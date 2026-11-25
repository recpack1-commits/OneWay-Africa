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
3. In Supabase Auth URL configuration, allow the app origin and the
   `/auth/callback?next=/update-password` redirect for password recovery.
4. Run `npm run dev`; use `npm run typecheck` and `npm run build` to validate.

## Authentication

Sign-in is available at `/sign-in`. Password recovery sends a PKCE link through
`/auth/callback`, then allows the user to set a new password at `/update-password`.
`/dashboard` verifies the Supabase user and requires an `active` row in
`public.app_users`; missing, inactive, or suspended profiles do not receive dashboard access.
User provisioning and role-aware navigation are intentionally not included in this stage.

The Stage 1 Supabase migration is preserved as-is. Do not apply database migrations or create
additional migrations without explicit authorization.