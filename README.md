# OffLine — Campus Queue & Service Management

OffLine is a role-based campus service operations platform with three separate portals. There is no demo-mode role switcher and no public registration.

## Portals

- **Administrator:** passcode-only login at `/admin/login`. The administrator provisions students and staff, resets passwords, activates or deactivates accounts, assigns staff to counters, manages services and windows, reviews emergency breaks, and monitors bookings and analytics.
- **Student:** email/password login at `/student/login`. Students browse services, choose a window and appointment slot, book a token, track status and queue position, and cancel eligible bookings.
- **Staff:** email/password login at `/staff/login`. Staff see their assigned service windows, view the live queue, mark arrival, call and complete students, update window availability, and request emergency breaks.

Students and staff cannot register themselves. Accounts are created only by the administrator. The database auth trigger rejects signups without the server-controlled provisioning claim.

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
5. Vercel is configured for Vite and uses the SPA rewrite in `vercel.json`, so direct portal URLs work.

## Scheduling rules

Slots are one hour long, 12:00–13:00 is reserved for lunch, and the final 15 minutes of each hour are a buffer. Slot capacity is derived from average service duration. Booking is validated and committed atomically in Postgres, with unique per-window token numbers.

## Security

- No public student or staff registration.
- The admin passcode is stored as a hash and exchanged for a server-verified, expiring session; invalid attempts are rate-limited.
- Student/staff passwords are created or reset through the admin server function.
- Exposed OffLine tables use RLS. Admin passcode/session tables have no anon/authenticated policies.
- Legacy `profiles`, `tokens`, and `counters` tables are kept separate and are not used by OffLine.
