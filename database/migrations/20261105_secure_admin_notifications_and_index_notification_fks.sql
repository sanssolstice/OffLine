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
