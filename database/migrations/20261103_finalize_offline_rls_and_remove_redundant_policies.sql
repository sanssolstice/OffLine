-- Final RLS cleanup for the passcode-only OffLine architecture.
-- The admin portal operates through the service-role Edge Function.

drop policy if exists legacy_retired_deny_all on public.counters;
create policy legacy_retired_deny_all on public.counters
  for all to anon, authenticated using (false) with check (false);
drop policy if exists legacy_retired_deny_all on public.profiles;
create policy legacy_retired_deny_all on public.profiles
  for all to anon, authenticated using (false) with check (false);
drop policy if exists legacy_retired_deny_all on public.tokens;
create policy legacy_retired_deny_all on public.tokens
  for all to anon, authenticated using (false) with check (false);

drop policy if exists server_private_deny_client_access on public.offline_admin_credentials;
create policy server_private_deny_client_access on public.offline_admin_credentials
  for all to anon, authenticated using (false) with check (false);
drop policy if exists server_private_deny_client_access on public.offline_admin_login_attempts;
create policy server_private_deny_client_access on public.offline_admin_login_attempts
  for all to anon, authenticated using (false) with check (false);
drop policy if exists server_private_deny_client_access on public.offline_admin_sessions;
create policy server_private_deny_client_access on public.offline_admin_sessions
  for all to anon, authenticated using (false) with check (false);
drop policy if exists server_private_deny_client_access on public.offline_provisioning_tickets;
create policy server_private_deny_client_access on public.offline_provisioning_tickets
  for all to anon, authenticated using (false) with check (false);

drop policy if exists breaks_admin_read_update on public.offline_break_requests;
drop policy if exists slots_admin_all on public.offline_slots;
drop policy if exists windows_admin_all on public.offline_windows;
drop policy if exists works_admin_all on public.offline_works;
drop policy if exists works_read_active on public.offline_works;
create policy works_read_active on public.offline_works
  for select to anon, authenticated using (active);

drop index if exists public.idx_offline_profiles_email;
