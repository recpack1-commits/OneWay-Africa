# OneWay Africa & BiblePlus Ministry Platform

The application is built with Next.js App Router, TypeScript, Tailwind CSS, and Supabase
authentication. It is designed for 2027 operations.

## Local setup

1. Install dependencies with `npm install`.
2. Copy `.env.example` to `.env.local` and set:
   - `NEXT_PUBLIC_SUPABASE_URL` to the Supabase project URL.
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` to that project's publishable key. Never use a
     service-role key in the browser or commit credentials.
   - `NEXT_PUBLIC_SITE_URL` to the app's origin (for example, `http://127.0.0.1:3000`).
   - `SUPABASE_SERVICE_ROLE_KEY` to the project's service-role key for server-side invitation
     delivery only. Keep it server-only and out of client bundles and version control.
3. In Supabase Auth URL configuration, allow the app origin and the
   `/auth/callback?next=/update-password` redirect for password recovery.
4. Run `npm run dev`; use `npm run typecheck` and `npm run build` to validate.

## Authentication

Sign-in is available at `/sign-in`. Password recovery sends a PKCE link through
`/auth/callback`, then allows the user to set a new password at `/update-password`.
`/dashboard` verifies the Supabase user and requires an `active` row in
`public.app_users`; missing, inactive, or suspended profiles do not receive dashboard access.
The Stage 2 migration provisions profiles for Supabase Auth users, adds the five platform roles,
permission-aware navigation, user invitations, role assignment, and account status controls.
System Administrators do not receive confidential financial permissions and cannot assign
financial-sensitive roles; that capability belongs to Financial Directors.

The Stage 1 Supabase migration is preserved as-is. The Stage 2 migration is version-controlled at
`supabase/migrations/20261125163225_stage2_roles_user_management.sql` and is not applied
automatically. It does not invent or grant a role to any account. Before opening the dashboard,
a trusted database operator must assign the initial System Administrator role to a verified,
existing Auth user; do this through a controlled administrative database session. Review and
explicitly authorize applying the migration before deploying it.