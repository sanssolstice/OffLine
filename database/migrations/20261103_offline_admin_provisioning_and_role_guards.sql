-- Fix admin-provisioned Auth account creation and tighten role-bound RPCs.
-- The auth.users trigger consumes a one-time service-role-only provisioning ticket.
create table if not exists public.offline_provisioning_tickets (
  email text primary key check (email = lower(email)),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
alter table public.offline_provisioning_tickets enable row level security;
revoke all on public.offline_provisioning_tickets from public, anon, authenticated;
grant all on public.offline_provisioning_tickets to service_role;
create index if not exists idx_offline_provisioning_tickets_expiry
  on public.offline_provisioning_tickets(expires_at);

create or replace function public.offline_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ticket_email text;
begin
  delete from public.offline_provisioning_tickets
  where email = lower(coalesce(new.email, ''))
    and expires_at > now()
  returning email into v_ticket_email;

  if v_ticket_email is null then
    delete from public.offline_provisioning_tickets
    where email = lower(coalesce(new.email, ''));
    raise exception 'Account creation is restricted. Ask your campus administrator to create your account.';
  end if;

  insert into public.offline_profiles(id, email, full_name, college_id, role)
  values (
    new.id,
    lower(new.email),
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(new.email, '@', 1), 'Student'),
    nullif(new.raw_user_meta_data->>'college_id', ''),
    'student'
  )
  on conflict(id) do update set
    email = excluded.email,
    full_name = excluded.full_name,
    college_id = excluded.college_id;

  return new;
end;
$$;
revoke all on function public.offline_handle_new_user() from public, anon, authenticated;

create or replace function public.offline_cancel_own_token(p_token_id uuid)
returns public.offline_tokens
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_token public.offline_tokens%rowtype;
begin
  if v_user is null or (select public.offline_current_user_role()) <> 'student' then
    raise exception 'An active student account is required';
  end if;

  update public.offline_tokens
  set status = 'cancelled',
      cancellation_type = 'student'
  where id = p_token_id
    and student_id = v_user
    and status in ('booked', 'arrived')
  returning * into v_token;

  if not found then
    raise exception 'Token cannot be cancelled';
  end if;

  insert into public.offline_service_events(token_id, actor_id, event_type)
  values (p_token_id, v_user, 'cancelled');

  return v_token;
end;
$$;
revoke all on function public.offline_cancel_own_token(uuid) from public, anon;
grant execute on function public.offline_cancel_own_token(uuid) to authenticated;

create or replace function public.offline_slot_usage(p_slot_ids uuid[])
returns table(slot_id uuid, used_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select t.slot_id, count(*)::bigint
  from public.offline_tokens t
  where (select public.offline_current_user_role()) = 'student'
    and t.slot_id = any(p_slot_ids)
    and t.status in ('booked', 'arrived', 'serving')
  group by t.slot_id;
$$;
revoke all on function public.offline_slot_usage(uuid[]) from public, anon;
grant execute on function public.offline_slot_usage(uuid[]) to authenticated;

drop policy if exists breaks_staff_insert on public.offline_break_requests;
create policy breaks_staff_insert
on public.offline_break_requests
for insert to authenticated
with check (
  requested_by = (select auth.uid())
  and (select public.offline_current_user_role()) = 'staff'
  and exists (
    select 1 from public.offline_windows w
    where w.id = offline_break_requests.window_id
      and w.staff_id = (select auth.uid())
  )
);
