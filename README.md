# Pathfinder Music Lessons — Website & Student Portal

Public site plus a custom student portal replacing MyMusicStaff.

- **Live site:** https://www.pathfindermusiclessons.com.au
- **Portal:** https://www.pathfindermusiclessons.com.au/portal/login.html
- **Hosting:** Netlify (auto-deploys from `main` unless auto-publish is off)
- **Database & auth:** Supabase — project `oxuyzcjgxmohpqyijpip`
- **Outbound email:** Resend, sending as the domain

---

## ⚠️ Read this first: the two Supabase keys

These are both JWTs starting `eyJ...` from the same Supabase page, and confusing
them is the single easiest way to break things or leak data.

| | anon key | service_role key |
|---|---|---|
| Stored in | `portal/js/supabase-client.js` | Netlify env vars + local `.env` |
| Visible to | everyone — it ships to the browser | server only, never the browser |
| Permissions | respects Row Level Security | **bypasses all RLS** |
| `role` claim | `anon` | `service_role` |

The anon key being public is fine and by design — RLS decides what it can reach.

**The service_role key must never appear in any file under `portal/`.** If it did,
every visitor would have unrestricted read/write to every student record. It lives
only in Netlify's env vars and in the gitignored `.env`.

Both are at: Supabase → Project Settings → API Keys → **Legacy anon, service_role
API keys**. Use the *legacy* tab — the newer `sb_publishable_...` / `sb_secret_...`
formats are **not** compatible with the Supabase JS v2 client or the Admin REST API
we call from the Functions.

To check which key you're holding, decode the JWT payload and read the `role` claim.

---

## Local development

This is how to work on the portal. **Do not develop by deploying** — see the cost
warning below.

### One-time setup

Requires Node.js and Git.

```bash
git clone https://github.com/pathfindermusic/website.git pathfinder
cd pathfinder
npm install -g netlify-cli
netlify login
netlify link --name pathfindermusic
```

Then create `.env` in the repo root (already gitignored):

```
SUPABASE_URL=https://oxuyzcjgxmohpqyijpip.supabase.co
SUPABASE_SERVICE_KEY=eyJ...      # service_role, NOT anon. No quotes.
RESEND_API_KEY=re_...
```

No quotes around values — Netlify's parser doesn't strip them and the key
arrives malformed. Keep each on one line.

Netlify's *secret* env vars cannot be read back out, so these must be copied
from their original source (Supabase / Resend), not from the Netlify UI.

### Daily use

```bash
netlify dev
```

Then http://localhost:8888/portal/login.html

Serves the static files and runs `/.netlify/functions/*` locally against the
**real** Supabase and **real** Resend. Functions hot-reload on save; static files
just need a browser refresh.

**PowerShell shows stderr in red.** Git progress, npm warnings and the Netlify
CLI's startup output all appear as red "errors" and are usually fine. The real
signal of failure is the prompt returning with nothing working, or the literal
word `error` rather than `warn`.

### Two cautions when running locally

- **Emails are real.** They go through Resend to actual inboxes and count against
  the daily quota. There is no sandbox — test sends to your own address.
- **The database is production.** Deleting a student locally deletes them for real.

For password-reset testing from localhost, add
`http://localhost:8888/portal/change-password.html` to Supabase → Authentication →
URL Configuration → Redirect URLs.

---

## 💸 Deploys cost money — batch them

Netlify bills roughly **15 credits per production deploy**, flat, regardless of how
much changed. One development session burned 1,005 of 1,015 credits across 67
deploys, nearly all single-file changes. Everything else — bandwidth, functions,
compute — came to under 10 credits combined.

**So:** develop locally, commit freely, and deploy **once** when a batch is
confirmed working.

Don't compare files by hand — `git status` and `git diff` (or VS Code's Source
Control panel) show exactly what changed. Then:

```bash
git add -A
git commit -m "what changed"
git push
```

There is **no separate database deploy**: local dev runs against the production
Supabase, so migrations take effect the moment you run them, regardless of what
code is deployed. Additive changes are safe; a destructive one would break
production immediately.

Consider turning off auto-publish (Netlify → Site configuration → Build & deploy →
Continuous deployment) so pushing to GitHub doesn't trigger a build. If you do,
remember production will lag behind `main` until you deploy manually.

---

## Architecture

```
/                          repo root
├── index.html, teachers.html, pricing.html …   public marketing site
├── netlify.toml
├── netlify/functions/
│   ├── create-user.js     admin ops needing service_role:
│   │                        create / get-email / reset-password / delete-user
│   └── send-email.js      resolves recipients server-side, sends via Resend
└── portal/
    ├── login.html, change-password.html
    ├── dashboard-admin.html    dashboard-teacher.html    dashboard-student.html
    ├── students.html  teachers.html  lessons.html  notifications.html
    ├── studios.html   admins.html      (super user only)
    ├── my-students.html            (teacher's roster + skill grading)
    ├── css/portal.css
    └── js/supabase-client.js       shared helpers + anon key
```

No build step. Static HTML with vanilla JS talking directly to Supabase.
The Functions use plain `fetch` — no npm dependencies, nothing to bundle.

### Why the Functions exist

Student emails live in `auth.users`, not `profiles`, and the browser can't read
that table. Anything needing admin rights or recipient resolution has to run
server-side with the service_role key. That's the only reason these two
Functions exist.

### Roles

`superuser` → `admin` → `teacher` / `student`, stored as a single `role` on
`profiles`. **One role per account** — see Known limitations.

---

## Data model notes that bite

**Email is not in `profiles`.** It lives in `auth.users`. Any page needing an
email calls `create-user.js` with `action: 'get-email'`. This is why the edit
modals show "Loading…" briefly.

**Lesson membership is `lesson_students`, not `lessons.student_id`.** Group
lessons made the old single-column approach impossible. `lessons.student_id`
still exists as a nullable legacy column — nothing reads it. Several bugs
traced back to code still assuming the old shape; `student_teachers` is
likewise orphaned and unused.

**Attendance is per (occurrence, student).** So an individual absence in a group
lesson can be recorded. **Lesson notes are per occurrence** — deliberately
shared across a band.

**Students need `students.email` or they are unreachable.** Login emails live in
`auth.users`, but bulk-imported students have no auth account. Notifications
resolve an address in this order: auth email → `students.email` →
`parent_email`. Before the `email` column existed, a studio-wide send silently
reached only the handful of students created through the portal — the count
looked plausible, so it was easy to miss. `zoho-migration.sql` now populates it,
and the Notifications page warns about anyone with no address.

**Adding a column? Run `NOTIFY pgrst, 'reload schema';` afterwards.** Supabase
caches the schema, so until PostgREST refreshes, every write including the new
column fails with *"Could not find the 'x' column of 'y' in the schema cache"* —
which reads like a code bug and isn't.

**Instrument labels are compared as exact strings.** Skill grading, lesson
instrument filtering and teacher-instrument validation all match on the literal
value, so a mismatch fails silently rather than erroring. Zoho and the website
form used "Piano / Keyboard" and "Voice" where the portal used "Piano" and
"Voice / Singing". The canonical list now lives in three places —
`lessons.html`, `students.html`, `teachers.html` — and they must stay identical.

**Dates: never `new Date("2026-07-29")`.** That parses as UTC midnight, which is
the previous day in AEST, and silently shifts lessons a day earlier. Use
`parseLocalDate()` from `supabase-client.js`, or compare the `YYYY-MM-DD` strings
directly. `toISODate()` builds from local date parts for the same reason.
This caused a real bug where Wednesday lessons appeared on Thursday.

### Views

- **`schedule_view`** — one row per occurrence. Admin and teacher dashboards.
  Exposes `student_count`, `attendance_marked_count`, `fully_marked`.
  `attendance_status` is only meaningful for single-student lessons.
- **`student_schedule_view`** — one row per (occurrence × student), so students
  can filter by `student_id` and group lessons appear for every member.

Attendance is joined by **subquery** in `schedule_view`, not `LEFT JOIN` —
a join would fan the view out to one row per student and duplicate every group
lesson on the admin grid.

---

## Email: two separate systems

| | Sends | From | Templates | Limit |
|---|---|---|---|---|
| **Resend** (via `send-email.js`) | portal notifications | the studio's address | in `send-email.js` | Resend plan: free = 100/day |
| **Supabase Auth** (via Resend SMTP) | password resets | `info@` | Supabase → Auth → Email Templates | 30/hour, configurable |

Supabase Auth was switched to Resend's SMTP so resets are branded and no longer
capped at 2/hour. Consequence: **a Resend outage now blocks password resets too.**
Fallback is setting a password directly in Supabase → Authentication → Users.

### DNS

Root domain verified in Resend. Records live alongside Google Workspace without
conflict because they're on different hostnames:

- `resend._domainkey` (DKIM) coexists with `google._domainkey`
- `send.` MX and SPF are scoped to the subdomain, so the apex Google SPF is untouched
- **Never add a second SPF record to the same hostname** — it breaks auth for both

`info@pathfindermusiclessons.com.au` is a **Google Group** with both studio
mailboxes as members, which is why it doesn't appear under Users. Replies to
portal email reach whichever studio is working.

### Notification template conventions

`{{first_name}}`, `{{student_name}}`, `{{instrument}}`, `{{teacher_name}}`,
`{{lesson_time}}`, `{{lesson_day}}`, `{{studio}}` substitute in subject and body.

A paragraph wrapped entirely in `**double asterisks**` renders as a highlighted
callout block; `**bold**` works inline. Used for lesson notes in emails.

Every recipient gets an individual email — no shared To lists. Where a student
has `parent_email`, both addresses receive it. A BCC copy goes to the sending
studio as the only record of what went out (it lands in Inbox, not Sent).

---

## Decisions already made (don't relitigate without reason)

- **Attendance rate = present ÷ all lessons that have ENDED.** Unmarked counts
  against the student. Chosen deliberately over "present ÷ marked", which hid
  the gap. Consequence: a teacher marking late briefly worsens their students'
  rates, which is also the incentive to mark promptly.
- **"Has the lesson ended", not "is it before today".** A lesson in progress
  isn't yet missed. All three dashboards use the same test.
- **Group lessons: attendance per student, notes shared.** Band notes go to the
  whole group; absences are individual.
- **Bulk sends get one studio summary, not one BCC per student.** 500 BCCs would
  bury the studio inbox. Single-recipient sends still BCC.
- **Cancelling a series keeps earlier occurrences on the grid** as history and
  hides everything from the cancellation point. It also sets `lessons.status`
  to cancelled, which frees the slot for rebooking — clash detection only
  considers active lessons.
- **Teacher detail page is read-only**; Edit bounces back to the Teachers page
  rather than duplicating the edit modal's validation logic.

## Row Level Security — read this before touching a policy

Four findings, each of which cost real time. The last one is subtle and
still load-bearing in several policies.

**Run policy changes ONE STATEMENT AT A TIME.** Several DDL statements sent
together to the Supabase SQL editor can apply *partially* — policy names
created while the bodies stay stale — with no error. A whole session went
into diagnosing an update that `pg_policies` said should have been allowed,
because the policy being enforced was not the policy being displayed.

**Always re-read the body afterwards**, not just the name:

```sql
SELECT policyname, permissive, cmd, qual, with_check
  FROM pg_policies WHERE tablename = '<table>' ORDER BY policyname;
```

**Leftover permissive policies are additive and silent.** Renaming a policy
during a rewrite leaves the old one in place, and permissive policies OR
together — so the old, broader rule quietly wins. Drop by the old name
explicitly.

**A policy that subqueries another RLS-protected table inherits that
table's visibility.** This looks like an existence check:

```sql
task_id IN (SELECT id FROM tasks)
```

but it actually means *"…among tasks I can see"*. Once a task moved to
another studio it became invisible, so the condition could never hold and
the operation failed with no useful error. This pattern is currently in the
`task_notes`, `task_handovers` and teacher policies. It works in each case
today — but it is doing more than it appears to.

### Testing a policy as another user

The SQL editor bypasses RLS, so policies look fine from there. Impersonate
instead — wrapped in a rollback, so nothing is written:

```sql
BEGIN;
  SET LOCAL role TO authenticated;
  SET LOCAL request.jwt.claims TO '{"sub":"<user-id>","role":"authenticated"}';
  SELECT get_my_role(), get_my_studio_ids();
  -- then the actual query or update that is failing
ROLLBACK;
```

### Task handover

`tasks.studio_id` and `assigned_to` must be changed through
`hand_over_task()`, never by a direct update. The function writes the
handover record and performs the move in one transaction. Two separate
writes produced phantom trail entries for handovers that never completed.

### Everything else about tasks

**Who can write what.** Admins have normal access, scoped by studio. Teachers
have **no** write access to `tasks` or `task_notes` at all — they reply through
`teacher_reply_to_task()`, which is `SECURITY DEFINER` and checks that the task
is genuinely about them. Same pattern as `hand_over_task()`: the checks inside
the function *are* the security boundary.

**Visibility.** `can_see_task(studio, assignee)` holds the rule in one place. An
admin sees a task when it belongs to one of their studios, **or** it is assigned
to them wherever it sits, **or** it has neither studio nor assignee — the shared
queue. Claiming a shared task therefore removes it from everyone else's list,
which is intended.

**Kinds.** `task` and `waitlist`. Waitlist entries are open-ended and have no due
date, so they are excluded from Overdue, Due Today, Next 7 Days, Unassigned and
All Open, and have a bucket of their own. Without that they would silently
accumulate in the main list.

**Tasks follow a student between studios.** A trigger on `students` moves open
tasks when `studio_id` changes, leaves them **unassigned** so they land in the
receiving studio's queue rather than being pushed at one named admin, and writes
a handover record explaining why. Closed tasks stay put — they are history.

**The log is one timeline.** Notes and handovers are merged and sorted together.
Handover records were written from the start but had nothing displaying them for
several days, so a task could change hands with nothing in the thread explaining
it.

**Buckets and the status filter used to fight.** The bucket filter ran first and
forced open-only, so choosing Done returned nothing. They now cooperate: picking
a date bucket resets the status filter, and vice versa.

## Traps that have already cost time

- **Check which environment you're looking at.** Local dev runs against the same
  Supabase as production, so data looks identical while the *code* differs by
  weeks. A wrong number is more often a stale page than a logic bug. Check the
  URL first.
- **Resend rejects `example.com`** and similar test domains, and its batch
  endpoint is all-or-nothing — one bad address kills the whole chunk. Use
  `yourname+alias@gmail.com` for test recipients. Addresses are now validated
  before sending, and skipped ones are reported.
- **`redirect_to` on `/auth/v1/recover` must be a QUERY parameter.** In the body
  it's silently ignored and Supabase falls back to the Site URL.
- **PowerShell prints stderr in red.** Git progress and npm warnings look like
  failures and aren't.

## Known limitations & open decisions

- **One role per account.** Miranda teaches *and* administers; ~3 such cases.
  Workaround is a separate email per role. Proper fix is `role` → `roles[]`
  plus RLS and login changes.
- **RLS is not enforced on views.** Supabase views run as owner by default. The
  frontend always filters correctly, so the dashboards are right — but the views
  would return other students' rows if queried directly with the anon key.
  Fixing needs `security_invoker = on` plus read policies across ~8 underlying
  tables. **Should be closed before go-live.**
- **Not built:** attendance report (sidebar link is dead), teacher Lesson Notes
  page, email history page. `send-email.js` already records every send in
  `email_log` including each recipient's Resend message ID, so a history page
  can show delivery status without further backend work. Per-recipient
  delivery/bounce status at scale would want Resend webhooks rather than
  polling.
- **Resend free tier is 100/day.** A studio-wide announcement to ~500 students
  exceeds it. Budget for the paid tier before first bulk send.
- **Bulk migration.** MyMusicStaff only exports PDF; Zoho CRM covers only students
  who came via enquiry, since admins enrolled some walk-ins directly. Imported
  students get no auth account — created on demand. `zoho-migration.sql` drops the
  `profiles.id → auth.users` FK to allow this.
- **Google Workspace DKIM** is enabled but worth confirming the selector matches.

---

## Applied SQL migrations

Run in order. All are re-runnable.

1. Initial schema — tables, RLS, `get_my_role()`, `get_my_teacher_id()`
2. `zoho-migration.sql` — Zoho CRM leads import
3. v0.3 — `lesson_type`, `max_students`, `series_notes`, `occurrence_notes`,
   `lesson_students`, `teachers.teaching_room`, `profiles.must_change_password`,
   `students.studio_id`
4. `ALTER TABLE lessons ALTER COLUMN student_id DROP NOT NULL`
5. `phase3-email.sql` — `email_log`, rebuilt `schedule_view`
6. Teacher RLS — read own students / profiles / instruments, plus insert & update
   on `student_instruments`
7. `student-schedule-view.sql`
8. `per-student-attendance.sql` — `attendance.student_id`, both views rebuilt
9. `student-contact-email.sql` — `students.email` (see below — this one matters)
10. `normalise-instruments.sql` — one canonical instrument list
11. `phase4a-tasks.sql` — tasks, contact log, handovers
12. `phase4a-admin-read-policy.sql` — admins can see each other
13. `phase4a-handover-function.sql` — `hand_over_task()`
14. `phase4a-task-visibility.sql` — assignment overrides missing studio
15. `phase4a-waitlist-and-transfer.sql` — `tasks.kind`, tasks follow a student
    who changes studio
16. `phase4a-outcome-values.sql` — contact-log outcomes matched to method
17. `phase4a-teacher-replies.sql` — `tasks.awaiting_admin`,
    `teacher_reply_to_task()`

---

## Testing status

**Working end to end:** super user, admin and studio management; teacher and
student CRUD with temp-password modal and duplicate detection; forced password
change on first login; password reset via both the login page and the admin
button; lessons daily grid with clash detection and date picker; group lessons;
agenda PDF; teacher dashboard including per-student group attendance, notes and
skill grading; teacher detail page; student dashboard; **all seven notification
scenarios**, including bulk sends, the studio summary email, and the automatic
cancellation notice with wording that varies by scope.

**Untested:** CSV import through the portal UI (bulk import is done via
`zoho-migration.sql` instead).

**Phase 4a (tasks) complete and tested by both studios.** Quick capture,
contact log with attempt counting and method-specific outcomes, studio-scoped
dashboard, cross-studio handover with the history intact, waitlist entries,
tasks following a student between studios, and a teacher reply loop.

Admins and teachers began using the reply loop as a back-and-forth chat within
hours, which nobody designed for. Two things will chafe if that continues:
nobody knows a reply has arrived until they next log in, and long threads read
newest-first. Worth watching before acting.

**Next up:** Phase 4b (enquiries, Prospective/Lapsed statuses); attendance
report page; RLS on views before go-live.

**Teacher landing page.** The teacher dashboard shows an open-task count —
red when non-zero — and a strip listing outstanding tasks above the schedule.
The strip is hidden entirely when there is nothing outstanding, so the schedule
stays the main thing on a normal day.

**Small gaps worth knowing:** the Admins page only lists accounts that have an
`admins` row, so a profile with `role='admin'` and no row is invisible and
unmanageable there. Password reset links always point at production, because
the redirect is hardcoded in `create-user.js` — they still work from local
development, they just land on the production page.
