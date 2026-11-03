-- Retire the original public queue system without deleting its historical data.
-- The new OffLine portal uses only the offline_* tables and RPCs.

-- Remove the prototype's unrestricted public policies and all API-role privileges.
drop policy if exists "Allow public read/write on counters" on public.counters;
drop policy if exists "Allow public read/write on profiles for prototype" on public.profiles;
drop policy if exists "Allow public read/write on tokens" on public.tokens;

alter table public.counters enable row level security;
alter table public.profiles enable row level security;
alter table public.tokens enable row level security;

revoke all privileges on table public.counters, public.profiles, public.tokens
  from public, anon, authenticated, service_role;

-- Replace retired queue RPCs with explicit, non-mutating tombstones.
-- Keep their signatures so stale clients get a clear error instead of mutating data.
create or replace function public.issue_next_token(
  p_counter_id uuid,
  p_student_name text,
  p_roll_number text,
  p_purpose text
)
returns public.tokens
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  raise exception 'The legacy queue system is retired. Please use the OffLine portal.';
end;
$function$;

create or replace function public.advance_counter_queue(
  p_counter_id uuid,
  p_prev_disposition public.token_status default 'SERVED'::public.token_status
)
returns public.tokens
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  raise exception 'The legacy queue system is retired. Please use the OffLine portal.';
end;
$function$;

create or replace function public.reset_all_queues()
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  raise exception 'The legacy queue system is retired. Please use the OffLine portal.';
end;
$function$;

revoke all privileges on function public.issue_next_token(uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all privileges on function public.advance_counter_queue(uuid, public.token_status)
  from public, anon, authenticated, service_role;
revoke all privileges on function public.reset_all_queues()
  from public, anon, authenticated, service_role;
