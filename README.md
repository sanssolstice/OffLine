# OffLine — Smart Token & Queue Management

OffLine helps college students reserve service slots and track their turn instead of waiting physically at an office counter.

## Prototype features

- **Student:** choose a service, window, date and slot; see availability; book a token; track status, queue position and estimated turn; cancel a booking.
- **Staff:** view the live queue; mark physical arrival; call and complete students; cancel a late/no-show token; open or close a window.
- **Admin:** manage the service catalogue and windows; review emergency-break requests; view operational metrics.
- **Demo mode:** runs immediately without login or backend; data persists in the current browser.
- **Supabase mode:** email/password authentication, RLS-protected data, atomic booking and staff service actions when configured.

## Run locally

Requirements: Node.js 20.19+ or 22.12+.

    npm install
    cp .env.example .env.local
    npm run dev

Open http://localhost:5173. Without Supabase values, the app starts in Interactive Demo Mode.

## Connect Supabase

1. Restore/activate the Supabase project.
2. Open SQL Editor, paste the contents of database/schema.sql, and run it once.
3. Copy the Project URL and publishable key (or legacy anon key) from Project Settings → API.
4. Add the values to .env.local:

    VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
    VITE_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY

5. Restart Vite. Create Student accounts using Sign up.
6. Create staff/admin accounts using Sign up, then promote their profiles via SQL Editor. New accounts always default to Student; a client cannot grant itself a privileged role.

Example role assignment:

    update public.profiles set role='admin' where college_id='ADMIN_COLLEGE_ID';
    update public.profiles set role='staff' where college_id='STAFF_COLLEGE_ID';
    update public.windows
    set staff_id=(select id from public.profiles where college_id='STAFF_COLLEGE_ID')
    where name='Window 01 · Student Services';

The schema seeds four example campus services, four windows and weekday slots for the coming days. Slots are one hour, the final 15 minutes are reserved as buffer, and 12:00–13:00 is blocked for lunch. Capacity is derived from the service-duration estimate.

## Recommended presentation walkthrough

1. Launch and remain in Demo Mode.
2. As Student, book a Bonafide Certificate or Document Verification slot.
3. Switch to Staff → Live Queue. Mark the token Arrived, then Call student and Complete.
4. Switch back to Student → My Tokens to show the updated status.
5. Switch to Admin → Services & Windows / Analytics to show configuration and operations.

Demo data is stored in the current browser only. It is not shared across browsers or devices. Live mode uses Supabase Auth and Postgres.

## Stack

React 19 · Vite 7 · Supabase Postgres/Auth · lucide-react

## Security

Only a publishable/anon key belongs in client-side configuration. Never add a service-role or secret key to a VITE_ variable or commit .env.local.
