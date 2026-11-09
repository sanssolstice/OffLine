-- Let authenticated students see which selected slots overlap a scheduled window interruption.
CREATE OR REPLACE FUNCTION public.offline_unavailable_slots(p_slot_ids uuid[])
RETURNS TABLE(slot_id uuid,reopens_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT s.id, max(x.ends_at) AS reopens_at
  FROM public.offline_slots s
  JOIN public.offline_window_interruptions x
    ON x.window_id=s.window_id
   AND x.status='scheduled'
   AND tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(s.starts_at,s.ends_at,'[)')
  WHERE s.id=ANY(COALESCE(p_slot_ids,ARRAY[]::uuid[]))
    AND (SELECT public.offline_current_user_role())='student'
  GROUP BY s.id;
$function$;
REVOKE ALL ON FUNCTION public.offline_unavailable_slots(uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.offline_unavailable_slots(uuid[]) TO authenticated;

-- Keep the booking availability number consistent with the booking transaction:
-- every non-cancelled token occupies a reserved place, including completed visits.
CREATE OR REPLACE FUNCTION public.offline_slot_usage(p_slot_ids uuid[])
RETURNS TABLE(slot_id uuid,used_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT t.slot_id,count(*)::bigint
  FROM public.offline_tokens t
  WHERE (SELECT public.offline_current_user_role())='student'
    AND t.slot_id=ANY(COALESCE(p_slot_ids,ARRAY[]::uuid[]))
    AND t.status<>'cancelled'
  GROUP BY t.slot_id;
$function$;
