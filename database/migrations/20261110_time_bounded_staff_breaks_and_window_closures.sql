-- Time-bounded staff breaks, approval-based leave, and administrator window closures.
CREATE TABLE IF NOT EXISTS public.offline_window_interruptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  window_id uuid NOT NULL REFERENCES public.offline_windows(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('short_break','staff_leave','admin_closure')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  reason text NOT NULL DEFAULT '',
  status text NOT NULL CHECK (status IN ('pending','scheduled','rejected','cancelled','completed')),
  created_by uuid REFERENCES public.offline_profiles(id) ON DELETE SET NULL,
  reviewed_by uuid REFERENCES public.offline_profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);
CREATE INDEX IF NOT EXISTS idx_offline_interruptions_window_time
  ON public.offline_window_interruptions(window_id, starts_at, ends_at, status);
CREATE INDEX IF NOT EXISTS idx_offline_interruptions_pending
  ON public.offline_window_interruptions(created_at DESC) WHERE status='pending';

ALTER TABLE public.offline_tokens
  ADD COLUMN IF NOT EXISTS interruption_id uuid
  REFERENCES public.offline_window_interruptions(id) ON DELETE SET NULL;
ALTER TABLE public.offline_admin_notifications
  ADD COLUMN IF NOT EXISTS interruption_id uuid
  REFERENCES public.offline_window_interruptions(id) ON DELETE SET NULL;

ALTER TABLE public.offline_window_interruptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.offline_window_interruptions FROM PUBLIC, anon;
GRANT SELECT ON public.offline_window_interruptions TO authenticated;
DROP POLICY IF EXISTS offline_interruptions_read_relevant ON public.offline_window_interruptions;
CREATE POLICY offline_interruptions_read_relevant ON public.offline_window_interruptions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.offline_windows w
      WHERE w.id = offline_window_interruptions.window_id
        AND w.staff_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM public.offline_tokens t
      WHERE t.interruption_id = offline_window_interruptions.id
        AND t.student_id = (SELECT auth.uid())
    )
  );
DROP POLICY IF EXISTS offline_interruptions_no_client_mutations ON public.offline_window_interruptions;
CREATE POLICY offline_interruptions_no_client_mutations ON public.offline_window_interruptions
  FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- Internal helper: activate an interruption and cancel only future tokens that
-- overlap the unavailable range. Each cancelled student receives their own alert
-- through offline_notify_token_event; unrelated users do not receive anything.
CREATE OR REPLACE FUNCTION public.offline_finalize_interruption(p_interruption_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_interrupt public.offline_window_interruptions%rowtype;
  v_count integer := 0;
  v_staff_id uuid;
  v_window_name text;
BEGIN
  SELECT * INTO v_interrupt
  FROM public.offline_window_interruptions
  WHERE id = p_interruption_id
  FOR UPDATE;

  IF NOT FOUND OR v_interrupt.status <> 'scheduled' THEN
    RAISE EXCEPTION 'The interruption is not scheduled';
  END IF;

  SELECT staff_id, name INTO v_staff_id, v_window_name
  FROM public.offline_windows WHERE id = v_interrupt.window_id;

  UPDATE public.offline_tokens AS t
  SET status = 'cancelled',
      cancellation_type = 'emergency',
      cancellation_reason = COALESCE(NULLIF(v_interrupt.reason,''), 'Service window unavailable'),
      interruption_id = v_interrupt.id
  FROM public.offline_slots AS s
  WHERE s.id = t.slot_id
    AND t.window_id = v_interrupt.window_id
    AND t.status IN ('booked','arrived')
    AND s.starts_at < v_interrupt.ends_at
    AND s.ends_at > v_interrupt.starts_at
    AND s.starts_at > now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- Notify only the staff member assigned to this window for administrator
  -- closures and approved leave. A staff member scheduling their own short break
  -- already initiated it and needs no duplicate notification.
  IF v_staff_id IS NOT NULL AND v_interrupt.kind <> 'short_break' THEN
    INSERT INTO public.offline_notifications(user_id, title, body, kind)
    VALUES (
      v_staff_id,
      CASE WHEN v_interrupt.kind='staff_leave' THEN 'Leave approved' ELSE 'Window closure scheduled' END,
      format('%s: unavailable %s–%s. Expected reopening: %s. %s',
        COALESCE(v_window_name,'Your service window'),
        to_char(v_interrupt.starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
        to_char(v_interrupt.ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
        to_char(v_interrupt.ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
        COALESCE(NULLIF(v_interrupt.reason,''),'')
      ),
      'window'
    );
  END IF;

  RETURN v_count;
END;
$function$;
REVOKE ALL ON FUNCTION public.offline_finalize_interruption(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.offline_finalize_interruption(uuid) TO service_role;

-- Staff may start a same-day short break immediately, or submit a leave request
-- with a time range and reason. Leave remains pending until admin approval.
CREATE OR REPLACE FUNCTION public.offline_staff_schedule_interruption(
  p_window_id uuid,
  p_kind text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason text DEFAULT ''
)
RETURNS TABLE(interruption_id uuid, interruption_status text, cancelled_tokens integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_profile public.offline_profiles%rowtype;
  v_window public.offline_windows%rowtype;
  v_id uuid;
  v_status text;
  v_cancelled integer := 0;
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Please sign in first'; END IF;
  SELECT * INTO v_profile FROM public.offline_profiles
  WHERE id=v_user AND role='staff' AND account_status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'An active staff account is required'; END IF;

  SELECT * INTO v_window FROM public.offline_windows
  WHERE id=p_window_id AND staff_id=v_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'You are not assigned to this service window'; END IF;

  IF p_kind NOT IN ('short_break','staff_leave') THEN
    RAISE EXCEPTION 'Choose a short break or a leave request';
  END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at OR p_starts_at < now() - interval '30 seconds' THEN
    RAISE EXCEPTION 'Choose a valid future time range';
  END IF;
  IF p_kind='short_break' THEN
    IF (p_starts_at AT TIME ZONE 'Asia/Kolkata')::date <> v_today
       OR (p_ends_at AT TIME ZONE 'Asia/Kolkata')::date <> v_today
       OR p_ends_at > ((v_today+1)::timestamp AT TIME ZONE 'Asia/Kolkata')
       OR p_ends_at > now() + interval '8 hours' THEN
      RAISE EXCEPTION 'A short break must fit within today';
    END IF;
    v_status := 'scheduled';
  ELSE
    IF length(trim(COALESCE(p_reason,''))) < 3 THEN
      RAISE EXCEPTION 'A reason is required for leave';
    END IF;
    IF p_starts_at > now() + interval '180 days' OR p_ends_at > now() + interval '181 days' THEN
      RAISE EXCEPTION 'Leave can be scheduled up to six months ahead';
    END IF;
    v_status := 'pending';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.offline_window_interruptions x
    WHERE x.window_id=p_window_id AND x.status IN ('pending','scheduled')
      AND tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')
  ) THEN
    RAISE EXCEPTION 'This window already has a break or leave in that time range';
  END IF;

  INSERT INTO public.offline_window_interruptions(window_id,kind,starts_at,ends_at,reason,status,created_by)
  VALUES(p_window_id,p_kind,p_starts_at,p_ends_at,
    CASE WHEN p_kind='short_break' THEN 'Staff short break' ELSE trim(p_reason) END,
    v_status,v_user)
  RETURNING id INTO v_id;

  IF p_kind='staff_leave' THEN
    INSERT INTO public.offline_admin_notifications(interruption_id,title,body,kind)
    VALUES(v_id,'Staff leave approval needed',
      format('%s requested leave for %s from %s to %s. Reason: %s',
        v_profile.full_name,v_window.name,
        to_char(p_starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
        to_char(p_ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
        trim(p_reason)),'leave');
  ELSE
    v_cancelled := public.offline_finalize_interruption(v_id);
  END IF;

  RETURN QUERY SELECT v_id,v_status,v_cancelled;
END;
$function$;
REVOKE ALL ON FUNCTION public.offline_staff_schedule_interruption(uuid,text,timestamptz,timestamptz,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.offline_staff_schedule_interruption(uuid,text,timestamptz,timestamptz,text) TO authenticated;

-- Admin-originated closures are already approved by the administrator's
-- authenticated admin-session Edge Function. No separate request is needed.
CREATE OR REPLACE FUNCTION public.offline_admin_schedule_window_closure(
  p_window_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason text
)
RETURNS TABLE(interruption_id uuid,cancelled_tokens integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_role text := current_setting('request.jwt.claim.role',true);
  v_id uuid;
  v_count integer;
BEGIN
  IF v_role <> 'service_role' THEN RAISE EXCEPTION 'Administrator service access required'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason))<3 THEN RAISE EXCEPTION 'A closure reason is required'; END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at<=p_starts_at OR p_starts_at<now()-interval '30 seconds' THEN
    RAISE EXCEPTION 'Choose a valid future time range';
  END IF;
  IF p_ends_at>p_starts_at+interval '24 hours' THEN RAISE EXCEPTION 'A window closure cannot exceed 24 hours'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.offline_window_interruptions x
    WHERE x.window_id=p_window_id AND x.status IN ('pending','scheduled')
      AND tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')
  ) THEN RAISE EXCEPTION 'This window already has a break or closure in that time range'; END IF;

  INSERT INTO public.offline_window_interruptions(window_id,kind,starts_at,ends_at,reason,status)
  VALUES(p_window_id,'admin_closure',p_starts_at,p_ends_at,trim(p_reason),'scheduled')
  RETURNING id INTO v_id;

  v_count := public.offline_finalize_interruption(v_id);
  RETURN QUERY SELECT v_id,v_count;
END;
$function$;
REVOKE ALL ON FUNCTION public.offline_admin_schedule_window_closure(uuid,timestamptz,timestamptz,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.offline_admin_schedule_window_closure(uuid,timestamptz,timestamptz,text) TO service_role;

CREATE OR REPLACE FUNCTION public.offline_admin_review_interruption(
  p_interruption_id uuid,
  p_approved boolean
)
RETURNS TABLE(interruption_status text,cancelled_tokens integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_role text := current_setting('request.jwt.claim.role',true);
  v_row public.offline_window_interruptions%rowtype;
  v_user_id uuid;
  v_count integer := 0;
  v_window_name text;
BEGIN
  IF v_role <> 'service_role' THEN RAISE EXCEPTION 'Administrator service access required'; END IF;
  SELECT x.* INTO v_row
  FROM public.offline_window_interruptions x
  WHERE x.id=p_interruption_id
  FOR UPDATE;

  SELECT w.name INTO v_window_name
  FROM public.offline_windows w
  WHERE w.id=v_row.window_id;
  IF NOT FOUND OR v_row.status<>'pending' OR v_row.kind<>'staff_leave' THEN
    RAISE EXCEPTION 'This leave request is no longer pending';
  END IF;

  v_user_id := v_row.created_by;
  IF p_approved THEN
    UPDATE public.offline_window_interruptions
      SET status='scheduled', reviewed_at=now()
      WHERE id=p_interruption_id;
    v_count := public.offline_finalize_interruption(p_interruption_id);
    UPDATE public.offline_window_interruptions SET reviewed_by=NULL WHERE id=p_interruption_id;
    IF v_user_id IS NOT NULL THEN
      INSERT INTO public.offline_notifications(user_id,title,body,kind)
      VALUES(v_user_id,'Leave approved',
        format('Your leave for %s is approved from %s to %s. Affected students have been notified.',
          v_window_name,
          to_char(v_row.starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
          to_char(v_row.ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM')),'leave');
    END IF;
    RETURN QUERY SELECT 'scheduled'::text,v_count;
  ELSE
    UPDATE public.offline_window_interruptions
      SET status='rejected', reviewed_at=now()
      WHERE id=p_interruption_id;
    IF v_user_id IS NOT NULL THEN
      INSERT INTO public.offline_notifications(user_id,title,body,kind)
      VALUES(v_user_id,'Leave request declined',
        format('Your leave request for %s from %s to %s was declined.',
          v_window_name,
          to_char(v_row.starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
          to_char(v_row.ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM')),'leave');
    END IF;
    RETURN QUERY SELECT 'rejected'::text,0;
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.offline_admin_review_interruption(uuid,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.offline_admin_review_interruption(uuid,boolean) TO service_role;

-- Use the same unavailable ranges in the authoritative booking transaction.
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
  v_reopen timestamptz;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Please sign in first'; END IF;
  SELECT * INTO v_profile FROM public.offline_profiles
  WHERE id=v_user AND account_status='active';
  IF NOT FOUND OR v_profile.role<>'student' THEN RAISE EXCEPTION 'An active student account is required'; END IF;

  SELECT * INTO v_slot FROM public.offline_slots WHERE id=p_slot_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Slot not found'; END IF;
  IF v_slot.slot_date<v_today OR v_slot.slot_date>(v_today+1) THEN
    RAISE EXCEPTION 'Bookings are available only for today and tomorrow';
  END IF;

  SELECT * INTO v_win FROM public.offline_windows WHERE id=v_slot.window_id FOR UPDATE;
  IF NOT FOUND OR v_win.status<>'open' THEN RAISE EXCEPTION 'This service window is not open'; END IF;
  IF v_slot.starts_at<=now() THEN RAISE EXCEPTION 'This slot has already started'; END IF;

  SELECT x.ends_at INTO v_reopen
  FROM public.offline_window_interruptions x
  WHERE x.window_id=v_win.id AND x.status='scheduled'
    AND tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(v_slot.starts_at,v_slot.ends_at,'[)')
  ORDER BY x.ends_at DESC LIMIT 1;
  IF v_reopen IS NOT NULL THEN
    RAISE EXCEPTION 'This window is unavailable during the selected slot. It is expected to reopen at %',
      to_char(v_reopen AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM');
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text||':'||v_win.work_id::text||':'||v_slot.slot_date::text,0)
  );
  IF EXISTS (
    SELECT 1 FROM public.offline_tokens t
    JOIN public.offline_windows win ON win.id=t.window_id
    JOIN public.offline_slots booked_slot ON booked_slot.id=t.slot_id
    WHERE t.student_id=v_user AND win.work_id=v_win.work_id
      AND booked_slot.slot_date=v_slot.slot_date AND t.status<>'cancelled'
  ) THEN RAISE EXCEPTION 'You already have a token for this service today. Cancel the earlier token before booking again.'; END IF;

  SELECT count(*) INTO v_used FROM public.offline_tokens WHERE slot_id=p_slot_id AND status<>'cancelled';
  IF v_used>=v_slot.capacity THEN RAISE EXCEPTION 'This slot is full. Please choose another one'; END IF;

  SELECT coalesce(max(token_number),0)+1 INTO v_num FROM public.offline_tokens WHERE window_id=v_slot.window_id;
  SELECT count(*)+1 INTO v_pos FROM public.offline_tokens
    WHERE slot_id=p_slot_id AND status IN ('booked','arrived','serving');
  INSERT INTO public.offline_tokens(student_id,slot_id,window_id,token_number,queue_position)
  VALUES(v_user,p_slot_id,v_slot.window_id,v_num,v_pos) RETURNING * INTO v_token;
  RETURN v_token;
END;
$function$;

-- Update the notification routing: booking goes to the student and their assigned
-- counter staff; operational leave alerts go to administrators; interruption
-- cancellations go only to the students whose tokens were cancelled.
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
  v_interruption public.offline_window_interruptions%rowtype;
  v_title text;
  v_body text;
BEGIN
  SELECT p.full_name,win.staff_id,win.name,work.name,sl.starts_at
    INTO v_student_name,v_staff_id,v_window_name,v_service_name,v_starts_at
  FROM public.offline_windows win
  JOIN public.offline_works work ON work.id=win.work_id
  JOIN public.offline_slots sl ON sl.id=NEW.slot_id
  LEFT JOIN public.offline_profiles p ON p.id=NEW.student_id
  WHERE win.id=NEW.window_id;
  v_student_name:=COALESCE(v_student_name,'Student');
  v_window_name:=COALESCE(v_window_name,'Campus counter');
  v_service_name:=COALESCE(v_service_name,'Campus service');

  IF TG_OP='INSERT' THEN
    IF NEW.student_id IS NOT NULL THEN
      INSERT INTO public.offline_notifications(user_id,token_id,title,body,kind)
      VALUES(NEW.student_id,NEW.id,'Booking confirmed',
        format('Token #%s for %s is booked at %s on %s.',
          NEW.token_number,v_service_name,v_window_name,
          to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM')),'booking');
    END IF;
    IF v_staff_id IS NOT NULL AND EXISTS(
      SELECT 1 FROM public.offline_profiles p
      WHERE p.id=v_staff_id AND p.role='staff' AND p.account_status='active'
    ) THEN
      INSERT INTO public.offline_notifications(user_id,token_id,title,body,kind)
      VALUES(v_staff_id,NEW.id,'New student booking',
        format('%s booked %s for %s at %s.',v_student_name,v_service_name,
          to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon'),
          to_char(v_starts_at AT TIME ZONE 'Asia/Kolkata','HH12:MI AM')),'booking');
    END IF;
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status='arrived' THEN
      v_title:='Arrival confirmed';v_body:=format('Your arrival for %s at %s has been recorded.',v_service_name,v_window_name);
    ELSIF NEW.status='serving' THEN
      v_title:='Your turn is ready';v_body:=format('Please proceed to %s for %s.',v_window_name,v_service_name);
    ELSIF NEW.status='completed' THEN
      v_title:='Service completed';v_body:=format('Your %s visit at %s is complete. Thank you.',v_service_name,v_window_name);
    ELSIF NEW.status='cancelled' THEN
      IF NEW.interruption_id IS NOT NULL THEN
        SELECT * INTO v_interruption FROM public.offline_window_interruptions WHERE id=NEW.interruption_id;
        v_title:='Appointment cancelled — window unavailable';
        v_body:=format('Token #%s for %s at %s was cancelled because the window is unavailable from %s to %s. Expected reopening: %s. Reason: %s',
          NEW.token_number,v_service_name,v_window_name,
          to_char(v_interruption.starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
          to_char(v_interruption.ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
          to_char(v_interruption.ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
          COALESCE(NULLIF(v_interruption.reason,''),'Not specified'));
      ELSE
        v_title:='Booking cancelled';
        v_body:=format('Token #%s for %s at %s has been cancelled.',NEW.token_number,v_service_name,v_window_name);
      END IF;
    ELSE
      v_title:=NULL;v_body:=NULL;
    END IF;

    IF NEW.student_id IS NOT NULL AND v_title IS NOT NULL THEN
      INSERT INTO public.offline_notifications(user_id,token_id,title,body,kind)
      VALUES(NEW.student_id,NEW.id,v_title,v_body,
        CASE WHEN NEW.status='cancelled' THEN 'cancellation' ELSE 'queue' END);
    END IF;

    IF NEW.status='cancelled' AND NEW.cancellation_type='student'
       AND v_staff_id IS NOT NULL AND EXISTS(
         SELECT 1 FROM public.offline_profiles p
         WHERE p.id=v_staff_id AND p.role='staff' AND p.account_status='active'
       ) THEN
      INSERT INTO public.offline_notifications(user_id,token_id,title,body,kind)
      VALUES(v_staff_id,NEW.id,'Student cancelled a booking',
        format('%s cancelled token #%s for %s.',v_student_name,NEW.token_number,v_service_name),'cancellation');
    ELSIF NEW.status='cancelled' AND NEW.cancellation_type='late_no_show' THEN
      INSERT INTO public.offline_admin_notifications(token_id,title,body,kind)
      VALUES(NEW.id,'Booking marked no-show',
        format('%s marked token #%s for %s at %s as a no-show.',
          v_student_name,NEW.token_number,v_service_name,v_window_name),'cancellation');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- Old break-request flow is retired; new leave requests use the interruption table.
-- Keep the table for audit compatibility, but it no longer receives new inserts.

DO $publication$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public'
      AND tablename='offline_window_interruptions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.offline_window_interruptions;
  END IF;
END;
$publication$;
