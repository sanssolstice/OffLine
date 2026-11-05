# OffLine — Campus Queue & Service Management

OffLine is a role-based campus service operations platform with three separate portals. There is no demo-mode role switcher and no public registration.

## Portals

- **Administrator:** passcode-only login at `/admin/login`. The administrator provisions students and staff, resets passwords, activates or deactivates accounts, permanently deletes deactivated accounts after confirmation, assigns staff to counters, manages services and windows, reviews emergency breaks, and monitors bookings, receives operations alerts, and generates custom date-range reports.
- **Student:** email/password login at `/student/login`. Students browse services, choose a window and one of the next two calendar days, book a token, see the live estimated turn, receive booking/queue notifications, and cancel eligible bookings.
- **Staff:** email/password login at `/staff/login`. Staff see assigned service windows, appointment times and live estimated turns, receive booking/cancellation notifications, view the live queue, mark arrivals, call and complete students, update window availability, and request emergency breaks.

Students and staff cannot register themselves. Accounts are created only by the administrator. The database auth trigger permits only short-lived, one-time provisioning tickets created by the server-side admin function; public signup remains disabled.

## Sample accounts

On the first successful admin login, OffLine provisions the following sample accounts, assigns staff to two counters and inserts sample queue records. The credentials are displayed in the admin's one-time account credentials dialog as well.

| Role | Name | College / Staff ID | Email | Initial password |
|---|---|---|---|---|
| Student | Aanya Sharma | OFF-STU-001 | `aanya.sharma@offline.edu` | `Aanya@OffLine26!` |
| Student | Rohan Verma | OFF-STU-002 | `rohan.verma@offline.edu` | `Rohan@OffLine26!` |
| Staff | Meera Kapoor | OFF-STF-001 | `meera.kapoor@offline.edu` | `Meera@OffLine26!` |
| Staff | Arjun Malhotra | OFF-STF-002 | `arjun.malhotra@offline.edu` | `Arjun@OffLine26!` |

These are prototype credentials. Change them from the administrator's People & Accounts page before using this deployment with real college users.

## Routes

- `/` — public landing page
- `/admin/login` — administrator passcode login
- `/admin/dashboard` — administration control centre
- `/student/login`, `/student/dashboard`, `/student/book`, `/student/tokens`
- `/staff/login`, `/staff/dashboard`, `/staff/queue`, `/staff/windows`

## Run locally

Requirements: Node.js 20.19+ or 22.12+.

    npm install
    cp .env.example .env.local
    npm run dev

Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in `.env.local`. Only a publishable/anon key belongs in frontend configuration. Never put the service-role or secret key in a `VITE_` variable.

## Supabase setup

1. Apply `database/schema.sql` to create the OffLine schema, RLS policies, private admin session tables, booking RPCs and starter campus services/windows/slots.
2. Deploy `supabase/functions/offline-admin/index.ts` as the Edge Function named `offline-admin` with JWT verification disabled. The function verifies its own opaque, expiring admin session token and rate-limits invalid passcode attempts. It uses the server-side Supabase secret for Auth Admin and private admin tables; that secret is never exposed to the browser.
3. Configure the one active row in `public.offline_admin_credentials` with id `primary`. Store only a SHA-256 hex digest in `passcode_hash`.
4. Do not enable an app-level signup route. Account creation is through the admin Edge Function.
5. Apply the migrations in `database/migrations/` in date order. The provisioning migration configures the private one-time ticket flow; the legacy retirement migration disables the old prototype API; the final RLS migration adds explicit client-deny policies and removes unused Auth-admin policies.
6. The live ETA RPC and notification triggers are installed by the November 5, 2026 migrations. Student/staff notification records update live in the portal; desktop browser alerts can be enabled while the portal is open.
7. Admin reports query appointments by their scheduled slot date. Account deletion requires prior deactivation and no active bookings; token history is retained with the student identity detached.
8. Vercel is configured for Vite and uses the SPA rewrite in `vercel.json`, so direct portal URLs work.

## Scheduling rules

Only today and tomorrow are offered for booking. Students may hold one non-cancelled token per service/work per calendar day; a cancelled token releases that service/day so another slot can be chosen. A completed token still counts for that day. Slot capacity and the duplicate-work/day check are validated atomically in Postgres with a transaction-scoped advisory lock. Slots are one hour long, 12:00–13:00 is reserved for lunch, and the final 15 minutes of each hour are a buffer.

## Security

- No public student or staff registration. The Auth trigger accepts only short-lived, one-time provisioning tickets created by the server-side admin function.
- The administrator passcode is stored as a SHA-256 digest and exchanged for a server-verified, expiring session. Invalid attempts are rate-limited.
- Student/staff passwords are created or reset through the admin Edge Function.
- Admin passcode/session and provisioning-ticket tables have explicit deny policies for anon/authenticated roles and are accessed only by the server-side service role.
- Retired `profiles`, `tokens`, and `counters` tables are preserved for recovery, but have no API-role grants or permissive policies. The legacy RPCs are disabled, non-mutating tombstones and cannot be executed by API roles.
- The exposed OffLine RPCs are limited to authenticated users, use a pinned empty search path, and enforce student/staff ownership and role checks before privileged operations. Notification rows are scoped to the recipient; administrator notifications are accessible only through the authenticated server-side admin function. Live ETA is calculated by a role-checked RPC.
