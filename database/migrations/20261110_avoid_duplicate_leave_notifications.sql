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
  WHERE id=p_interruption_id
  FOR UPDATE;

  IF NOT FOUND OR v_interrupt.status<>'scheduled' THEN
    RAISE EXCEPTION 'The interruption is not scheduled';
  END IF;

  SELECT staff_id,name INTO v_staff_id,v_window_name
  FROM public.offline_windows WHERE id=v_interrupt.window_id;

  UPDATE public.offline_tokens AS t
  SET status='cancelled',
      cancellation_type='emergency',
      cancellation_reason=COALESCE(NULLIF(v_interrupt.reason,''),'Service window unavailable'),
      interruption_id=v_interrupt.id
  FROM public.offline_slots AS s
  WHERE s.id=t.slot_id
    AND t.window_id=v_interrupt.window_id
    AND t.status IN ('booked','arrived')
    AND s.starts_at<v_interrupt.ends_at
    AND s.ends_at>v_interrupt.starts_at
    AND s.starts_at>now();

  GET DIAGNOSTICS v_count=ROW_COUNT;

  -- Staff leave is reported to the requester by the approval RPC itself.
  -- Only administrator-originated closures generate an additional staff alert.
  IF v_staff_id IS NOT NULL AND v_interrupt.kind='admin_closure' THEN
    INSERT INTO public.offline_notifications(user_id,title,body,kind)
    VALUES(
      v_staff_id,'Window closure scheduled',
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

REVOKE ALL ON FUNCTION public.offline_finalize_interruption(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.offline_finalize_interruption(uuid) TO service_role;
