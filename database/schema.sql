-- OffLine: Smart Token and Queue Management
-- Apply once in the Supabase SQL Editor after the project is ACTIVE.
-- Never put a service_role/secret key in the browser app.

create extension if not exists pgcrypto;
create table if not exists public.offline_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default 'Student', college_id text unique,
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

-- Definer helper avoids recursive RLS when checking a caller's role.
create or replace function public.offline_current_user_role()
returns text language sql stable security definer set search_path=''
as $$ select p.role from public.offline_profiles p where p.id=(select auth.uid()) and p.account_status='active' $$;
revoke all on function public.offline_current_user_role() from public,anon;
grant execute on function public.offline_current_user_role() to authenticated;

-- Ignore role fields from signup metadata: every new account is a Student.
create or replace function public.offline_handle_new_user()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 insert into public.offline_profiles(id,full_name,college_id,role)
 values(new.id,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1),'Student'),
 nullif(new.raw_user_meta_data->>'college_id',''),'student')
 on conflict(id) do nothing;
 return new;
end;
$$;
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

create policy "profiles_select_self_or_admin" on public.offline_profiles for select to authenticated
using(id=(select auth.uid()) or (select public.offline_current_user_role())='admin');
create policy "profiles_update_self_or_admin" on public.offline_profiles for update to authenticated
using(id=(select auth.uid()) or (select public.offline_current_user_role())='admin')
with check((id=(select auth.uid()) and role='student') or (select public.offline_current_user_role())='admin');
create policy "works_read_active" on public.offline_works for select to anon,authenticated
using(active or (select public.offline_current_user_role())='admin');
create policy "works_admin_all" on public.offline_works for all to authenticated
using((select public.offline_current_user_role())='admin') with check((select public.offline_current_user_role())='admin');
create policy "windows_read" on public.offline_windows for select to anon,authenticated using(true);
create policy "windows_admin_all" on public.offline_windows for all to authenticated
using((select public.offline_current_user_role())='admin') with check((select public.offline_current_user_role())='admin');
create policy "windows_staff_update_assigned" on public.offline_windows for update to authenticated
using(staff_id=(select auth.uid())) with check(staff_id=(select auth.uid()));
create policy "slots_read" on public.offline_slots for select to anon,authenticated using(true);
create policy "slots_admin_all" on public.offline_slots for all to authenticated
using((select public.offline_current_user_role())='admin') with check((select public.offline_current_user_role())='admin');
create policy "tokens_read_owner_staff_admin" on public.offline_tokens for select to authenticated
using(student_id=(select auth.uid()) or (select public.offline_current_user_role())='admin'
or exists(select 1 from public.offline_windows w where w.id=tokens.window_id and w.staff_id=(select auth.uid())));
create policy "events_read_authorized" on public.offline_service_events for select to authenticated
using(exists(select 1 from public.offline_tokens t where t.id=service_events.token_id and (
t.student_id=(select auth.uid()) or (select public.offline_current_user_role())='admin'
or exists(select 1 from public.offline_windows w where w.id=t.window_id and w.staff_id=(select auth.uid())))));
create policy "breaks_staff_insert" on public.offline_break_requests for insert to authenticated
with check(requested_by=(select auth.uid()) and exists(select 1 from public.offline_windows w where w.id=window_id and w.staff_id=(select auth.uid())));
create policy "breaks_admin_read_update" on public.offline_break_requests for all to authenticated
using((select public.offline_current_user_role())='admin') with check((select public.offline_current_user_role())='admin');

grant select on public.offline_works,public.offline_windows,public.offline_slots to anon,authenticated;
grant select,update on public.offline_profiles to authenticated;
grant select on public.offline_tokens,public.offline_service_events to authenticated;
grant select,insert,update on public.offline_break_requests to authenticated;
grant insert,update,delete on public.offline_works,public.offline_windows,public.offline_slots to authenticated;

-- Atomic slot lock and capacity check prevent overbooking on simultaneous requests.
create or replace function public.offline_book_token(p_slot_id uuid)
returns public.offline_tokens language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_slot public.offline_slots%rowtype; v_win public.offline_windows%rowtype;
v_profile public.offline_profiles%rowtype; v_num integer; v_pos integer; v_used integer; v_token public.offline_tokens%rowtype;
begin
 if v_user is null then raise exception 'Please sign in first'; end if;
 select * into v_profile from public.offline_profiles where id=v_user and account_status='active';
 if not found or v_profile.role<>'student' then raise exception 'An active student account is required'; end if;
 select * into v_slot from public.offline_slots where id=p_slot_id for update;
 if not found then raise exception 'Slot not found'; end if;
 select * into v_win from public.offline_windows where id=v_slot.window_id;
 if v_win.status<>'open' then raise exception 'This service window is not open'; end if;
 if v_slot.starts_at<=now() then raise exception 'This slot has already started'; end if;
 select count(*) into v_used from public.offline_tokens where slot_id=p_slot_id and status in('booked','arrived','serving');
 if v_used>=v_slot.capacity then raise exception 'This slot is full. Please choose another one'; end if;
 select coalesce(max(t.token_number),0)+1 into v_num from public.offline_tokens t join public.offline_slots s on s.id=t.slot_id
 where t.window_id=v_slot.window_id and s.slot_date=v_slot.slot_date;
 select count(*)+1 into v_pos from public.offline_tokens where slot_id=p_slot_id and status in('booked','arrived','serving');
 insert into public.offline_tokens(student_id,slot_id,window_id,token_number,queue_position)
 values(v_user,p_slot_id,v_slot.window_id,v_num,v_pos) returning * into v_token;
 return v_token;
end;
$$;

create or replace function public.offline_staff_update_token(p_token_id uuid,p_action text,p_reason text default null)
returns public.offline_tokens language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_token public.offline_tokens%rowtype; v_allowed boolean; v_next text; v_event text;
begin
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
as $$
declare v_token public.offline_tokens%rowtype;
begin
 update public.offline_tokens set status='cancelled',cancellation_type='student'
 where id=p_token_id and student_id=auth.uid() and status in('booked','arrived') returning * into v_token;
 if not found then raise exception 'Token cannot be cancelled'; end if;
 insert into public.offline_service_events(token_id,actor_id,event_type) values(p_token_id,auth.uid(),'cancelled');
 return v_token;
end;
$$;
revoke all on function public.offline_book_token(uuid) from public,anon;
revoke all on function public.offline_staff_update_token(uuid,text,text) from public,anon;
revoke all on function public.offline_cancel_own_token(uuid) from public,anon;
grant execute on function public.offline_book_token(uuid),public.offline_staff_update_token(uuid,text,text),public.offline_cancel_own_token(uuid) to authenticated;

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
cross join generate_series(current_date,current_date+14,interval '1 day') d
cross join (values(time '09:00'),(time '10:00'),(time '11:00'),(time '13:00'),(time '14:00'),(time '15:00'),(time '16:00')) t(start_time)
where extract(isodow from d) between 1 and 5
on conflict(window_id,starts_at) do nothing;

-- Create staff/admin accounts through Auth, then promote from SQL Editor:
-- update public.offline_profiles set role='admin' where college_id='YOUR_ADMIN_COLLEGE_ID';
-- update public.offline_profiles set role='staff' where college_id='YOUR_STAFF_COLLEGE_ID';
-- update public.offline_windows set staff_id=(select id from public.offline_profiles where college_id='YOUR_STAFF_COLLEGE_ID')
-- where name='Window 01 · Student Services';