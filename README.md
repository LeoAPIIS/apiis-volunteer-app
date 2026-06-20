# APIIS Volunteer Management

A web app to manage 100+ volunteers who supervise students' Zoom classes for the APIIS online
training program.

## Features

- **Class → Group → Student** structure: 4 classes (e.g. *MMin 6P Monday Morning*), 156 groups total.
- **Attendance & assessment**: volunteers score each student's **Contribution (0–3)** per session
  (with an on-screen scoring rubric) plus an optional remark.
- **Students report (admin)**: per-student × per-week matrix, filter by class, one-click **Excel
  export** (single sheet; each session date spans a *Score* and a *Remark* column).
- **Volunteers report (admin)**: per-user attendance/coverage activity; promote/demote and delete by role.
- **CSV import (super admin only)**: students (`Name, Class, Group, Email` — **email is the unique key**) and
  volunteers (`Name, Email, Phone, Class, Group` — optional class/group auto-assigns; shared temp password).
- **Weekly availability & coverage**: volunteers confirm availability for the upcoming week;
  unavailable groups become **coverage requests** other volunteers can claim. In-app notifications +
  **email** (Resend), scheduled with **pg_cron**, skipping term-break weeks.
- **Roles (3 tiers)** — enforced by Supabase RLS + SECURITY DEFINER functions:
  - **super_admin** — appoint/remove admins; **import & delete** students/volunteers; delete anyone; cannot be deleted/demoted by others.
  - **admin** — day-to-day management (assignments, attendance, reports/export); **cannot import, delete users, or change roles**.
  - **volunteer** — records attendance, answers availability, claims coverage.
- **Account**: any user can change their own password (top-right menu → Account).

## Tech stack

Vite 8 · React 19 · TypeScript · Tailwind CSS v4 · shadcn/ui · React Router 7 · TanStack Query ·
Supabase (Postgres + Auth + RLS + pg_cron + pg_net) · Resend (email) · SheetJS / xlsx.

---

## Local development

```bash
npm install
cp .env.example .env.local      # fill in the two values below
npm run dev                     # http://localhost:5173
```

| Variable | Where to find it |
|----------|------------------|
| `VITE_SUPABASE_URL` | Supabase → Project Settings → API → Project URL |
| `VITE_SUPABASE_ANON_KEY` | same page → anon / publishable key (safe for the browser) |

Server-side secrets (Resend) live in Supabase **Vault**, never in `.env`.

| Command | Description |
|---------|-------------|
| `npm run dev` | Dev server |
| `npm run build` | Type-check + production build to `dist/` |
| `npm run lint` | ESLint |
| `npm run preview` | Preview the production build |

---

## Database setup (Supabase SQL Editor — no CLI needed)

Run in order:

1. **Schema + RLS + functions** — paste **`supabase/_apply_all.sql`** (all migrations combined) and Run.
   *(Already-deployed project: run only the new files in `supabase/migrations/`, in filename order.)*
2. **Super admin** — edit & run **`supabase/make_admin.sql`** to create/promote `itsupport@apiis.org`
   as **super_admin** (only needed if that account doesn't already exist — the super-admin migration
   promotes it automatically if it does).
3. **Email reminders** *(optional)* — edit & run **`supabase/email_setup.sql`** (Resend key in Vault).
4. **Scheduling** *(optional)* — **`supabase/pg_cron_setup.sql`** (Saturday/Sunday jobs that also email).

Migrations live in `supabase/migrations/`. CLI alternative: `supabase link` + `supabase db push`.

### Email reminders (Resend)

1. Create a [Resend](https://resend.com) account, generate an API key, verify a sender domain
   (testing: send from `onboarding@resend.dev`).
2. Store the key via `supabase/email_setup.sql` (Supabase Vault: `resend_api_key`, `resend_from_email`, `app_url`).
3. The pg_cron jobs send weekly/coverage emails. The admin **"Run now"** buttons create in-app
   notifications only (no email) to avoid accidental mass sends.

---

## Deployment (Vercel / Netlify)

Static SPA (`npm run build` → `dist/`). SPA routing config is included so deep links / refreshes work:

- **Vercel** — `vercel.json` rewrites all routes to `index.html`. Import the repo (framework: Vite).
- **Netlify** — `public/_redirects` does the same. Build `npm run build`, publish `dist`.

After deploying:

1. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in the host's environment variables.
2. Supabase → Authentication → URL Configuration: add the deployed URL to **Site URL / redirect URLs**.
3. If using email, set the Vault `app_url` secret to the deployed URL (used in email links).

---

> The only account is the super admin **`itsupport@apiis.org`** (created/promoted via `make_admin.sql`).
> Everyone else is created by importing the real volunteer CSV.

## End-to-end test checklist

1. **Super admin** (itsupport) → Admin Console → *Volunteers*: promote a volunteer to **admin**
   (shield icon — visible only to super admin).
2. **Super admin** → *Students* / *Volunteers* → **Import CSV**: import students (`Name, Class, Group, Email`)
   and volunteers (`Name, Email, Phone, Class, Group`). Re-importing the same email **updates** instead of duplicating.
3. **Admin** → *Groups & Assignments*: assign a volunteer to a group (or it was auto-assigned on import).
4. **Volunteer** → a group → set **Contribution (0–3)** + remark → Save.
5. **Admin** → *Students* (pick the class): the score/remark shows in the matrix; **Export Excel**.
6. **Admin** → *Scheduling* → **Run weekly availability check**; a volunteer answers **No**;
   **Run coverage summary** → that group becomes an open coverage request; another volunteer claims it.
7. Only a **super admin** can import or delete students/volunteers and promote/demote admins;
   nobody can delete a **super admin** or their own account. Admins manage assignments, attendance & reports.

## Project structure

```
src/
  components/   layout, route guards, attendance form, students/volunteers reports,
                scheduling, import, error boundary, ui/ (shadcn)
  pages/        Login, Dashboard, Admin, GroupAttendance, Notifications, Account
  hooks/        use-groups, use-attendance, use-assignments, use-scheduling
  lib/          supabase client, auth context (roles), report/export, csv, date & calendar helpers
  types/        shared TypeScript types
supabase/
  migrations/   schema, RLS, functions (apply in order; or use _apply_all.sql)
  make_admin.sql · email_setup.sql · pg_cron_setup.sql · cleanup_test_data.sql
```
