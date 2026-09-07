# Self-Hosting Setup Guide

This guide walks you through standing up your **own independent copy** of the APIIS Volunteer
Management app — to manage your own volunteers who record students' Zoom-class attendance and
contribution scores.

Each organization runs a fully separate instance: **your own code deployment, your own Supabase
database, and your own email account.** Nothing is shared with any other instance — separate data,
separate logins, separate keys.

> **This guide assumes the same program as APIIS** — the same MMin 6 / MMin 7 curriculum, the same
> 66-week calendar, and the same class/group structure. If your program differs, see
> [Customizing for a different program](#customizing-for-a-different-program) at the end.

---

## What you'll end up with

- A website (your app) hosted on **Vercel**, at your own URL.
- A **Supabase** project holding all your data (Postgres + Auth + scheduled jobs).
- Weekly **email reminders** (availability checks + coverage requests) sent through **Resend**.

## Architecture at a glance

- **Frontend:** a static single-page app (React + Vite). Vercel just serves files; the browser
  talks **directly** to Supabase.
- **Backend:** Supabase (Postgres database, Auth, Row-Level Security, `pg_cron` scheduled jobs,
  `pg_net` for outbound HTTP, Vault for secrets). All access rules and privileged actions live in
  the database, not the browser.
- **Email:** sent from the database (SQL → `pg_net` → Resend). No separate mail server.

## Before you start — accounts you'll need (all have a free tier)

| Service | What for | Sign up |
|---|---|---|
| **GitHub** | Hold your copy of the code | https://github.com |
| **Vercel** | Host the website | https://vercel.com |
| **Supabase** | Database, auth, scheduled jobs | https://supabase.com |
| **Resend** | Send the reminder emails | https://resend.com |

The free tiers are enough for ~100+ volunteers.

---

## Step 1 — Get your own copy of the code

You want your **own** repository (not a shared one), so your deployment is independent.

**Option A — "Use this template" (recommended).** Ask the owner of the original repo to enable
*Template repository* (repo **Settings → General → Template repository**). Then click
**"Use this template" → Create a new repository** to get your own copy under your GitHub account.

**Option B — Fork.** From the original repo, click **Fork**.

Either way you now have your own GitHub repo. You do **not** need to run anything locally — Vercel
builds from GitHub.

---

## Step 2 — Create your Supabase project

1. Log in to Supabase → **New project**.
2. Choose an organization, a name, a strong **database password** (save it), and a region close to
   your users.
3. Wait for it to finish provisioning (~2 minutes).

Keep the project's **Project URL** and **anon public key** handy — you'll need them in Step 6.
They're under **Settings → API**.

---

## Step 3 — Build the database

Everything (tables, security policies, functions, and the seeded classes & groups) is in one file:
`supabase/_apply_all.sql`.

1. In your Supabase project, open **SQL Editor → New query**.
2. Open `supabase/_apply_all.sql` from the repo, copy **the entire file**, paste it in, and **Run**.

This creates all tables, all Row-Level-Security policies, all functions, and seeds the **4 classes
and 156 groups** for the MMin program. (One line in the file promotes `itsupport@apiis.org` to
super-admin — for you that email doesn't exist yet, so that line simply does nothing. You'll create
your own admin in the next step.)

> If you ever see an error part-way through, fix it and re-run — the file is safe to run again
> (it uses `create ... if not exists` / `create or replace`).

---

## Step 4 — Create your super-admin login

The super-admin can do everything (create/remove admins, import and delete people, change roles).
Protection is by **role**, not by a specific email — so use **your own** admin email.

1. Open `supabase/make_admin.sql`.
2. **Replace every `itsupport@apiis.org`** in that file with **your own admin email**
   (there are a few occurrences).
3. Change the initial password `pw := 'ChangeMe-123'` to something you choose.
4. Paste the edited file into **SQL Editor** and **Run**.

You can verify with the query commented at the bottom of that file — it should show your email with
role `super_admin`.

---

## Step 5 — Set up email (Resend + Vault)

Reminder emails go out through Resend. Keys are stored in Supabase **Vault** (never in a normal
table).

1. In **Resend**: create an **API key** (starts with `re_`), and **verify a sending domain** (for
   real delivery). For a quick test you can send from `onboarding@resend.dev`.
2. Open `supabase/email_setup.sql` and fill in your three values:
   - `resend_api_key` → your `re_…` key
   - `resend_from_email` → e.g. `Your Org Volunteers <noreply@yourdomain.com>`
   - `app_url` → your app's URL (you'll have this after Step 6 — you can set a placeholder now and
     update it later)
3. Paste it into **SQL Editor** and **Run**.

To update a value later, use the `vault.update_secret(...)` example commented in that file.

> Resend's free tier limits sends to **2 requests/second** — the app already batches emails to stay
> under this, so no action needed.

---

## Step 6 — Deploy the frontend to Vercel

1. Log in to Vercel → **Add New… → Project** → **Import** your GitHub repo from Step 1.
2. Framework preset: **Vite** (Vercel usually detects it). Build command `npm run build`, output
   `dist` — the defaults are correct.
3. Add two **Environment Variables** (from your Supabase **Settings → API**):
   - `VITE_SUPABASE_URL` = your Project URL (e.g. `https://abcd.supabase.co`)
   - `VITE_SUPABASE_ANON_KEY` = your anon public key
4. **Deploy.** When it finishes, note your live URL (e.g. `https://your-app.vercel.app`).

Now go back to **Step 5** and set `app_url` to this real URL (so email links point to your app).

> The repo already includes `vercel.json` and `public/_redirects` so deep links (e.g. refreshing on
> `/admin`) work correctly — no extra config needed.

---

## Step 7 — Point Supabase Auth at your site

So password-reset links redirect back to your app:

1. Supabase → **Authentication → URL Configuration**.
2. Set **Site URL** to your Vercel URL, and add it under **Redirect URLs** too.

**(Optional but recommended) password-reset emails via Supabase SMTP:** by default Supabase sends
auth emails from its own address with tight rate limits. To send from your domain, go to
**Authentication → Emails / SMTP settings** and plug in your Resend **SMTP** credentials.

---

## Step 8 — Schedule the weekly jobs

The reminders and weekly cleanups run on `pg_cron`.

1. Open `supabase/pg_cron_setup.sql`, paste into **SQL Editor**, and **Run**.

This enables `pg_cron` + `pg_net` and schedules:

| Job | When (Singapore time, UTC+8) | Does |
|---|---|---|
| availability-mmin6 | Thu 20:00 | Ask MMin 6 volunteers if they're available next week |
| availability-mmin7 | Fri 20:00 | Ask MMin 7 volunteers |
| coverage-all | Sat 23:00 | Broadcast groups needing coverage |
| clear-manual-assignments / clear-group-checkmarks | Wed 09:00 | Weekly clear of temp assignments & marks |
| expire-coverage | Wed 09:00 | Remove last week's temporary coverage |

> **Timezone:** the app is wired to **Singapore time (UTC+8)** — the cron times above are the UTC
> equivalents, and the in-app deadlines use UTC+8 too. If your organization is in a different
> timezone, see [Timezone](#timezone) below.

Verify with: `select jobname, schedule, active from cron.job order by jobname;`

---

## Step 9 — Sign in and import your people

1. Open your Vercel URL and **log in** with your admin email + the password from Step 4.
2. The **4 classes and 156 groups already exist** (seeded in Step 3) — you don't create those.
3. Import your **volunteers** and **students** via CSV, on the **Volunteers** and **Students** pages
   (**Import CSV**, super-admin only):
   - Volunteers: `Name, Email, Class, Group` — new accounts get the initial password `123456`.
   - Students: `Name, Class, Group, Email`.
   - `Email` is the unique key; re-importing the same email updates that person.

---

## Step 10 — Verify everything works

- [ ] You can log in as super-admin; the **Admin Console** shows Groups, Records, Students,
      Volunteers, Scheduling, History, Feedback.
- [ ] A test volunteer can log in, open a group, and record attendance (it **auto-saves**).
- [ ] `select name from vault.decrypted_secrets;` shows `resend_api_key`, `resend_from_email`,
      `app_url`.
- [ ] `select jobname from cron.job;` shows the scheduled jobs.
- [ ] (Optional) Send yourself a test email — in SQL Editor, as the project owner:
      `select public.run_weekly_availability_check(false);` runs it **in-app only** (no email);
      passing `true` would email volunteers, so only do that when you're ready.

---

## Customizing for your organization

### Branding / logo
The APIIS logo and brand colors are baked into the frontend (`src/assets/` and the CSS variables in
`src/index.css`). Replace the logo asset and adjust the color tokens, then push to GitHub — Vercel
redeploys automatically.

### Timezone
The app assumes **Singapore / UTC+8**. If you're elsewhere, change:
- `src/lib/date.ts` (`todaySG` — the `Asia/Singapore` timezone) and `src/lib/deadlines.ts`
  (the `TZ = 8` constant) for the in-app "today" and deadlines, then push.
- `supabase/pg_cron_setup.sql` cron times (they're written in UTC; adjust so they fire at the local
  times you want), then re-run it.

### Language
The app's **interface is in English**. Your data — student names, notes, etc. — can be in any
language and displays fine. Translating the **UI** into another language is a separate effort
(internationalization); it isn't part of setup. If your team needs a translated UI, that's a
development task to add later.

### Customizing for a different program
This guide assumes the **same MMin 6 / MMin 7 curriculum and 66-week calendar** as APIIS. If your
program has different weeks, dates, or class structure, two things must be adapted (both are
development work):
- `src/lib/calendar.ts` — the baked 66-week calendar for both curricula.
- The seeded classes/groups (in the migrations) — replace with your own structure.
Ask a developer to regenerate these for your program before importing people.

---

## How updates & migrations work (ongoing)

- The database is built and changed via **numbered SQL files** in `supabase/migrations/`, applied by
  **pasting them into the Supabase SQL Editor** in filename order. There is no automated migration
  step.
- `supabase/_apply_all.sql` is the concatenation of every migration — that's what you ran in Step 3
  for a fresh install.
- When you pull new code that includes a new migration, run that migration's SQL in your Supabase
  SQL Editor. New frontend code deploys automatically when you push to GitHub (Vercel).

## Security notes

- **Never share your Supabase keys or Resend key** — each instance uses its own. Sharing them would
  give access to your data.
- The **service-role key** (Supabase → Settings → API) bypasses all security. Keep it secret; the
  app does **not** use it in the browser — only the anon key.
- All access control lives in the database (Row-Level Security + admin-gated functions). The
  frontend's role checks are for convenience only.

## Troubleshooting

- **Login works but pages are empty / permission errors** → re-check that `_apply_all.sql` finished
  without error (Step 3).
- **Emails not sending** → check `select name from vault.decrypted_secrets;` shows all three secrets,
  your Resend domain is verified, and the cron jobs exist. Inspect delivery in the Resend dashboard.
- **Password reset link goes nowhere** → set the Site URL / Redirect URLs (Step 7).
- **Weekly reminders didn't fire** → confirm the week is a real class week (they auto-skip term
  breaks), reminders are enabled (Admin → Scheduling), and the cron jobs are `active`.
