-- Standardize slot capacity on the service's configured average handling time.
-- Every one-hour slot has 45 service minutes and a fixed 15-minute buffer.
-- Capacity is derived once from the service record and enforced by the database.

ALTER TABLE public.offline_works
  ADD COLUMN IF NOT EXISTS slot_capacity integer
  GENERATED ALWAYS AS (GREATEST(1, FLOOR(45.0 / avg_service_minutes)::integer)) STORED;

-- Never accept a capacity supplied by an individual client or stale slot generator.
CREATE OR REPLACE FUNCTION public.offline_enforce_slot_capacity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_capacity integer;
BEGIN
  SELECT work.slot_capacity
    INTO v_capacity
  FROM public.offline_windows AS win
  JOIN public.offline_works AS work ON work.id = win.work_id
  WHERE win.id = NEW.window_id;

  IF v_capacity IS NULL THEN
    RAISE EXCEPTION 'A valid service window is required to calculate slot capacity';
  END IF;

  NEW.capacity := v_capacity;
  NEW.buffer_minutes := 15;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.offline_enforce_slot_capacity() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS offline_slots_enforce_service_capacity ON public.offline_slots;
CREATE TRIGGER offline_slots_enforce_service_capacity
BEFORE INSERT OR UPDATE OF window_id, capacity ON public.offline_slots
FOR EACH ROW EXECUTE FUNCTION public.offline_enforce_slot_capacity();

-- Refresh future slots when an administrator changes a service's handling time
-- or moves a window to a different service. Existing token rows are untouched.
CREATE OR REPLACE FUNCTION public.offline_sync_future_slot_capacity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'offline_works' THEN
    UPDATE public.offline_slots AS slot
    SET capacity = work.slot_capacity
    FROM public.offline_windows AS win
    JOIN public.offline_works AS work ON work.id = win.work_id
    WHERE slot.window_id = win.id
      AND win.work_id = NEW.id
      AND slot.starts_at > now();
  ELSIF TG_TABLE_NAME = 'offline_windows' THEN
    UPDATE public.offline_slots AS slot
    SET capacity = work.slot_capacity
    FROM public.offline_works AS work
    WHERE slot.window_id = NEW.id
      AND work.id = NEW.work_id
      AND slot.starts_at > now();
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.offline_sync_future_slot_capacity() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS offline_works_sync_future_slot_capacity ON public.offline_works;
CREATE TRIGGER offline_works_sync_future_slot_capacity
AFTER UPDATE OF avg_service_minutes ON public.offline_works
FOR EACH ROW
WHEN (OLD.avg_service_minutes IS DISTINCT FROM NEW.avg_service_minutes)
EXECUTE FUNCTION public.offline_sync_future_slot_capacity();

DROP TRIGGER IF EXISTS offline_windows_sync_future_slot_capacity ON public.offline_windows;
CREATE TRIGGER offline_windows_sync_future_slot_capacity
AFTER UPDATE OF work_id ON public.offline_windows
FOR EACH ROW
WHEN (OLD.work_id IS DISTINCT FROM NEW.work_id)
EXECUTE FUNCTION public.offline_sync_future_slot_capacity();

-- Correct all upcoming legacy slots to the same generated service capacity.
-- This never removes or edits bookings already attached to those slots.
UPDATE public.offline_slots AS slot
SET capacity = work.slot_capacity
FROM public.offline_windows AS win
JOIN public.offline_works AS work ON work.id = win.work_id
WHERE slot.window_id = win.id
  AND slot.starts_at > now();

-- A booked/completed appointment consumes a reserved spot. Only cancellation
-- releases it, matching the booking RPC and the visible "spots left" counter.
CREATE OR REPLACE FUNCTION public.offline_slot_usage(p_slot_ids uuid[])
RETURNS TABLE(slot_id uuid, used_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT t.slot_id, count(*)::bigint
  FROM public.offline_tokens AS t
  WHERE (SELECT public.offline_current_user_role()) = 'student'
    AND t.slot_id = ANY(p_slot_ids)
    AND t.status <> 'cancelled'
  GROUP BY t.slot_id;
$function$;

CREATE OR REPLACE FUNCTION public.offline_book_token(p_slot_id uuid)
RETURNS public.offline_tokens
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_slot public.offline_slots%rowtype;
  v_win public.offline_windows%rowtype;
  v_profile public.offline_profiles%rowtype;
  v_num integer;
  v_pos integer;
  v_used integer;
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_token public.offline_tokens%rowtype;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Please sign in first'; END IF;

  SELECT * INTO v_profile
  FROM public.offline_profiles
  WHERE id = v_user AND account_status = 'active';

  IF NOT FOUND OR v_profile.role <> 'student' THEN
    RAISE EXCEPTION 'An active student account is required';
  END IF;

  SELECT * INTO v_slot
  FROM public.offline_slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Slot not found'; END IF;

  IF v_slot.slot_date < v_today OR v_slot.slot_date > (v_today + 1) THEN
    RAISE EXCEPTION 'Bookings are available only for today and tomorrow';
  END IF;

  SELECT * INTO v_win
  FROM public.offline_windows
  WHERE id = v_slot.window_id
  FOR UPDATE;

  IF NOT FOUND OR v_win.status <> 'open' THEN
    RAISE EXCEPTION 'This service window is not open';
  END IF;

  IF v_slot.starts_at <= now() THEN
    RAISE EXCEPTION 'This slot has already started';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_user::text || ':' || v_win.work_id::text || ':' || v_slot.slot_date::text,
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM public.offline_tokens AS t
    JOIN public.offline_windows AS win ON win.id = t.window_id
    JOIN public.offline_slots AS booked_slot ON booked_slot.id = t.slot_id
    WHERE t.student_id = v_user
      AND win.work_id = v_win.work_id
      AND booked_slot.slot_date = v_slot.slot_date
      AND t.status <> 'cancelled'
  ) THEN
    RAISE EXCEPTION 'You already have a token for this service today. Cancel the earlier token before booking again.';
  END IF;

  -- Completed bookings still consume a spot. A cancellation is the only
  -- transition that releases capacity for another student.
  SELECT count(*) INTO v_used
  FROM public.offline_tokens
  WHERE slot_id = p_slot_id
    AND status <> 'cancelled';

  IF v_used >= v_slot.capacity THEN
    RAISE EXCEPTION 'This slot is full. Please choose another one';
  END IF;

  SELECT coalesce(max(token_number), 0) + 1 INTO v_num
  FROM public.offline_tokens
  WHERE window_id = v_slot.window_id;

  -- Queue position is for people still waiting or being served, not history.
  SELECT count(*) + 1 INTO v_pos
  FROM public.offline_tokens
  WHERE slot_id = p_slot_id
    AND status IN ('booked','arrived','serving');

  INSERT INTO public.offline_tokens(student_id, slot_id, window_id, token_number, queue_position)
  VALUES (v_user, p_slot_id, v_slot.window_id, v_num, v_pos)
  RETURNING * INTO v_token;

  RETURN v_token;
END;
$function$;
