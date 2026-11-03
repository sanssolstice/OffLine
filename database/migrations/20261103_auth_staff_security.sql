-- OffLine authentication and staff queue security migration.
-- These changes have been applied to the connected Supabase project.

alter table public.offline_profiles add column if not exists email text;
create unique index if not exists idx_offline_profiles_email_lower
  on public.offline_profiles(lower(email)) where email is not null;

drop policy if exists profiles_select_self_or_admin on public.offline_profiles;
drop policy if exists profiles_staff_read_assigned_students on public.offline_profiles;
create policy offline_profiles_select_self_admin_or_assigned_staff
on public.offline_profiles for select to authenticated
using(
 id=(select auth.uid())
 or (select public.offline_current_user_role())='admin'
 or (
   role='student' and (select public.offline_current_user_role())='staff'
   and exists(select 1 from public.offline_tokens t join public.offline_windows w on w.id=t.window_id
     where t.student_id=offline_profiles.id and w.staff_id=(select auth.uid())
     and t.status in('booked','arrived','serving','completed'))
 )
);

create or replace function public.offline_handle_new_user()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if coalesce(new.raw_app_meta_data->>'offline_provisioned','false') <> 'true' then
   raise exception 'Public registration is disabled. Ask your campus administrator to create your account.';
 end if;
 insert into public.offline_profiles(id,email,full_name,college_id,role)
 values(new.id,lower(new.email),coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1),'Student'),
   nullif(new.raw_user_meta_data->>'college_id',''),'student')
 on conflict(id) do update set email=excluded.email,full_name=excluded.full_name,college_id=excluded.college_id;
 return new;
end;
$$;

create index if not exists idx_offline_tokens_student_slot_status
  on public.offline_tokens(student_id,slot_id,status);

create or replace function public.offline_slot_usage(p_slot_ids uuid[])
returns table(slot_id uuid,used_count bigint)
language sql stable security definer set search_path=''
as $$
 select t.slot_id,count(*)::bigint from public.offline_tokens t
 where auth.uid() is not null and t.slot_id=any(p_slot_ids)
 and t.status in('booked','arrived','serving') group by t.slot_id;
$$;
revoke all on function public.offline_slot_usage(uuid[]) from public,anon;
grant execute on function public.offline_slot_usage(uuid[]) to authenticated;

create or replace function public.offline_book_token(p_slot_id uuid)
returns public.offline_tokens language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid:=auth.uid(); v_slot public.offline_slots%rowtype; v_win public.offline_windows%rowtype;
 v_profile public.offline_profiles%rowtype; v_num integer; v_pos integer; v_used integer; v_token public.offline_tokens%rowtype;
begin
 if v_user is null then raise exception 'Please sign in first'; end if;
 select * into v_profile from public.offline_profiles where id=v_user and account_status='active';
 if not found or v_profile.role<>'student' then raise exception 'An active student account is required'; end if;
 select * into v_slot from public.offline_slots where id=p_slot_id for update;
 if not found then raise exception 'Slot not found'; end if;
 select * into v_win from public.offline_windows where id=v_slot.window_id for update;
 if not found or v_win.status<>'open' then raise exception 'This service window is not open'; end if;
 if v_slot.starts_at<=now() then raise exception 'This slot has already started'; end if;
 if exists(select 1 from public.offline_tokens where student_id=v_user and slot_id=p_slot_id and status in('booked','arrived','serving')) then
   raise exception 'You already have an active booking for this slot';
 end if;
 select count(*) into v_used from public.offline_tokens where slot_id=p_slot_id and status in('booked','arrived','serving');
 if v_used>=v_slot.capacity then raise exception 'This slot is full. Please choose another one'; end if;
 select coalesce(max(token_number),0)+1 into v_num from public.offline_tokens where window_id=v_slot.window_id;
 select count(*)+1 into v_pos from public.offline_tokens where slot_id=p_slot_id and status in('booked','arrived','serving');
 insert into public.offline_tokens(student_id,slot_id,window_id,token_number,queue_position)
 values(v_user,p_slot_id,v_slot.window_id,v_num,v_pos) returning * into v_token;
 return v_token;
end;
$$;
revoke all on function public.offline_book_token(uuid) from public,anon;
grant execute on function public.offline_book_token(uuid) to authenticated;

-- Publication additions for the client Realtime subscriptions are idempotent.
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
