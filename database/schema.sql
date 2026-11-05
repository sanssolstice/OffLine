-- OffLine: Smart Token and Queue Management
-- Apply once in the Supabase SQL Editor after the project is ACTIVE.
-- Never put a service_role/secret key in the browser app.

create extension if not exists pgcrypto;
create table if not exists public.offline_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default 'Student', college_id text unique, email text unique,
 role text not null default 'student' check(role in('student','staff','admin')),
 account_status text not null default 'active' check(account_status in('active','inactive')),
 created_at timestamptz not null default now()
);
create table if not exists public.offline_works (
 id uuid primary key default gen_random_uuid(), name text not null unique,
 description text not null default '',
 avg_service_minutes integer not null default 10 check(avg_service_minutes between 1 and 45),
 active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.offline_windows (
 id uuid primary key default gen_random_uuid(), work_id uuid not null references public.offline_works(id) on delete restrict,
 name text not null unique, location text not null default 'Main Office',
 staff_id uuid references public.offline_profiles(id) on delete set null,
 status text not null default 'open' check(status in('open','closed','break')),
 created_at timestamptz not null default now()
);
create table if not exists public.offline_slots (
 id uuid primary key default gen_random_uuid(), window_id uuid not null references public.offline_windows(id) on delete cascade,
 slot_date date not null, starts_at timestamptz not null, ends_at timestamptz not null,
 capacity integer not null check(capacity>0), buffer_minutes integer not null default 15 check(buffer_minutes=15),
 created_at timestamptz not null default now(), unique(window_id,starts_at),
 check(ends_at-starts_at=interval '1 hour')
);
create table if not exists public.offline_tokens (
 id uuid primary key default gen_random_uuid(), student_id uuid not null references public.offline_profiles(id) on delete restrict,
 slot_id uuid not null references public.offline_slots(id) on delete restrict,
 window_id uuid not null references public.offline_windows(id) on delete restrict,
 token_number integer not null, queue_position integer not null,
 status text not null default 'booked' check(status in('booked','arrived','serving','completed','cancelled')),
 booked_at timestamptz not null default now(), arrived_at timestamptz,
 service_started_at timestamptz, completed_at timestamptz,
 cancellation_type text check(cancellation_type in('student','staff','late_no_show','emergency')),
 cancellation_reason text, unique(window_id,token_number)
);
create index if not exists idx_offline_slots_date_window on public.offline_slots(slot_date,window_id,starts_at);
create index if not exists idx_offline_tokens_student_status on public.offline_tokens(student_id,status,booked_at desc);
create index if not exists idx_offline_tokens_window_status on public.offline_tokens(window_id,status,token_number);
create index if not exists idx_offline_tokens_slot_id on public.offline_tokens(slot_id);
create index if not exists idx_offline_windows_work_id on public.offline_windows(work_id);
create index if not exists idx_offline_windows_staff_id on public.offline_windows(staff_id);
create table if not exists public.offline_service_events (
 id uuid primary key default gen_random_uuid(), token_id uuid not null references public.offline_tokens(id) on delete cascade,
 actor_id uuid references public.offline_profiles(id) on delete set null,
 event_type text not null check(event_type in('arrived','service_started','completed','cancelled','window_opened','window_closed')),
 details jsonb not null default '{}'::jsonb, occurred_at timestamptz not null default now()
);
create table if not exists public.offline_break_requests (
 id uuid primary key default gen_random_uuid(), window_id uuid not null references public.offline_windows(id) on delete cascade,
 requested_by uuid not null references public.offline_profiles(id) on delete restrict, reason text not null,
 status text not null default 'pending' check(status in('pending','approved','rejected')),
 requested_at timestamptz not null default now(), reviewed_by uuid references public.offline_profiles(id) on delete set null,
 reviewed_at timestamptz
);

-- Private administrator authentication records. These tables are only accessible via the Edge Function.
create table if not exists public.offline_admin_credentials (
 id text primary key check(id='primary'),
 passcode_hash text not null,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.offline_admin_login_attempts (
 ip_hash text primary key,
 attempts integer not null default 0,
 window_started_at timestamptz not null default now(),
 locked_until timestamptz
);
create table if not exists public.offline_admin_sessions (
 id uuid primary key default gen_random_uuid(),
 token_hash text not null unique,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null,
 revoked_at timestamptz
);
create table if not exists public.offline_provisioning_tickets (
 email text primary key check(email=lower(email)),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null
);
alter table public.offline_provisioning_tickets enable row level security;
alter table public.offline_admin_credentials enable row level security;
alter table public.offline_admin_login_attempts enable row level security;
alter table public.offline_admin_sessions enable row level security;
alter table public.offline_provisioning_tickets enable row level security;
revoke all on public.offline_admin_credentials,public.offline_admin_login_attempts,public.offline_admin_sessions,public.offline_provisioning_tickets from public,anon,authenticated;
grant all on public.offline_admin_credentials,public.offline_admin_login_attempts,public.offline_admin_sessions,public.offline_provisioning_tickets to service_role;
create policy server_private_deny_client_access on public.offline_admin_credentials for all to anon,authenticated using(false) with check(false);
create policy server_private_deny_client_access on public.offline_admin_login_attempts for all to anon,authenticated using(false) with check(false);
create policy server_private_deny_client_access on public.offline_admin_sessions for all to anon,authenticated using(false) with check(false);
create policy server_private_deny_client_access on public.offline_provisioning_tickets for all to anon,authenticated using(false) with check(false);
create index if not exists idx_offline_provisioning_tickets_expiry on public.offline_provisioning_tickets(expires_at);
create index if not exists idx_offline_admin_sessions_expiry
 on public.offline_admin_sessions(expires_at) where revoked_at is null;
create index if not exists idx_offline_tokens_student_slot_status on public.offline_tokens(student_id,slot_id,status);
create unique index if not exists idx_offline_profiles_email_lower on public.offline_profiles(lower(email)) where email is not null;
create index if not exists idx_offline_events_token_id on public.offline_service_events(token_id);
create index if not exists idx_offline_events_actor_id on public.offline_service_events(actor_id);
create index if not exists idx_offline_breaks_window_id on public.offline_break_requests(window_id);
create index if not exists idx_offline_breaks_requested_by on public.offline_break_requests(requested_by);
create index if not exists idx_offline_breaks_reviewed_by on public.offline_break_requests(reviewed_by);

-- Definer helper avoids recursive RLS when checking a caller's role.
create or replace function public.offline_current_user_role()
returns text language sql stable security definer set search_path=''
as $$ select p.role from public.offline_profiles p where p.id=(select auth.uid()) and p.account_status='active' $$;
revoke all on function public.offline_current_user_role() from public,anon;
grant execute on function public.offline_current_user_role() to authenticated;

-- Ignore role fields from signup metadata: every new account is a Student.
create or replace function public.offline_handle_new_user()
returns trigger language plpgsql security definer set search_path=''
as $
declare v_ticket_email text;
begin
 delete from public.offline_provisioning_tickets
 where email=lower(coalesce(new.email,''))
   and expires_at>now()
 returning email into v_ticket_email;
 if v_ticket_email is null then
   delete from public.offline_provisioning_tickets where email=lower(coalesce(new.email,''));
   raise exception 'Account creation is restricted. Ask your campus administrator to create your account.';
 end if;
 insert into public.offline_profiles(id,email,full_name,college_id,role)
 values(new.id,lower(new.email),
   coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1),'Student'),
   nullif(new.raw_user_meta_data->>'college_id',''),'student')
 on conflict(id) do update set email=excluded.email,full_name=excluded.full_name,college_id=excluded.college_id;
 return new;
end;
$;
revoke all on function public.offline_handle_new_user() from public,anon,authenticated;
drop trigger if exists on_auth_user_created_offline_v2 on auth.users;
create trigger on_auth_user_created_offline_v2 after insert on auth.users
for each row execute procedure public.offline_handle_new_user();

alter table public.offline_profiles enable row level security;
alter table public.offline_works enable row level security;
alter table public.offline_windows enable row level security;
alter table public.offline_slots enable row level security;
alter table public.offline_tokens enable row level security;
alter table public.offline_service_events enable row level security;
alter table public.offline_break_requests enable row level security;

create policy "offline_profiles_select_self_admin_or_assigned_staff" on public.offline_profiles for select to authenticated
using(
 id=(select auth.uid())
 or (select public.offline_current_user_role())='admin'
 or (
   role='student'
   and (select public.offline_current_user_role())='staff'
   and exists(
     select 1 from public.offline_tokens t
     join public.offline_windows w on w.id=t.window_id
     where t.student_id=offline_profiles.id and w.staff_id=(select auth.uid())
       and t.status in('booked','arrived','serving','completed')
   )
 )
);
create policy "profiles_update_self_or_admin" on public.offline_profiles for update to authenticated
using(id=(select auth.uid()) or (select public.offline_current_user_role())='admin')
with check((id=(select auth.uid()) and role='student') or (select public.offline_current_user_role())='admin');
create policy "works_read_active" on public.offline_works for select to anon,authenticated
using(active);
create policy "windows_read" on public.offline_windows for select to anon,authenticated using(true);
create policy "windows_staff_update_assigned" on public.offline_windows for update to authenticated
using(staff_id=(select auth.uid())) with check(staff_id=(select auth.uid()));
create policy "slots_read" on public.offline_slots for select to anon,authenticated using(true);
create policy "tokens_read_owner_staff_active" on public.offline_tokens for select to authenticated
using(
 (select public.offline_current_user_role()) in('student','staff')
 and (
   student_id=(select auth.uid())
   or exists(select 1 from public.offline_windows w where w.id=offline_tokens.window_id and w.staff_id=(select auth.uid()))
 )
);
create policy "events_read_authorized" on public.offline_service_events for select to authenticated
using(exists(select 1 from public.offline_tokens t where t.id=offline_service_events.token_id and (
t.student_id=(select auth.uid()) or (select public.offline_current_user_role())='admin'
or exists(select 1 from public.offline_windows w where w.id=t.window_id and w.staff_id=(select auth.uid())))));
create policy "breaks_staff_insert" on public.offline_break_requests for insert to authenticated
with check(requested_by=(select auth.uid()) and (select public.offline_current_user_role())='staff' and exists(select 1 from public.offline_windows w where w.id=window_id and w.staff_id=(select auth.uid())));
create policy "breaks_staff_read_own" on public.offline_break_requests for select to authenticated
using(requested_by=(select auth.uid()) and (select public.offline_current_user_role())='staff');

grant select on public.offline_works,public.offline_windows,public.offline_slots to anon,authenticated;
grant select,update on public.offline_profiles to authenticated;
grant select on public.offline_tokens,public.offline_service_events to authenticated;
grant select,insert,update on public.offline_break_requests to authenticated;
grant insert,update,delete on public.offline_works,public.offline_windows,public.offline_slots to authenticated;

-- Atomic slot lock and capacity check prevent overbooking on simultaneous requests.
create or replace function public.offline_book_token(p_slot_id uuid)
returns public.offline_tokens language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid:=auth.uid();
 v_slot public.offline_slots%rowtype;
 v_win public.offline_windows%rowtype;
 v_profile public.offline_profiles%rowtype;
 v_num integer;
 v_pos integer;
 v_used integer;
 v_token public.offline_tokens%rowtype;
begin
 if v_user is null then raise exception 'Please sign in first'; end if;
 select * into v_profile from public.offline_profiles where id=v_user and account_status='active';
 if not found or v_profile.role<>'student' then raise exception 'An active student account is required'; end if;
 select * into v_slot from public.offline_slots where id=p_slot_id for update;
 if not found then raise exception 'Slot not found'; end if;
 select * into v_win from public.offline_windows where id=v_slot.window_id for update;
 if not found or v_win.status<>'open' then raise exception 'This service window is not open'; end if;
 if v_slot.starts_at<=now() then raise exception 'This slot has already started'; end if;
 if exists(
   select 1 from public.offline_tokens
   where student_id=v_user and slot_id=p_slot_id and status in('booked','arrived','serving')
 ) then raise exception 'You already have an active booking for this slot'; end if;
 select count(*) into v_used from public.offline_tokens where slot_id=p_slot_id and status in('booked','arrived','serving');
 if v_used>=v_slot.capacity then raise exception 'This slot is full. Please choose another one'; end if;
 select coalesce(max(token_number),0)+1 into v_num from public.offline_tokens where window_id=v_slot.window_id;
 select count(*)+1 into v_pos from public.offline_tokens where slot_id=p_slot_id and status in('booked','arrived','serving');
 insert into public.offline_tokens(student_id,slot_id,window_id,token_number,queue_position)
 values(v_user,p_slot_id,v_slot.window_id,v_num,v_pos) returning * into v_token;
 return v_token;
end;
$$;

create or replace function public.offline_slot_usage(p_slot_ids uuid[])
returns table(slot_id uuid,used_count bigint)
language sql stable security definer set search_path=''
as $
 select t.slot_id,count(*)::bigint
 from public.offline_tokens t
 where (select public.offline_current_user_role())='student'
 and t.slot_id=any(p_slot_ids)
 and t.status in('booked','arrived','serving')
 group by t.slot_id;
$;
revoke all on function public.offline_slot_usage(uuid[]) from public,anon;
grant execute on function public.offline_slot_usage(uuid[]) to authenticated;

create or replace function public.offline_staff_update_token(p_token_id uuid,p_action text,p_reason text default null)
returns public.offline_tokens language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_token public.offline_tokens%rowtype; v_allowed boolean; v_next text; v_event text;
begin
 if v_user is null or (select public.offline_current_user_role())<>'staff' then
   raise exception 'An active staff account is required';
 end if;
 select * into v_token from public.offline_tokens where id=p_token_id for update;
 if not found then raise exception 'Token not found'; end if;
 select (select public.offline_current_user_role())='admin' or exists(
 select 1 from public.offline_windows w where w.id=v_token.window_id and w.staff_id=v_user) into v_allowed;
 if not v_allowed then raise exception 'You are not assigned to this service window'; end if;
 if p_action='arrive' and v_token.status='booked' then v_next:='arrived';v_event:='arrived';
 elsif p_action='start' and v_token.status='arrived' then v_next:='serving';v_event:='service_started';
 elsif p_action='complete' and v_token.status='serving' then v_next:='completed';v_event:='completed';
 elsif p_action='cancel' and v_token.status in('booked','arrived') then v_next:='cancelled';v_event:='cancelled';
 else raise exception 'This action is not valid for the current token status'; end if;
 update public.offline_tokens set status=v_next,
 arrived_at=case when p_action='arrive' then now() else arrived_at end,
 service_started_at=case when p_action='start' then now() else service_started_at end,
 completed_at=case when p_action='complete' then now() else completed_at end,
 cancellation_type=case when p_action='cancel' then 'staff' else cancellation_type end,
 cancellation_reason=case when p_action='cancel' then p_reason else cancellation_reason end
 where id=p_token_id returning * into v_token;
 insert into public.offline_service_events(token_id,actor_id,event_type,details)
 values(p_token_id,v_user,v_event,jsonb_build_object('reason',p_reason));
 return v_token;
end;
$$;

create or replace function public.offline_cancel_own_token(p_token_id uuid)
returns public.offline_tokens language plpgsql security definer set search_path=''
as $
declare v_user uuid:=auth.uid(); v_token public.offline_tokens%rowtype;
begin
 if v_user is null or (select public.offline_current_user_role())<>'student' then
   raise exception 'An active student account is required';
 end if;
 update public.offline_tokens set status='cancelled',cancellation_type='student'
 where id=p_token_id and student_id=v_user and status in('booked','arrived') returning * into v_token;
 if not found then raise exception 'Token cannot be cancelled'; end if;
 insert into public.offline_service_events(token_id,actor_id,event_type) values(p_token_id,v_user,'cancelled');
 return v_token;
end;
$;
revoke all on function public.offline_book_token(uuid) from public,anon;
revoke all on function public.offline_staff_update_token(uuid,text,text) from public,anon;
revoke all on function public.offline_cancel_own_token(uuid) from public,anon;
grant execute on function public.offline_book_token(uuid),public.offline_staff_update_token(uuid,text,text),public.offline_cancel_own_token(uuid) to authenticated;

do $$
begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='offline_tokens') then
     alter publication supabase_realtime add table public.offline_tokens;
   end if;
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='offline_windows') then
     alter publication supabase_realtime add table public.offline_windows;
   end if;
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='offline_break_requests') then
     alter publication supabase_realtime add table public.offline_break_requests;
   end if;
 end if;
end $$;

insert into public.offline_works(name,description,avg_service_minutes) values
('Bonafide Certificate','Request and collect a bonafide certificate.',10),
('Document Verification','Verification of college forms and documents.',8),
('ID Card Services','New, replacement and correction requests.',12),
('Fee & Accounts','Fee receipts, dues and account queries.',10)
on conflict(name) do nothing;
insert into public.offline_windows(work_id,name,location)
select w.id,s.window_name,s.location from (values
('Bonafide Certificate','Window 01 · Student Services','Administrative Block'),
('Document Verification','Window 02 · Verification','Administrative Block'),
('ID Card Services','Window 03 · ID Desk','Ground Floor'),
('Fee & Accounts','Window 04 · Accounts','Administrative Block')
) s(work_name,window_name,location) join public.offline_works w on w.name=s.work_name
on conflict(name) do nothing;
-- Weekday slots: 09–12 and 13–17; last 15 minutes of each hour are buffer.
insert into public.offline_slots(window_id,slot_date,starts_at,ends_at,capacity,buffer_minutes)
select win.id,d::date,(d::date+t.start_time) at time zone 'Asia/Kolkata',
((d::date+t.start_time)+interval '1 hour') at time zone 'Asia/Kolkata',
greatest(1,floor(45.0/work.avg_service_minutes)::integer),15
from public.offline_windows win join public.offline_works work on work.id=win.work_id
cross join generate_series(current_date,current_date+1,interval '1 day') d
cross join (values(time '09:00'),(time '10:00'),(time '11:00'),(time '13:00'),(time '14:00'),(time '15:00'),(time '16:00')) t(start_time)
where extract(isodow from d) between 1 and 5
on conflict(window_id,starts_at) do nothing;

-- Administrator access is passcode-only and does not use a public Auth account.
-- Student/staff accounts are created and assigned roles through the offline-admin
-- Edge Function. Do not promote profiles manually or enable public registration.
--
-- Keep offline_admin_credentials server-only. Store only the lowercase SHA-256
-- digest in passcode_hash; never store the plaintext administrator passcode.
--
-- For an existing database that contains the retired prototype tables/functions,
-- apply database/migrations/20261103_retire_legacy_public_queue_system.sql.


-- Live ETA, durable notification inboxes and daily booking uniqueness.
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


-- Follow-up hardening for the notification subsystem.
CREATE POLICY offline_admin_notifications_deny_clients
  ON public.offline_admin_notifications
  FOR ALL TO anon, authenticated
  USING(false) WITH CHECK(false);
GRANT ALL ON TABLE public.offline_admin_notifications TO service_role;
CREATE INDEX IF NOT EXISTS idx_offline_notifications_token
  ON public.offline_notifications(token_id) WHERE token_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_offline_admin_notifications_token
  ON public.offline_admin_notifications(token_id) WHERE token_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_offline_admin_notifications_break
  ON public.offline_admin_notifications(break_request_id) WHERE break_request_id IS NOT NULL;
