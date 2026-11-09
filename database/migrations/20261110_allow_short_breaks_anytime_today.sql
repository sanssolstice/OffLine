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
    v_status:='scheduled';
  ELSE
    IF length(trim(COALESCE(p_reason,'')))<3 THEN
      RAISE EXCEPTION 'A reason is required for leave';
    END IF;
    IF p_starts_at>now()+interval '180 days' OR p_ends_at>now()+interval '181 days' THEN
      RAISE EXCEPTION 'Leave can be scheduled up to six months ahead';
    END IF;
    v_status:='pending';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.offline_window_interruptions x
    WHERE x.window_id=p_window_id AND x.status IN ('pending','scheduled')
      AND tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')
  ) THEN RAISE EXCEPTION 'This window already has a break or leave in that time range'; END IF;

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
    v_cancelled:=public.offline_finalize_interruption(v_id);
  END IF;

  RETURN QUERY SELECT v_id,v_status,v_cancelled;
END;
$function$;
