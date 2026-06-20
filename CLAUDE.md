# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

APIIS Volunteer Management — a web app for ~100+ volunteers who supervise students' Zoom classes for the APIIS online training program (attendance/contribution scoring, weekly availability + coverage, CSV import, admin reports).

## Commands

```bash
npm run dev        # Vite dev server (http://localhost:5173)
npm run build      # tsc -b && vite build  → dist/  (type-check is part of the build)
npm run lint       # eslint .
npm run preview    # serve the production build
```

- **Always run `npm run build` AND `npm run lint` before considering a change done** — the build is the type-check, and `tsconfig.app.json` sets `noUnusedLocals`/`noUnusedParameters`, so an unused import or variable *fails the build*. When you delete the last use of an import, delete the import too.
- **There is no test framework or test suite.** Don't look for one or invent test commands.
- Requires `.env.local` with `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (Supabase → Settings → API). Server-side secrets (Resend) live in Supabase Vault, never in env.

## Architecture

**Stack:** Vite 8 · React 19 · TypeScript 6 · Tailwind CSS v4 · shadcn/ui (radix-nova, Radix + lucide) · React Router 7 · TanStack Query v5 · Supabase (Postgres + Auth + RLS) · sonner toasts. Static SPA — no server of our own.

**The single most important fact: authorization lives in the database, not in React.** The frontend is a thin client that calls `supabase-js` (table queries + `rpc(...)`). All access control and privileged mutations are enforced server-side by:
- **Row Level Security** policies on every table.
- **`SECURITY DEFINER` functions** (RPCs) gated by `is_admin()` / `is_super_admin()` for anything privileged (creating/deleting/importing users, role changes, the weekly reminder jobs, coverage claiming). UI role checks are for UX only; never assume they enforce anything.

**Roles (3 tiers):** `super_admin` > `admin` > `volunteer`. `is_admin()` returns true for both admin and super_admin. **Only super_admin** can change roles, import (students/volunteers), or delete students/volunteers (RLS `is_super_admin()` on `students` writes + the `admin_import_volunteer`/`admin_delete_volunteer` RPCs). Admins do day-to-day work (assignments, attendance, reports/export). `itsupport@apiis.org` is the super_admin and is protected from deletion/demotion.

**Data flow:** TanStack Query hooks in `src/hooks/` (`use-groups`, `use-attendance`, `use-assignments`, `use-scheduling`) wrap all Supabase calls and own the query keys / invalidation. Auth/session/profile lives in `src/lib/auth.tsx` (`useAuth`, `roleHome(role)`); route protection in `src/components/protected-route.tsx` + `require-role.tsx`.

**Domain model:** Class → Group → Student.
- The `cohorts` table *is* the "Class" layer (UI says "Class", DB says cohort). There are 4 classes (e.g. `MMin 6P Monday Morning`) totaling 156 groups.
- `attendance_records` is the core table: one row per (student, session_date) — `unique (student_id, session_date)` enables upsert-on-save. Scoring is a single **Contribution 0–3** plus an optional note.
- `email` is the **unique key** for both students and volunteers; CSV import upserts on email (re-importing updates rather than duplicating).

**Course calendar (`src/lib/calendar.ts` + `class_sessions` table):** A fixed 66-week program, baked into `calendar.ts` from a curriculum Excel (no runtime Excel parsing). Two curricula `MMin 6` / `MMin 7` (chosen by class name via `curriculumForClass`), each weeks 0–66. Non-obvious rules:
- Week numbers are contiguous; **term breaks are gaps in the dates**, not numbered weeks.
- The **same calendar date can be a different week number per curriculum** — always map date↔week *per the student's/group's curriculum*.
- Calendar anchors are Mondays; **Tuesday classes** (`MMin 6L`, `MMin 7P`) store Monday+1 (`sessionDateForWeek`). `weekForDate` normalizes any date to its week's Monday before lookup, so reports stay correct for Monday classes, Tuesday classes, and legacy data.
- Reminders are gated by the `class_sessions` table (seeded from the calendar): the pg_cron jobs only fire when next Monday is a real session date, auto-skipping every break.

**Reports/export:** `src/lib/report.ts` builds the per-student × per-week matrix and Excel export. `xlsx` is imported **dynamically** (`await import('xlsx')`, loaded from a CDN tarball pinned in package.json) to keep it out of the main bundle — preserve this.

**Email + scheduling:** Reminders are pure SQL (`run_weekly_availability_check`, `run_summarize_coverage`) invoked by **pg_cron**; email is sent from SQL via **pg_net → Resend** (no Edge Function / CLI). Signature is `(p_send_email boolean, p_curriculum text)`; 4 cron jobs spread the weekly email volume (see `pg_cron_setup.sql`). **Availability** (`run_weekly_availability_check`, Thu MMin 6 / Fri MMin 7): `p_curriculum` filters *both* the recipients and the session-week gate (per-curriculum). **Coverage** (`run_summarize_coverage`, Sat → MMin 6 audience / Sun → MMin 7 audience): always creates coverage requests for *all* curricula's gaps and gates on any class week — `p_curriculum` filters *only the notification recipients* (cross-curriculum claiming is allowed). `p_curriculum` null = all volunteers (the admin "Run now" buttons, in-app only). Curriculum match = assignment to a cohort named `'<curriculum>%'`.

## Database / migrations workflow

- Migrations are numbered SQL files in `supabase/migrations/` (timestamp-prefixed; **apply in filename order**). There is no Supabase CLI step in the normal flow — **migrations are run by pasting SQL into the Supabase SQL Editor.** The app has only the anon/authenticated key, so Claude cannot run DDL itself; when a change needs DB work, **write the migration file and give the user the SQL to run.**
- `supabase/_apply_all.sql` is the concatenation of all migrations for fresh installs. **When you add a migration, also append it to `_apply_all.sql`** (last definition wins for `create or replace`).
- `SECURITY DEFINER` functions use `set search_path = ''`, so **every table/function reference must be schema-qualified** (`public.x`, `auth.users`, `vault.decrypted_secrets`). Changing a function's return type requires `drop function ... ` first, then recreate, then re-`grant execute`.
- Other one-off scripts: `make_admin.sql` (create/promote the super admin), `email_setup.sql` (Resend secrets → Vault), `pg_cron_setup.sql` (schedule the jobs), `cleanup_test_data.sql`.
- To validate a migration before handing it over, run it against a throwaway `postgres:16-alpine` Docker container with minimal stubs for the `auth`/`vault` schemas and the prerequisite functions (`is_admin`, `next_week_monday`, etc.); use `pg_isready -h 127.0.0.1` (TCP) to wait for readiness.

## Conventions & gotchas

- **Supabase to-one embeds**: `select('... groups(name, cohorts(name))')` returns nested objects at runtime but supabase-js types them as arrays — cast with `as unknown as { ... }` (the pattern is used throughout `report.ts` / `use-scheduling.ts`).
- **`verbatimModuleSyntax`** is on → import types with `import type`. Path alias `@/*` → `src/*`.
- **Tailwind v4, no `tailwind.config.js`.** Theme tokens are oklch CSS variables in `src/index.css` (`:root`/`.dark`/`@theme inline`). APIIS brand colors live here (`--brand`, `--brand-green`, `--navy`) plus `primary`/etc.
- **Performance is a hard constraint for visual work:** strict CSP blocks external hosts, so no external fonts/images/CDNs — use the bundled Geist font, inline SVG, CSS gradients, and optimize any raster asset before bundling under `src/`.
- **UI copy is English** (i18n may come later); inline code comments are written in Chinese — match the surrounding style.
- Design/data source files (brand PDF, logo PNG, curriculum Excel) are git-ignored; their baked outputs live in `src/assets` / `src/lib` + migrations.

## Deployment

Static SPA on **Vercel**, auto-deploys on push to `main`. SPA deep-link routing is handled by `vercel.json` rewrites and `public/_redirects`. After deploy, set the two `VITE_*` env vars in the host and add the deployed URL to Supabase Auth → URL Configuration.
