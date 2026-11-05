-- Canonical source for the migration already applied to the live project.
-- Applied migration: live ETA, durable notifications and same-work/day booking guard.
-- Limits booking dates to the local calendar day and the following day.
ALTER TABLE public.offline_tokens ALTER COLUMN student_id DROP NOT NULL;
ALTER TABLE public.offline_break_requests ALTER COLUMN requested_by DROP NOT NULL;

CREATE TABLE IF NOT EXISTS public.offline_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.offline_profiles(id) ON DELETE CASCADE,
  token_id uuid REFERENCES public.offline_tokens(id) ON DELETE SET NULL,
  title text NOT NULL,
  body text NOT NULL,
  kind text NOT NULL DEFAULT 'info',
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_offline_notifications_user_created
  ON public.offline_notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_offline_notifications_unread
  ON public.offline_notifications(user_id, created_at DESC) WHERE read_at IS NULL;

CREATE TABLE IF NOT EXISTS public.offline_admin_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_id uuid REFERENCES public.offline_tokens(id) ON DELETE SET NULL,
  break_request_id uuid REFERENCES public.offline_break_requests(id) ON DELETE SET NULL,
  title text NOT NULL,
  body text NOT NULL,
  kind text NOT NULL DEFAULT 'info',
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_offline_admin_notifications_created
  ON public.offline_admin_notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_offline_admin_notifications_unread
  ON public.offline_admin_notifications(created_at DESC) WHERE read_at IS NULL;

CREATE TABLE IF NOT EXISTS public.offline_queue_activity (
  window_id uuid NOT NULL REFERENCES public.offline_windows(id) ON DELETE CASCADE,
  slot_date date NOT NULL,
  revision bigint NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(window_id,slot_date)
);

ALTER TABLE public.offline_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.offline_notifications FROM PUBLIC, anon;
GRANT SELECT ON public.offline_notifications TO authenticated;
GRANT UPDATE(read_at) ON public.offline_notifications TO authenticated;
DROP POLICY IF EXISTS offline_notifications_read_own ON public.offline_notifications;
CREATE POLICY offline_notifications_read_own ON public.offline_notifications
  FOR SELECT TO authenticated
  USING(user_id=(SELECT auth.uid()) AND public.offline_current_user_role() IN ('student','staff'));
DROP POLICY IF EXISTS offline_notifications_mark_own_read ON public.offline_notifications;
CREATE POLICY offline_notifications_mark_own_read ON public.offline_notifications
  FOR UPDATE TO authenticated
  USING(user_id=(SELECT auth.uid()) AND public.offline_current_user_role() IN ('student','staff'))
  WITH CHECK(user_id=(SELECT auth.uid()) AND public.offline_current_user_role() IN ('student','staff'));

ALTER TABLE public.offline_admin_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.offline_admin_notifications FROM PUBLIC, anon, authenticated;

ALTER TABLE public.offline_queue_activity ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.offline_queue_activity FROM PUBLIC, anon;
GRANT SELECT ON public.offline_queue_activity TO authenticated;
DROP POLICY IF EXISTS offline_queue_activity_read_relevant ON public.offline_queue_activity;
CREATE POLICY offline_queue_activity_read_relevant ON public.offline_queue_activity
  FOR SELECT TO authenticated
  USING(
    public.offline_current_user_role() IN ('student','staff')
    AND (
      EXISTS(SELECT 1 FROM public.offline_windows w
        WHERE w.id=offline_queue_activity.window_id AND w.staff_id=(SELECT auth.uid()))
      OR EXISTS(SELECT 1 FROM public.offline_tokens t
        JOIN public.offline_slots s ON s.id=t.slot_id
        WHERE t.student_id=(SELECT auth.uid())
          AND t.window_id=offline_queue_activity.window_id
          AND s.slot_date=offline_queue_activity.slot_date
          AND t.status IN ('booked','arrived','serving'))
    )
  );

CREATE OR REPLACE FUNCTION public.offline_book_token(p_slot_id uuid)
 RETURNS offline_tokens
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
    FROM public.offline_tokens t
    JOIN public.offline_windows win ON win.id = t.window_id
    JOIN public.offline_slots booked_slot ON booked_slot.id = t.slot_id
    WHERE t.student_id = v_user
      AND win.work_id = v_win.work_id
      AND booked_slot.slot_date = v_slot.slot_date
      AND t.status <> 'cancelled'
  ) THEN
    RAISE EXCEPTION 'You already have a token for this service today. Cancel the earlier token before booking again.';
  END IF;

  SELECT count(*) INTO v_used
  FROM public.offline_tokens
  WHERE slot_id = p_slot_id AND status IN ('booked','arrived','serving');

  IF v_used >= v_slot.capacity THEN
    RAISE EXCEPTION 'This slot is full. Please choose another one';
  END IF;

  SELECT coalesce(max(token_number), 0) + 1 INTO v_num
  FROM public.offline_tokens
  WHERE window_id = v_slot.window_id;

  SELECT count(*) + 1 INTO v_pos
  FROM public.offline_tokens
  WHERE slot_id = p_slot_id AND status IN ('booked','arrived','serving');

  INSERT INTO public.offline_tokens(student_id, slot_id, window_id, token_number, queue_position)
  VALUES (v_user, p_slot_id, v_slot.window_id, v_num, v_pos)
  RETURNING * INTO v_token;

  RETURN v_token;
END;
$function$;

CREATE OR REPLACE FUNCTION public.offline_bump_queue_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.offline_queue_activity(window_id, slot_date, revision, updated_at)
  SELECT NEW.window_id, s.slot_date, 1, now()
  FROM public.offline_slots s
  WHERE s.id = NEW.slot_id
  ON CONFLICT (window_id, slot_date)
  DO UPDATE SET
    revision = public.offline_queue_activity.revision + 1,
    updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.offline_notify_break_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_window_name text;
BEGIN
  SELECT name INTO v_window_name
  FROM public.offline_windows
  WHERE id = NEW.window_id;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.offline_admin_notifications(break_request_id, title, body, kind)
    VALUES (
      NEW.id, 'Staff break request',
      format('%s requested a break at %s: %s',
        COALESCE((SELECT p.full_name FROM public.offline_profiles p WHERE p.id = NEW.requested_by), 'A staff member'),
        COALESCE(v_window_name, 'a service window'), NEW.reason),
      'break'
    );
  ELSIF NEW.status IS DISTINCT FROM OLD.status AND NEW.requested_by IS NOT NULL THEN
    INSERT INTO public.offline_notifications(user_id, title, body, kind)
    VALUES (
      NEW.requested_by,
      CASE WHEN NEW.status = 'approved' THEN 'Break request approved' ELSE 'Break request reviewed' END,
      format('Your break request for %s was %s.', COALESCE(v_window_name, 'your service window'), NEW.status),
      'break'
    );
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.offline_notify_token_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_student_name text := 'Student';
  v_staff_id uuid;
  v_window_name text := 'Campus counter';
  v_service_name text := 'Campus service';
  v_starts_at timestamptz;
  v_slot_date date;
  v_title text;
  v_body text;
BEGIN
  SELECT p.full_name, win.staff_id, win.name, work.name, sl.starts_at, sl.slot_date
    INTO v_student_name, v_staff_id, v_window_name, v_service_name, v_starts_at, v_slot_date
  FROM public.offline_windows win
  JOIN public.offline_works work ON work.id = win.work_id
  JOIN public.offline_slots sl ON sl.id = NEW.slot_id
  LEFT JOIN public.offline_profiles p ON p.id = NEW.student_id
  WHERE win.id = NEW.window_id;

  v_student_name := COALESCE(v_student_name, 'Student');
  v_window_name := COALESCE(v_window_name, 'Campus counter');
  v_service_name := COALESCE(v_service_name, 'Campus service');

  IF TG_OP = 'INSERT' THEN
    IF NEW.student_id IS NOT NULL THEN
      INSERT INTO public.offline_notifications(user_id, token_id, title, body, kind)
      VALUES (
        NEW.student_id, NEW.id, 'Booking confirmed',
        format('Token #%s for %s is booked at %s on %s, %s.',
          NEW.token_number, v_service_name, v_window_name,
          to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon'),
          to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')),
        'booking'
      );
    END IF;

    IF v_staff_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.offline_profiles p
      WHERE p.id = v_staff_id AND p.role = 'staff' AND p.account_status = 'active'
    ) THEN
      INSERT INTO public.offline_notifications(user_id, token_id, title, body, kind)
      VALUES (
        v_staff_id, NEW.id, 'New student booking',
        format('%s booked %s for %s at %s.',
          v_student_name, v_service_name,
          to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon'),
          to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')),
        'booking'
      );
    END IF;

    INSERT INTO public.offline_admin_notifications(token_id, title, body, kind)
    VALUES (
      NEW.id, 'New campus booking',
      format('%s booked %s at %s for %s, %s.',
        v_student_name, v_service_name, v_window_name,
        to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon'),
        to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')),
      'booking'
    );

  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'arrived' THEN
      v_title := 'Arrival confirmed';
      v_body := format('Your arrival for %s at %s has been recorded.', v_service_name, v_window_name);
    ELSIF NEW.status = 'serving' THEN
      v_title := 'Your turn is ready';
      v_body := format('Please proceed to %s for %s.', v_window_name, v_service_name);
    ELSIF NEW.status = 'completed' THEN
      v_title := 'Service completed';
      v_body := format('Your %s visit at %s is complete. Thank you.', v_service_name, v_window_name);
    ELSIF NEW.status = 'cancelled' THEN
      v_title := 'Booking cancelled';
      v_body := format('Token #%s for %s at %s has been cancelled.', NEW.token_number, v_service_name, v_window_name);
    ELSE
      v_title := NULL;
      v_body := NULL;
    END IF;

    IF NEW.student_id IS NOT NULL AND v_title IS NOT NULL THEN
      INSERT INTO public.offline_notifications(user_id, token_id, title, body, kind)
      VALUES (NEW.student_id, NEW.id, v_title, v_body,
        CASE WHEN NEW.status = 'cancelled' THEN 'cancellation' ELSE 'queue' END);
    END IF;

    IF NEW.status = 'cancelled'
       AND NEW.cancellation_type = 'student'
       AND v_staff_id IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.offline_profiles p
         WHERE p.id = v_staff_id AND p.role = 'staff' AND p.account_status = 'active'
       ) THEN
      INSERT INTO public.offline_notifications(user_id, token_id, title, body, kind)
      VALUES (
        v_staff_id, NEW.id, 'Student cancelled a booking',
        format('%s cancelled token #%s for %s.', v_student_name, NEW.token_number, v_service_name),
        'cancellation'
      );
    ELSIF NEW.status = 'cancelled' THEN
      INSERT INTO public.offline_admin_notifications(token_id, title, body, kind)
      VALUES (
        NEW.id, 'Booking cancelled',
        format('%s cancelled token #%s for %s at %s.',
          v_student_name, NEW.token_number, v_service_name, v_window_name),
        'cancellation'
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.offline_notify_window_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.staff_id IS NOT NULL THEN
    INSERT INTO public.offline_notifications(user_id, title, body, kind)
    VALUES (
      NEW.staff_id, 'Service window updated',
      format('%s is now %s.', NEW.name, NEW.status),
      'window'
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.offline_queue_estimates(p_window_ids uuid[])
 RETURNS TABLE(token_id uuid, window_id uuid, queue_position integer, wait_minutes integer, estimated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_role text := public.offline_current_user_role();
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF v_user IS NULL OR v_role NOT IN ('student','staff') THEN
    RAISE EXCEPTION 'An active student or staff account is required';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      t.id AS token_id,
      t.window_id,
      t.student_id,
      t.status,
      t.arrived_at,
      t.booked_at,
      t.service_started_at,
      s.slot_date,
      s.starts_at,
      work.avg_service_minutes
    FROM public.offline_tokens t
    JOIN public.offline_slots s ON s.id = t.slot_id
    JOIN public.offline_windows win ON win.id = t.window_id
    JOIN public.offline_works work ON work.id = win.work_id
    WHERE t.window_id = ANY(COALESCE(p_window_ids, ARRAY[]::uuid[]))
      AND t.status IN ('booked','arrived','serving')
      AND s.slot_date BETWEEN v_today AND (v_today + 1)
      AND (v_role = 'student' OR win.staff_id = v_user)
  ),
  ranked AS (
    SELECT
      b.*,
      row_number() OVER (
        PARTITION BY b.window_id, b.slot_date
        ORDER BY
          b.starts_at,
          CASE b.status WHEN 'serving' THEN 0 WHEN 'arrived' THEN 1 ELSE 2 END,
          COALESCE(b.arrived_at, b.booked_at)
      ) AS position_in_queue,
      max(
        CASE WHEN b.status = 'serving' THEN
          greatest(
            0::numeric,
            b.avg_service_minutes::numeric
              - extract(epoch FROM (now() - COALESCE(b.service_started_at, now()))) / 60
          )
        END
      ) OVER (PARTITION BY b.window_id, b.slot_date) AS serving_remaining,
      count(*) FILTER (WHERE b.status = 'serving')
        OVER (PARTITION BY b.window_id, b.slot_date) AS serving_count
    FROM base b
  ),
  estimates AS (
    SELECT
      r.*,
      CASE
        WHEN r.status = 'serving' THEN 0::numeric
        ELSE COALESCE(r.serving_remaining, 0::numeric)
          + greatest(r.position_in_queue - 1 - r.serving_count, 0) * r.avg_service_minutes
      END AS wait_value
    FROM ranked r
  )
  SELECT
    e.token_id,
    e.window_id,
    e.position_in_queue::integer,
    ceil(e.wait_value)::integer,
    greatest(now(), e.starts_at) + (ceil(e.wait_value)::integer * interval '1 minute')
  FROM estimates e
  WHERE v_role = 'staff' OR e.student_id = v_user
  ORDER BY e.slot_date, e.starts_at, e.position_in_queue;
END;
$function$;

REVOKE ALL ON FUNCTION public.offline_notify_token_event() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.offline_bump_queue_activity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.offline_notify_break_request() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.offline_notify_window_status() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.offline_queue_estimates(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.offline_queue_estimates(uuid[]) TO authenticated;
REVOKE ALL ON FUNCTION public.offline_book_token(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.offline_book_token(uuid) TO authenticated;

DROP TRIGGER IF EXISTS offline_bump_queue_activity ON public.offline_tokens;
CREATE TRIGGER offline_bump_queue_activity AFTER INSERT OR UPDATE OF status ON public.offline_tokens FOR EACH ROW EXECUTE FUNCTION offline_bump_queue_activity();

DROP TRIGGER IF EXISTS offline_notify_break_request ON public.offline_break_requests;
CREATE TRIGGER offline_notify_break_request AFTER INSERT OR UPDATE OF status ON public.offline_break_requests FOR EACH ROW EXECUTE FUNCTION offline_notify_break_request();

DROP TRIGGER IF EXISTS offline_notify_token_event ON public.offline_tokens;
CREATE TRIGGER offline_notify_token_event AFTER INSERT OR UPDATE OF status ON public.offline_tokens FOR EACH ROW EXECUTE FUNCTION offline_notify_token_event();

DROP TRIGGER IF EXISTS offline_notify_window_status ON public.offline_windows;
CREATE TRIGGER offline_notify_window_status AFTER UPDATE OF status ON public.offline_windows FOR EACH ROW EXECUTE FUNCTION offline_notify_window_status();

DO $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='offline_notifications') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.offline_notifications;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='offline_queue_activity') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.offline_queue_activity;
  END IF;
END;
$$;
