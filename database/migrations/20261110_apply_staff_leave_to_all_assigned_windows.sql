-- A staff leave is a person-level absence: schedule it across every window
-- assigned to that staff member and approve/reject the whole request together.
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
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at<=p_starts_at OR p_starts_at<now()-interval '30 seconds' THEN
    RAISE EXCEPTION 'Choose a valid future time range';
  END IF;

  IF p_kind='short_break' THEN
    IF (p_starts_at AT TIME ZONE 'Asia/Kolkata')::date<>v_today
       OR (p_ends_at AT TIME ZONE 'Asia/Kolkata')::date<>v_today
       OR p_ends_at>((v_today+1)::timestamp AT TIME ZONE 'Asia/Kolkata') THEN
      RAISE EXCEPTION 'A short break must fit within today';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.offline_window_interruptions x
      WHERE x.window_id=p_window_id AND x.status IN ('pending','scheduled')
        AND tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')
    ) THEN RAISE EXCEPTION 'This window already has a break or leave in that time range'; END IF;

    v_status:='scheduled';
    INSERT INTO public.offline_window_interruptions(window_id,kind,starts_at,ends_at,reason,status,created_by)
    VALUES(p_window_id,'short_break',p_starts_at,p_ends_at,'Staff short break','scheduled',v_user)
    RETURNING id INTO v_id;

    v_cancelled:=public.offline_finalize_interruption(v_id);
    RETURN QUERY SELECT v_id,v_status,v_cancelled;
    RETURN;
  END IF;

  -- Leave requires a reason and applies to every window assigned to this staffer.
  IF length(trim(COALESCE(p_reason,'')))<3 THEN
    RAISE EXCEPTION 'A reason is required for leave';
  END IF;
  IF p_starts_at>now()+interval '180 days' OR p_ends_at>now()+interval '181 days' THEN
    RAISE EXCEPTION 'Leave can be scheduled up to six months ahead';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.offline_window_interruptions x
    JOIN public.offline_windows w ON w.id=x.window_id
    WHERE w.staff_id=v_user AND x.status IN ('pending','scheduled')
      AND tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')
  ) THEN RAISE EXCEPTION 'One of your assigned windows already has a break or leave in that time range'; END IF;

  v_status:='pending';
  FOR v_window IN
    SELECT * FROM public.offline_windows
    WHERE staff_id=v_user
    ORDER BY name
    FOR UPDATE
  LOOP
    INSERT INTO public.offline_window_interruptions(window_id,kind,starts_at,ends_at,reason,status,created_by)
    VALUES(v_window.id,'staff_leave',p_starts_at,p_ends_at,trim(p_reason),'pending',v_user)
    RETURNING id INTO v_id;

    INSERT INTO public.offline_admin_notifications(interruption_id,title,body,kind)
    VALUES(v_id,'Staff leave approval needed',
      format('%s requested leave across assigned service windows (%s) from %s to %s. Reason: %s',
        v_profile.full_name,v_window.name,
        to_char(p_starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
        to_char(p_ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
        trim(p_reason)),'leave');

    RETURN QUERY SELECT v_id,v_status,0;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.offline_staff_schedule_interruption(uuid,text,timestamptz,timestamptz,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.offline_staff_schedule_interruption(uuid,text,timestamptz,timestamptz,text) TO authenticated;

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
  v_target record;
  v_window_names text;
BEGIN
  IF v_role<>'service_role' THEN RAISE EXCEPTION 'Administrator service access required'; END IF;

  SELECT x.* INTO v_row
  FROM public.offline_window_interruptions x
  WHERE x.id=p_interruption_id
  FOR UPDATE;
  IF NOT FOUND OR v_row.status<>'pending' OR v_row.kind<>'staff_leave' THEN
    RAISE EXCEPTION 'This leave request is no longer pending';
  END IF;
  v_user_id:=v_row.created_by;

  IF p_approved THEN
    UPDATE public.offline_window_interruptions
      SET status='scheduled',reviewed_at=now()
      WHERE created_by=v_user_id AND kind='staff_leave' AND status='pending'
        AND starts_at=v_row.starts_at AND ends_at=v_row.ends_at AND reason=v_row.reason;

    FOR v_target IN
      SELECT x.id FROM public.offline_window_interruptions x
      WHERE x.created_by=v_user_id AND x.kind='staff_leave' AND x.status='scheduled'
        AND x.starts_at=v_row.starts_at AND x.ends_at=v_row.ends_at AND x.reason=v_row.reason
    LOOP
      v_count:=v_count+public.offline_finalize_interruption(v_target.id);
    END LOOP;

    SELECT string_agg(w.name,', ' ORDER BY w.name) INTO v_window_names
    FROM public.offline_window_interruptions x
    JOIN public.offline_windows w ON w.id=x.window_id
    WHERE x.created_by=v_user_id AND x.kind='staff_leave' AND x.status='scheduled'
      AND x.starts_at=v_row.starts_at AND x.ends_at=v_row.ends_at AND x.reason=v_row.reason;

    IF v_user_id IS NOT NULL THEN
      INSERT INTO public.offline_notifications(user_id,title,body,kind)
      VALUES(v_user_id,'Leave approved',
        format('Your leave across %s is approved from %s to %s. Affected students have been notified.',
          COALESCE(v_window_names,'your assigned windows'),
          to_char(v_row.starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
          to_char(v_row.ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM')),'leave');
    END IF;
    RETURN QUERY SELECT 'scheduled'::text,v_count;
  ELSE
    UPDATE public.offline_window_interruptions
      SET status='rejected',reviewed_at=now()
      WHERE created_by=v_user_id AND kind='staff_leave' AND status='pending'
        AND starts_at=v_row.starts_at AND ends_at=v_row.ends_at AND reason=v_row.reason;

    SELECT string_agg(w.name,', ' ORDER BY w.name) INTO v_window_names
    FROM public.offline_window_interruptions x
    JOIN public.offline_windows w ON w.id=x.window_id
    WHERE x.created_by=v_user_id AND x.kind='staff_leave' AND x.status='rejected'
      AND x.starts_at=v_row.starts_at AND x.ends_at=v_row.ends_at AND x.reason=v_row.reason;

    IF v_user_id IS NOT NULL THEN
      INSERT INTO public.offline_notifications(user_id,title,body,kind)
      VALUES(v_user_id,'Leave request declined',
        format('Your leave request across %s from %s to %s was declined.',
          COALESCE(v_window_names,'your assigned windows'),
          to_char(v_row.starts_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM'),
          to_char(v_row.ends_at AT TIME ZONE 'Asia/Kolkata','DD Mon HH12:MI AM')),'leave');
    END IF;
    RETURN QUERY SELECT 'rejected'::text,0;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.offline_admin_review_interruption(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.offline_admin_review_interruption(uuid,boolean) TO service_role;
