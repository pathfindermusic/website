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
├── admin/                  Decap CMS editor (Sep 2026) — see How-To Guide below
│   ├── index.html          loads Netlify Identity + the Decap CMS bundle
│   └── config.yml          git-gateway backend, guide collection, media folder
├── netlify/functions/
│   ├── create-user.js     admin ops needing service_role:
│   │                        create / get-email / reset-password / delete-user
│   └── send-email.js      resolves recipients server-side, sends via Resend
└── portal/
    ├── login.html, change-password.html
    ├── tasks.html              post-login landing page for admin/superuser
    ├── enquiries.html  notifications.html
    ├── lessons.html    students.html    teachers.html    teacher-detail.html
    ├── attendance-report.html
    ├── distribution-lists.html (Bcc-ready address lists for Gmail — see below)
    ├── bok-artefacts.html      (Guitar-only artefact library — see Skill grading below)
    ├── dashboard-teacher.html    dashboard-student.html
    ├── dashboard-admin.html    NOT in the sidebar any more (Sep 2026 nav reorg) —
    │                             still on disk, reachable by direct URL only
    ├── studios.html   admins.html      (super user only)
    ├── my-students.html            (teacher's roster + skill grading)
    ├── manuals/                     How-To Guide (Sep 2026) — see below
    │   ├── index.html    system-overview.html
    │   ├── admin-guide.html    teacher-guide.html    student-guide.html
    │   ├── manuals.css
    │   ├── guide-content.js   shared fetch/render/TOC script — the one
    │   │                        deliberate exception to "duplicate per page"
    │   │                        below, since all four guides need the same
    │   │                        logic and only the .md path differs
    │   ├── content/            Decap-CMS-managed guide text (Sep 2026)
    │   │   ├── system-overview.md    admin-guide.md
    │   │   └── teacher-guide.md      student-guide.md
    │   └── images/uploads/     screenshots added via the CMS land here
    ├── css/portal.css
    └── js/supabase-client.js       shared helpers + anon key
```

No build step. Static HTML with vanilla JS talking directly to Supabase.
The Functions use plain `fetch` — no npm dependencies, nothing to bundle.

**Sidebar order (Sep 2026 reorg):** Front desk (Tasks, Enquiries, Notifications)
→ Teaching (Lessons, Students, Teachers) → Curriculum (Artefact Library) →
Reports (Attendance, Distribution Lists) → Super User (hidden unless
superuser) → **Manuals (How-To Guide)**, added to the bottom of every role's
sidebar — admin, teacher and student alike. `tasks.html` and `enquiries.html`
build it dynamically via `renderSidebar()`; every other admin-facing page
(11 of them, plus the 2 teacher pages and the student dashboard) duplicates
the same static markup — a page added to one has to be added to all the
others by hand, there's no shared include. This bit dashboard-admin.html once
already: it kept its own full copy of the sidebar from before the Sep 2026
nav reorg and was still missing the later Distribution Lists entry until the
How-To Guide pass added both that and Manuals in the same edit — a reminder
to check *every* duplicate, including pages nothing currently links to.

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

**`deferrable` is a reserved word in Postgres**, as are `references`, `user`,
`order` and `limit`. The error points at the line but not the reason. The
column that wanted that name is `can_defer`.

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

**A student's name lives on `students.first_name`/`last_name`, not
`profiles`.** (Phase 10, Oct 2026.) It used to live only on `profiles`, keyed
by `students.user_id` — fine while every student had their own login, but
siblings sharing one family login (see "Shared family logins" below) also
share that one profile, so every page reading a name via the profile showed
the same name for all of them, and editing one changed it for every sibling
on that login. `profiles` is now the *login's* identity only (used for
Reset PW and the one place a shared login sees itself — the top nav, which
shows "`{{last_name}} family`" for a student role rather than one child's
name). Every student-facing name read or write — the students list, lessons,
teacher dashboards, notifications, task subjects, `send-email.js` — now goes
through the student's own columns, falling back to the profile only for a
record that somehow has neither. New student records (enquiry intake, Add
Student, CSV import) set both columns going forward.

### Views

- **`schedule_view`** — one row per occurrence. Admin and teacher dashboards.
  Exposes `student_count`, `attendance_marked_count`, `fully_marked`.
  `attendance_status` is only meaningful for single-student lessons.
  `student_name` (private lessons only) prefers `students.first_name`/
  `last_name` over the shared profile (phase 11, Oct 2026).
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
| **Resend** (via `receive-enquiry.js`) | enquiry acknowledgement + studio notification | the matched studio's address, `admin@` if none matched | in `receive-enquiry.js` (not `emailTemplate()` — see Phase 4d) | same Resend plan |
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

**The footer's postal address is looked up per send, not hardcoded (Sep
2026).** `emailTemplate()` in `netlify/functions/send-email.js` used to have
both studios' addresses baked into the footer as a literal string, so a
Ringwood email's footer showed Kilsyth's address too, and vice versa — and
neither followed what was actually entered on the Studios page (`studios.
address`, the same field the Studios admin screen edits). It now resolves
the *sending* studio's own `address` by matching `studios.email` against
`fromEmail` once per send, and passes it into `emailTemplate()`; a studio
with no address on file simply gets no address line, rather than a blank or
wrong one. The lookup is best-effort — a failure logs a warning and omits
the line rather than failing the whole send over a footer.

**`{{portal_link}}` (Sep 2026) — a personal, one-time Portal sign-in link,
not a stored password.** Added for the Portal-launch announcement to every
active student, but it's a general-purpose token, available in any
Notification from here on. There is no way to read back a student's actual
password — Supabase Auth never stores it in a recoverable form — so this
generates a fresh `type: 'recovery'` link per recipient via Supabase's
Admin `generate_link` endpoint (`generatePortalLink()` in
`send-email.js`), which returns a URL without sending anything itself,
unlike the public `/auth/v1/recover` endpoint `create-user.js`'s
`reset-password` action uses (that one sends Supabase's own bare,
unbranded email immediately and gives nothing back to reuse — the two look
similar but solve different problems). The link redirects to
`change-password.html` after verifying, same as every other password flow
in this app; same `redirect_to`-must-also-be-a-query-param defensiveness
as the existing `/recover` call, since GoTrue's handling of that field has
already bitten this project once.

Deliberately **does not create accounts.** "Add login" on the Students
page is an interactive, admin-judgment flow (`students.html`'s `addLogin`)
because it prompts the admin to pick a login email by hand — siblings
often share one family address, so there's no safe way to guess a correct
one automatically. A student with no `user_id` yet is therefore left out
of that particular send rather than mailed a dead link, and named in both
the function's JSON response (`skippedNoLogin`) and the studio summary
email, so an admin can use Add Login for them individually and follow up
separately.

Only resolved when a message actually contains the token (`needsPortalLink`
in `send-email.js`) — one Supabase Admin API call per recipient is real
cost, so every other Notification (the overwhelming majority) is
completely unaffected and exactly as fast as before. When needed, lookups
run with bounded concurrency (`mapLimit`, 15 at a time) rather than one at
a time, to keep a few hundred recipients from approaching the function's
execution time limit.

**`students.email` having a value is not proof a real login exists (fixed
1 Oct 2026).** A website enquiry (`receive-enquiry.js`) writes the
submitted address straight into `students.email` at intake — functionally
the parent's address, for a minor — with a freshly minted `user_id` that
was never passed to Supabase Auth at all (`profiles.id` has no foreign key
to `auth.users`, which is what allows an enquiry to exist with no login).
Converting that enquiry through to an active enrolment never touches
`email`/`parent_email` — `startProcess()` only updates `status`. So a
student can go all the way from website enquiry to fully active with
`students.email` genuinely populated the whole time, yet no real
`auth.users` row ever created for her.

Two places assumed `students.email` truthy meant "has a login" and were
wrong for exactly this student:
- The Students list's Add login/Reset PW button (`renderStudents()`) —
  showed "Reset PW" for her, which would have tried to reset a password
  for an account that doesn't exist. Now checks `authUserIds.has(s.user_id)`
  — a `Set` of every real `auth.users` id, bulk-fetched once per
  `loadStudents()` via a new `list-user-ids` action on `create-user.js`
  (ids only, no emails — one admin-API list call for the whole page,
  instead of one per student).
- The student modal's Email Address field (`openStudentModal()`) — used
  to fetch from `auth.users` via `create-user.js`'s `get-email` action
  instead of reading `students.email` directly, so it showed blank for
  this exact student: no login existed, so the lookup found nothing,
  while the real address sat untouched in the column underneath the whole
  time. Now reads `student.email` directly (synchronous, no network call)
  and shows login status as a separate, informational hint alongside it.
  Saving this field only ever writes that one column either way — editing
  or adding an email here, on an *existing* student, has never created or
  touched a login; "Add login" is a fully separate, manual, admin-chosen
  action. (The one place typing an email *does* auto-create a login is
  the **Add Student** form, for a brand-new record — `saveStudent()`'s
  `!editId` branch calls `create-user.js` directly when `email` is set.
  An *existing* student's Edit form never does.)

**Ongoing enrolment now creates its own portal login, and the "You're
enrolled" email links straight to it (Oct 2026).** Previously an admin had
to click "Add login" by hand for every converted student, then separately
tell them their temp password — a step easy to forget precisely because
nothing else in the flow depends on it. `ensureLoginForEnrolment()` in
`processes.js` runs inside `maybeSendConfirmation()`, right before the
enrolment email is built (never for a trial): if the student already has a
real login it does nothing; otherwise it tries `students.email ||
students.parent_email` against `create-user.js`'s `create` action, the same
call `addLogin()` makes by hand, and on success re-points `user_id` at the
new auth id exactly as `addLogin()` does.

**No temp password is ever emailed.** The email instead carries
`{{portal_link}}` — the one-time Supabase recovery link already built for
the Portal-launch announcement (`generatePortalLink()` in `send-email.js`;
see that section above) — resolved fresh at send time from the `user_id`
`ensureLoginForEnrolment()` just set. The student clicks it, lands on
`change-password.html`, sets their own password; nothing sensitive is
generated, stored or transmitted in plaintext. `maybeSendConfirmation()`
only swaps in the `{{portal_link}}` sentence when login creation actually
succeeded (`hasPortalLink`); otherwise the email keeps today's generic "you'll
receive a link to log in shortly" wording, so a hiccup here degrades
gracefully instead of silently dropping the recipient — `send-email.js`
excludes anyone it can't resolve a portal link for *entirely* from a send
that asks for one, which is exactly right for a bulk blast but would be
wrong for a single enrolment confirmation.

**Deliberately does not touch the shared-family-login case.** ~5% of
students share one login across siblings, set up today by leaving every
sibling but one's `students.email` blank — that case simply has no
candidate address here and is left alone, same as always. The rarer case —
two siblings each entered through their own separate website enquiry,
naming the same parent email — hits `create-user.js`'s existing "already
registered" (`existed: true`) the moment the second one tries to
auto-create a login; `ensureLoginForEnrolment()` treats that as the
expected shared-login situation, not an error, and leaves that student's
record untouched rather than guessing at a fix. Raised and decided
explicitly (1 Oct 2026): auto-linking siblings on that collision was
considered and rejected in favour of leaving it exactly as admins already
handle it by hand.

The **"All active students — every studio"** audience in Notifications
(`mode: 'all'`) already existed server-side — `distribution-lists.html`
has used it for a while — it just wasn't offered as a Notifications radio
option until this was added. Active only, not trial, matching what
"active student" means everywhere else on Reports/Distribution Lists.

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
- **Tasks is the post-login landing page for admin and superuser (Sep 2026),
  not the Schedule dashboard.** `login.html`'s `redirectByRole()` sends both
  roles to `tasks.html`. The Schedule link was dropped from every sidebar at
  the same time — `dashboard-admin.html` itself was left on disk rather than
  deleted (nothing has ever needed it gone, and history/links pointing at it
  shouldn't 404), but it's now reachable only by typing the URL directly.
- **Cloning a lesson occurrence (Sep 2026) is a new one-off lesson, not a copy
  of `lesson_occurrences` alone.** `lessons.html`'s occurrence modal has a
  "Clone to new timeslot" button that inserts a fresh `lessons` row (teacher,
  studio, instrument, lesson type, duration all copied from the source) plus
  its single `lesson_occurrences` row at the chosen date/time, plus
  `lesson_students` rows replicating the exact roster the source occurrence
  had (permanent members + any ad-hoc guest on that occurrence). Occurrence
  notes and attendance are deliberately NOT copied — the clone is a fresh,
  unmarked lesson. It reuses the same teacher-availability hard-block and
  "freed slot" clash detection (absent/teacher-cancelled occurrences don't
  block) that `saveLesson()` uses, scoped to the one target date.
- **A one-off's Day field is derived from its date, not independently set
  (Sep 2026).** Reported 26 Sep 2026: a non-teaching event couldn't be booked
  into a slot a cancelled lesson had freed, even though a regular lesson
  could be booked into the same slot. The freed-slot clash detection itself
  was never the problem — it doesn't distinguish a non-teaching event from
  any other lesson. The actual cause: Add Lesson has separate Day and Start
  date fields, and nothing kept them in sync. Booking a real replacement
  lesson into a freed slot was normally done via **Clone**, which always
  derives the day from the date chosen, so it never hit this. Booking a
  non-teaching event has to go through Add Lesson instead (Clone has no
  blank non-teaching option), and Day defaults to whatever the form was
  last left showing — e.g. still Wednesday after the grid had moved on to
  Thursday — while Start date resets to today. `plannedDates()` trusts Day
  over the typed date and walks forward to the next date that matches it,
  so the one-off silently landed on, and clashed on, a different date than
  the one actually chosen. Fixed by deriving Day from Start date automatically
  whenever "One-off lesson" is selected (`syncDayFromStartDate()` in
  `lessons.html`), re-deriving it if the date is then changed, disabling the
  Day dropdown while a one-off is selected (it isn't independently
  meaningful any more), and defaulting Day to match Start date's weekday
  every time Add Lesson opens fresh, closing the same gap for a brand-new
  series too. Editing an existing one-off is untouched — it already loads
  the real day from the lesson record, not from this derivation.
- **Freed-slot clash detection now fetches only the new booking's own date
  window, not an overlapping lesson's entire history (Sep 2026).** Reported
  30 Sep 2026: a one-off trial couldn't be booked into a slot a lesson's
  occurrence had freed by being marked Absent — No Credit, even though the
  freed-slot logic itself (an occurrence where every student in the roster
  has an Absent/Teacher Cancelled mark doesn't block a new booking) is
  correct and unchanged. `saveLesson()`'s clash check used to fetch every
  occurrence — past and future, three years of them for an indefinite
  series — for every lesson sharing that weekly time slot, with no date
  filter at all, then work out which were freed in JS. An indefinite series
  is ~150 occurrences a year; multiply that by every teacher who happens to
  have a lesson at the same time of day, and the fetch can run past
  Supabase's default 1000-row response cap, which truncates silently rather
  than erroring — so the exact occurrence that mattered could simply not
  come back. `checkCloneClash()` never had this problem, since a clone is
  always for one specific date and already queried only that date. Fixed by
  bounding `saveLesson()`'s occurrence fetch to the new booking's planned
  dates (a single date for a one-off; the same date-range logic scales down
  naturally for a bounded series) — `lesson_occurrences.select(...).gte(
  'date', ...).lte('date', ...)` alongside the existing `.in('lesson_id',
  overlappingIds)`, rather than every date the lesson has ever had.
- **Online lessons get a violet camera badge, not a colour change (Sep
  2026).** `is_online` used to be invisible on the Daily grid and Monthly
  view entirely — the only place it showed at all was a small "Online" text
  pill on the Weekly list. Admins asked for it to be obvious at a glance
  everywhere. The private/group/makeup border colour on a lesson block
  already carries real meaning, so rather than repurposing or fighting that
  colour coding, online lessons get an additional small violet circular
  badge (a camera icon, `onlineIconBadge()` in `lessons.html`) — top-right
  corner on the Daily grid block, next to the time on a Monthly tile, and
  as an icon inside the existing pill on the Weekly list. Same violet
  (`#7c3aed`) as the pre-existing `.pill-online` elsewhere in the app, so
  it reads as one consistent "online" signal across every view and the
  occurrence modal.

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

### Never write policies blind — measure first

Two attempts at securing the views failed by guessing at what was needed. The
method that worked: impersonate each role, count what they can read, and add a
policy only where the count is zero.

```sql
BEGIN;
  SET LOCAL role TO authenticated;
  SET LOCAL request.jwt.claims TO '{"sub":"<user-id>","role":"authenticated"}';
  SELECT 'lessons' AS t, COUNT(*) FROM lessons
  UNION ALL SELECT 'lesson_occurrences', COUNT(*) FROM lesson_occurrences
  -- …every table the view touches
ROLLBACK;
```

Both views inner-join `lessons`, `teachers`, `profiles` and `studios`, so a
single zero on any of those empties the entire view. Measuring first showed
students were missing four policies and that teachers and admins needed none —
against nine written on a guess, which locked everyone out of the portal.

### A policy on a table cannot read that table

`get_my_role()` reads `profiles`. A policy on `profiles` that calls it is
circular: login can't load a profile, and the portal reports "Account not fully
set up".

The same in two hops is just as fatal — a policy on `lessons` that subqueries
`lesson_students`, whose own policy subqueries `lessons`, gives
`42P17: infinite recursion detected in policy`.

**The fix is `SECURITY DEFINER`.** Such a function reads without RLS applying,
so no cycle can form. `get_my_role()`, `get_my_teacher_id()`,
`get_my_studio_ids()` and `my_lesson_ids()` all exist for this reason. Any new
policy needing a relationship lookup should use one, not an inline subquery.

### Studio access is a default, not a boundary

Admins see and work on every studio. Their pages simply *default* the studio
filter to their own, so the day starts with their own work and the other studio
is one dropdown away.

This replaced database-level scoping, which was the wrong tool. Being a `FOR
ALL` policy it restricted writing as well as reading, and the failures surfaced
as opaque `42501` errors rather than clear refusals. Three bugs came from it in
two days — an invisible task that made an enquiry report "Needs a task", a task
silently losing its subject when edited by an admin who couldn't see that
student, and a student creation that inserted fine and then failed on the
read-back.

The lesson worth keeping: **scoping in the database enforces a boundary;
scoping in the interface expresses a preference.** The admins wanted a
preference, and said so once asked directly.

`applyDefaultStudio()` in `supabase-client.js` does it, and only where an admin
covers exactly one studio.

### Historical note: studio scoping restricted writing, not just reading

`admins_manage_students_in_their_studios` is a `FOR ALL` policy, so its
`USING` clause governs reads *and* the read-back after a write. A request with
`Prefer: return=representation` — which supabase-js sends whenever `.select()`
follows an insert — therefore fails with `42501` when an admin creates a
student at another studio: the insert succeeds, the read-back is denied, and
the error names row-level security rather than the actual problem.

`students.html` blocks this case with a plain message. The workaround is to
create the student at your own studio and move them across, which carries
their tasks over.

**Decided:** creating for another studio stays forbidden. It is rare, and
admins can hand it over between themselves.

### A student may have no login of their own

Around 5% of students are siblings sharing one family email address, and
`auth.users.email` must be unique — so a login each is impossible.

Email is therefore optional. A student without one gets no auth account and
exists as a record only, exactly like the bulk-imported students; notifications
reach them through `parent_email`. `students.user_id` is not unique, so several
students can share one profile — that is how a family login works.

The student dashboard shows a child switcher when the login owns more than one
student, and one child at a time: practice notes and attendance are per child,
and combining them invites reading the wrong child's feedback. A single child
sees no switcher.

**Creating a student is not atomic.** The auth account is made first, then the
profile, then the student row. A failure partway used to leave an auth account
holding the email address with no student attached — invisible in the portal,
and the next attempt failed with "already used" for a student nobody could
find. Both later steps now roll the account back. If this recurs, look for
orphans:

```sql
SELECT u.id, u.email, u.created_at
  FROM auth.users u
 WHERE NOT EXISTS (SELECT 1 FROM students s WHERE s.user_id = u.id)
   AND NOT EXISTS (SELECT 1 FROM admins  a WHERE a.user_id = u.id)
   AND NOT EXISTS (SELECT 1 FROM teachers t WHERE t.user_id = u.id);
```

### Substitute teachers

A substitution belongs to one **occurrence**, not the series — the following
week reverts on its own. Two cases:

- **Staff cover.** `lesson_occurrences.substitute_teacher_id` points at another
  teacher. `schedule_view.teacher_id` is `COALESCE(substitute, usual)`, so the
  lesson genuinely moves into the substitute's schedule and leaves the usual
  teacher's. They see the students, the notes including earlier weeks, and can
  mark attendance — `phase5-substitute-access.sql` grants that explicitly
  rather than leaving it to chance.
- **External cover.** `substitute_name` is just text. The person has no account,
  so the lesson stays with the usual teacher and an admin marks the attendance
  they report.

Admins can mark attendance from the occurrence modal in either case;
`marked_by` records who did it, which is the whole audit trail.

**Rebuilding either view resets `security_invoker`.** Any migration that
recreates them must set it again, or the Supabase lint silently reopens.

### Three views, one modal, three different shapes

`lessons.html` has daily, weekly and monthly views built at different times, and
each populated `allOccurrences` differently while sharing one occurrence modal:

- the **weekly** view merged student lists into copies held for rendering, so
  the modal — reading `allOccurrences` — found no students and could not mark
  attendance
- the **monthly** view reads `schedule_view`, so its occurrences were never in
  `allOccurrences` at all, and called an `openOccurrence()` that did not exist
- neither grid query fetched the substitute columns, so a covered lesson looked
  ordinary

If a fourth view is ever added, it must attach `lessonStudents` to
`allOccurrences` itself, not to a copy.

**A slot can hold more than one lesson.** Cancelling frees a slot for
rebooking, so the daily grid may need to show a cancelled lesson and its
replacement together — `.find()` showed whichever came back first.

Occurrences that overlap in time (a real double-booking, or a cancelled
lesson sharing its old start time with whatever replaced it) are grouped
into one clustering pass per teacher, so the render loop only ever emits one
`<td>` per teacher per row no matter how messy the underlying booking is —
letting each overlapping occurrence get its own `<td>` was what pushed a
different, unrelated teacher's lesson block sideways out of the grid
(reported 14 Sep 2026).

Inside that one cell, each occurrence is drawn at its own true start time
and duration — absolutely positioned within the cell (`top`/`height` scaled
from its real start/duration, not from reading order) and given its own
side-by-side column when it genuinely overlaps another occurrence, via a
plain interval-graph greedy column assignment (walk occurrences in
start-time order, give each the first column whose last occupant already
ended). Earlier this just stacked whichever occurrences shared the slot in
a flex column, live first — which meant a 60-minute lesson that replaced a
cancelled 30-minute one at the same start time visually read as if it only
ran the second half hour, because nothing in the display reflected where
each occurrence actually sat in time (reported 28 Sep 2026). A cluster with
only cancelled occurrences and nothing live still uses the old simple
stacked list — there's no real duration being misrepresented when nothing
is actually on.

### A guard that returns quietly turns a bug into a non-event

Three failures in one afternoon, all from a correct check failing silently:

- `applyDefaultStudio` returned early when the dropdown had no matching
  option — because it was called *before* the options were added. Both admins
  saw every studio while the control said otherwise.
- The same helper returned early when an admin appeared to cover several
  studios, which happened because `tasks.html` queried `admins` without
  selecting `studio_ids`.
- `loadWeeklyView` threw part-way and left the spinner turning for ever, with
  the error only in the console.

The checks were right in each case; the silence is what cost the time. The
helper now logs why it did nothing, and `loadView()` shows a failure with a
retry button rather than spinning.

### Filtering on a joined column gives a LEFT join

`.eq('lessons.studio_id', x)` does not exclude non-matching rows — it returns
them with `lessons: null`. The weekly view passed those through and the
renderer threw on the first one. Anything filtering on a joined column must
also drop rows where the join came back null.

The daily and monthly views use `schedule_view` and were unaffected. The weekly
view is the only one still joining directly, and moving it to the view would
remove this class of problem.

### Reloading a list must reapply its filter

`loadStudents()` rendered the full list directly, so any reload discarded the
active filter — a student moved to another studio reappeared until the page was
refreshed by hand. Reload paths should go through the filter function, never
render the raw array.

### Tightening scope can silently clear data

Any `<select>` populated from a scoped query drops values the current user
cannot see. The control then reads empty, and saving writes that absence as a
deliberate change.

Studio-scoping students did exactly this: a Kilsyth admin opened a task about a
Ringwood prospective student, the subject dropdown had no matching option, and
saving set `subject_type` and `subject_id` to null. The task survived; its link
to the student did not, and the Enquiries page then correctly reported "Needs a
task" for an enquiry whose task existed but pointed at nobody.

`tasks.html` now keeps the original subject when it wasn't among the options,
and shows it as "Student at another studio". **Check every dropdown with the
same shape before tightening scope anywhere else** — the assignee and studio
pickers have it too.

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

### A plain subquery inside a policy pays for every policy on the table it reads

(Sep 2026.) Teachers started getting `57014 canceling statement due to
statement timeout` when marking attendance — but only some teachers, and only
sometimes, which made it look like a permissions bug or a one-off network
blip at first. `EXPLAIN (ANALYZE, BUFFERS)`, run impersonating the affected
teacher (see above), showed the real shape of it:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT lo.id FROM lesson_occurrences lo
JOIN lessons l ON l.id = lo.lesson_id
WHERE l.teacher_id = get_my_teacher_id();
-- Execution Time: 1333.264 ms, Buffers: shared hit=23999
```

That's the subquery the old `"Teacher marks attendance for own lessons"`
policy used to check ownership — a correctness rule identical to the section
above (*"A policy that subqueries another RLS-protected table inherits that
table's visibility"*), except here it degraded performance rather than
correctness. `lesson_occurrences` carries five permissive SELECT policies
(teacher-own, teacher-covering-as-substitute, student, admin, plus one more).
None of that is specific to attendance — but because the subquery reads
`lesson_occurrences` under ordinary RLS, Postgres evaluates all five, per row,
for every occurrence the teacher has ever had. For a teacher with a long
private-student history that's thousands of rows and a second-plus, even
though the actual answer only needed one column off one indexed lookup.

**The fix, same pattern as `SECURITY DEFINER` above:** move the join into a
`STABLE SECURITY DEFINER` function (`my_owned_occurrence_ids()`, alongside the
already-existing `my_covered_occurrence_ids()` for substitutes and
`my_lesson_ids()` for students) so it reads the underlying tables without RLS
re-applying. Same access, no five-policy fan-out — the identical impersonated
`EXPLAIN` dropped from 1333ms to sub-millisecond. See
`attendance-owner-check-perf-fix.sql`.

**The general lesson:** any policy subquery — not just ones that look
recursive — inherits the *full* RLS cost of every table it touches, including
policies that have nothing to do with the check being written. If a table has
more than one or two permissive policies, a plain subquery into it from
another policy is a latent performance trap, not just a latent correctness
one. Prefer a `SECURITY DEFINER` helper by default for any RLS check that
reads a second table, even when there's no recursion risk forcing the issue.

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

**Quick-add opens the Task modal straight away (Sep 2026).** `quickAddTask()`
(the "What needs doing?" bar, admin/superuser only) used to just insert the row
and refresh the list — a title-only task with no due date, assignee, subject or
kind, that then had to be found again among every other task before any of that
could be set. Reported 28 Sep 2026. It now `.select('id').single()`s the insert,
reloads `tasks` (`openTaskModal()` reads from that array, so the reload has to
come first), and opens straight into the Task modal on the new row, already
editable.

### Enquiries

**An enquiry is a student record with status `prospective`.** No auth account —
they cannot log in, and `profiles.id` has no foreign key to `auth.users`, which
is what allows this. Same mechanism as the Zoho import.

**Every enquiry gets a follow-up task**, due on the enquiry date. This is not
optional. An enquiry with no task is a sticky note: nothing surfaces it, nobody
is prompted, and it sits there forever. Several designs were removed for
recreating exactly that.

**There are three exits, and they mean different things:**

| Action | Meaning |
|---|---|
| Discard as spam | Never a real enquiry. Deletes the record, its instruments, its profile and all its tasks |
| Close task → Not proceeding | A real person who didn't convert. Becomes `lapsed`, kept as history |
| Close task → Trial / Enrolling | Converted. Becomes `trial` or `active` and moves to Students |

**Closing a follow-up task means the enquiry is settled.** If it isn't settled,
the task stays open with a later due date. There is deliberately no "close it but
leave the enquiry open" — that strands the enquiry.

**Cancel is blocked on enquiry follow-ups** for the same reason. Cancel means "this
never needed doing", which cannot apply to an enquiry: every enquiry needs
chasing. The button is hidden, and refuses if reached another way.

**Converted enquiries stay on the Enquiries page** under the Converted filter.
Without that the page would only ever show failures and work in progress, and
there would be no way to see the conversion rate.

**Returning people send a fresh enquiry** rather than reviving an old one, and it
is usually a past *student* rather than a lapsed enquiry. Opening an enquiry
therefore checks for a match on email, phone or exact name and shows an amber
banner if it finds one. It flags; it does not merge — the admin judges.

**Prospective and lapsed are excluded** from the Students page, from notification
recipients, and from the task subject picker (though lapsed students still
resolve there, so their closed tasks don't show "(unknown)").

### Enrolment processes

**Three fixed checklists** — trial confirmation, ongoing enrolment, end
enrolment — each an instance attached to a student, with the item labels
copied in at creation so changing a checklist later doesn't rewrite what an
admin ticked months ago.

**Automatic items are evaluated live, never stored.** "Trial lesson added"
becomes true after the process starts, so a stored value would be wrong from
the moment it was written.

**Every automatic check is scoped to the process, not the student.** This is
the single mistake that recurred most often during the build — asking "does a
lesson exist" when the question is "does a lesson exist *for this*". It
surfaced four separate times:

- a trial student's lesson satisfied the *enrolment* checklist
- an active student trying a second instrument satisfied a new *trial*
  checklist on day one
- an enrolment confirmation email described the trial lesson
- a returning student's task due dates came from their previous enrolment

The scoping is now consistent: `lessons.created_at >= process.started_at`,
future occurrences only, and a series means more than one occurrence. Anything
new in this area should follow the same rule.

**`can_defer` marks the items worth turning into a task** — Xero and eWay,
where a genuine blockage can occur. Everything else is tick-and-move-on;
raising a task for "explained the policies" is heavier than the work.
Previously an admin would tick eWay dishonestly and track the real work
elsewhere, losing the only thing the checklist records.

**A deferred item clears when its task is done**, computed from the task's
status rather than stored, so it cannot drift.

**Completing the end-enrolment checklist sets the student inactive.** There is
no Deactivate button — it set a status and left the lessons running, so a
"deactivated" student still appeared on their teacher's schedule. Ending an
enrolment is a process, not a flag.

**Closing an "End enrolment — [name]" task is what starts the checklist**,
in `tasks.html`'s `setStatus()` — not `planEndEnrolment()` itself, which only
creates that task, due whenever the admin says the enrolment should end. The
task's title prefix and the student's current `active` status are how
`setStatus()` recognises it; closing it pops a `confirm()` ("Start the
end-enrolment checklist? This sends the farewell email.") before calling
`startProcess()`, since the farewell email goes out immediately at that
point — not once the checklist is later completed. Declining that confirm
leaves the task open rather than completing it: it used to fall through to
the ordinary "mark done" path, so declining silently ticked the task with no
checklist ever started and no email sent — indistinguishable, later, from
never having closed it at all. Reported 30 Sep 2026: an admin testing the
flow clicked past the popup and the task just showed as done.

**Nothing with history gets deleted.** Student and teacher deletion were both
removed — they were built as ordinary CRUD in Phase 2, before the lifecycle
existed, and by the time it did they were stale as well as destructive. Student
deletion removed lessons via the legacy `lessons.student_id` column, so it
deleted the profile and auth account while leaving orphaned `lesson_students`
rows; teacher deletion never touched `lessons` at all.

Deactivate is the answer in both cases: the record survives, past lessons stay
attributed, and they can come back. Delete remains only on Studios and Admins,
where it is Super User only and genuinely rare.

**Students and enquiries are studio-scoped**, matching tasks. An admin sees only
their own studios' students; a student with no studio stays visible to everyone.
The `WITH CHECK` is role-only, so a student can be handed *out* to another studio
but not pulled in — the same asymmetry as tasks.

Changing a student's studio hands them over: a trigger moves their open tasks to
the receiving studio's queue, unassigned, with a handover record explaining why.
Enquiries have a **Move studio** button for this; moving an enquiry's follow-up
task offers to move the enquiry too, since they are the same piece of work.

**Known gap: lessons are not studio-scoped.** Only students and tasks are.

**An indefinite lesson series runs three years ahead of today**, not from
whenever it began. Generating 52 weeks from the start date meant a migrated
student whose lessons began in early 2025 got occurrences that had all already
happened — their lesson appeared in no view at all, and could not be fixed
through the portal. `INDEFINITE_YEARS` in `lessons.html` controls the horizon.
Nothing tops series up as time passes, so that horizon is a real deadline.

After any bulk import, check for series that are already exhausted:

```sql
SELECT l.id, l.instrument, MAX(o.date) AS last_occurrence
  FROM lessons l JOIN lesson_occurrences o ON o.lesson_id = l.id
 WHERE l.status = 'active'
 GROUP BY l.id, l.instrument
HAVING MAX(o.date) < CURRENT_DATE;
```

**Known gap:** deleting a studio does not check for live lessons. It cleans up
teacher references and availability, but a studio with a running schedule would
leave those lessons pointing at nothing. Worth a guard before a fourth studio
exists.

**Ending lessons cancels, never deletes.** Occurrences up to the last-lesson
date are kept, everything after is cancelled. The slot frees for rebooking
either way, but attendance and notes survive.

### Confirmation and lifecycle emails

Six templates, all in `portal/js/processes.js`, matching the wording
Pathfinder already used so nothing changes for the student:

| Email | Trigger |
|---|---|
| Thanks for getting in touch | Enquiry created |
| Your trial is booked | Trial lesson added |
| You're enrolled | Lesson series added |
| We're just checking in | Closing the check-in task |
| Payment problem | Closing a finance follow-up task |
| Farewell for now | End enrolment started |

**The policy text is verbatim from the studio's own templates** — four weeks'
notice, a recorded video lesson as the default for a missed lesson, school and
public holiday rules, photography. An earlier drafted version had two of these
materially wrong. Do not paraphrase it.

**"You're enrolled" carries a Portal how-to guide link (Sep 2026).** After
the policies and before the sign-off, this email now has a "PORTAL HOW-TO
GUIDE" section pointing to `STUDENT_GUIDE_URL`
(`.../portal/manuals/student-guide.html`) — added specifically for new
students, since the How-To Guide's role gate (see "How-To Guide" below) means
the guide can no longer be handed out as a bare link to someone without an
account yet. The link isn't deep — signing in from it lands on the student's
dashboard, not the guide itself, because `requireAuth()` has no return-path
support — but a student who isn't logged in yet simply sees the login page,
and once their account exists they can always reach the guide from there or
the Portal sidebar. This only touches the enrolment email; "Your trial is
booked" is unchanged, since a trial student doesn't have Portal access yet
either way.

**Confirmations send when the lesson is added**, not at conversion — that is
when the details they carry come into existence. `process_items.sent_at`
guards against sending twice.

**The email body format:** a paragraph wrapped in `**asterisks**` becomes a
callout block and may span blank lines; `**bold**` works inline, including
inside a callout; a line of `---` becomes a section rule; a short ALL-CAPS line
becomes an orange heading.

**The log is one timeline.** Notes and handovers are merged and sorted together.
Handover records were written from the start but had nothing displaying them for
several days, so a task could change hands with nothing in the thread explaining
it.

**Buckets and the status filter used to fight.** The bucket filter ran first and
forced open-only, so choosing Done returned nothing. They now cooperate: picking
a date bucket resets the status filter, and vice versa.

## Skill grading (Tier/Grade) — universal, but the artefact library stays Guitar-only

Two separate things share the word "grading" and are easy to conflate:

- **`bok_grade_levels` / `student_grade_milestones` / `student_current_grades`**
  — the Tier/Grade ladder (Foundation → Grade 0, Beginner → Grades 1-3,
  Intermediate → Grades 4-6, Advanced → Grades 7-8). These tables were
  always instrument-agnostic; nothing about their schema is Guitar-specific.
  `student_current_grades` is a view returning each student's latest
  `achieved_on` grade per instrument. `student_grade_milestones` is
  history-preserving — always INSERT, never UPDATE, so a student's grading
  history stays intact even as they progress.
- **`bok_artefacts`** — the Body of Knowledge content library (exercises,
  pieces, resources tied to a grade level). This one genuinely *is*
  Guitar-only content and stays that way deliberately — it isn't gated by
  the same instrument list, and generalising it would mean writing a whole
  curriculum for ten more instruments, not a code change.

**What changed (Sep 2026):** the Tier/Grade ladder itself was extended from
Guitar-only to all instruments. It needed no schema change — `bok_grade_levels`
already had no Guitar-specific column — only widening the UI-layer
`GRADED_INSTRUMENTS` gate from `['Guitar']` to the full instrument list, in
five files: `dashboard-student.html`, `dashboard-teacher.html`,
`my-students.html`, `teacher-detail.html` (aliased to `INSTRUMENTS` in
`students.html`, which uses the same canonical array as everywhere else).
`my-students.html` and `students.html` also now print `Instrument (Tier — Grade)`
next to the instrument name wherever it was previously shown bare.

`GRADED_INSTRUMENTS` is kept as an **explicit list, not "always graded."**
An unrecognised or mistyped instrument string (most likely from a CSV import)
falls back to the old `student_instruments.skill_level` 0-8 bar instead of
silently showing "Not yet graded" for something that was never meant to be
tracked this way. `skill_level` stays in the DB untouched and un-migrated —
it's just no longer displayed once a grade milestone exists for that
student/instrument, the same non-destructive pattern used for Guitar from
the start. `skillBandColour()` in `supabase-client.js` gives the fallback bar
the same colour banding the grade pill already used.

**How it was found:** teachers noticed only Guitar students showed a grade
(e.g. "Beginner — Grade 2") on the teacher dashboard's My Schedule view,
because `attachCurrentGrades()` in `dashboard-teacher.html` only computed
`currentGrade` for instruments in `GRADED_INSTRUMENTS`, which was still
`['Guitar']` at the time — everyone else silently got nothing rather than
falling back to the skill bar. That was the first fix; widening
`GRADED_INSTRUMENTS` everywhere else followed the same day once the pattern
was confirmed.

### Grade animal names (Sep 2026) — a cosmetic overlay, not a data model change

Admins wanted each instrument's 9 grade levels to have a fun nickname —
young students respond a lot better to "you're a Hawk now!" than "you're
Intermediate Grade 5" — the same idea as swimming badges (tadpole → shark
→ marlin). Guitar's names were the pilot; Bass, Drums, Piano / Keyboard,
Violin, Voice / Singing, Ukulele and Saxophone followed once the theme
was approved. Music Theory, Band and Other were deliberately left out —
they're catch-alls rather than one real instrument, and nobody asked for
a theme for them.

The names are **not stored in the database.** `bok_grade_levels` stays the
single generic 9-row reference scale it always was — Foundation/Beginner/
Intermediate/Advanced × Grade 0-8 — shared by every instrument, per the
section above. The animal names are a pure display-layer lookup, keyed by
instrument then by `sort_order` (0-8), in one constant:
`BOK_GRADE_ANIMAL_NAMES` in `js/supabase-client.js`. This was a deliberate
choice over a new `instrument × grade_level` table: nobody asked for these
to be admin-editable through the UI, so a table would mean a migration,
RLS policies, seeding, and a fetch on every page that shows a grade, for
content that only changes when someone asks Claude to change it. A plain
JS map is one file to edit either way.

Three helpers, all in `js/supabase-client.js`, all instruments funnel
through:

- `gradeAnimalName(instrument, sortOrder)` — the bare nickname, or `''`
  for an instrument with no theme (or an out-of-range level).
- `gradeLabel(gradeLevel, instrument)` — the display string every screen
  actually renders: the existing `"Tier — Grade N"`, with `" (Animal
  Name)"` appended when the instrument has a theme. This is additive by
  design — admins explicitly asked to keep the Tier/Grade label and
  extend it, not replace it. `gradeLevel` needs `{tier, label,
  sort_order}`; passed only `{tier, label}` (a query that forgot to
  select `sort_order`) it just never shows an animal name rather than
  throwing.
- `gradeOptionsHtml(gradeLevels, instrument, selectedId)` — builds a
  Grade `<select>`'s `<option>` list via `gradeLabel()`. Every grade
  dropdown in the Portal (the student edit form, "record grade" on My
  Students, the BoK library's Add/Edit Artefact form) now calls this
  instead of inlining its own `${g.tier} — ${g.label}` map, so a future
  instrument added to the theme doesn't need updating in five places.

Every `student_current_grades` query that feeds a `gradeLabel()` call had
to add `sort_order` to its `.select()` — the view already exposed it, but
most call sites had only ever selected `tier,label` since nothing before
this needed `sort_order` client-side. `bok_grade_levels` queries were
already `select('*')` everywhere, so those needed no change.

**One exception:** `bok-artefacts.html`'s grade *filter* (as opposed to
its Add/Edit form's grade field) spans every instrument in the library at
once, so it stays on the plain label — one dropdown option can't carry an
animal name for ten different instruments simultaneously. The Add/Edit
form's own Grade field, by contrast, always belongs to whichever
instrument is picked right next to it, so it rebuilds its options via
`onArtefactInstrumentChange()` whenever that instrument changes, and
prefills correctly for both "Add" (defaults to Guitar) and "Edit" (the
artefact's own instrument) when the modal opens.

**Adding a themed instrument later, or changing one of these names,** is
a one-file edit: extend `BOK_GRADE_ANIMAL_NAMES` in
`js/supabase-client.js` with a 9-entry array keyed by the exact instrument
string used in `INSTRUMENTS`. No migration, no seeding, nothing to run in
Supabase — the change takes effect everywhere the next time the page
loads.

## Distribution lists (Sep 2026) — Gmail Bcc, not another sending path

Admins asked for a way to reach students via their own Gmail rather than
Notifications, specifically when they expect replies or need to attach a
file — Notifications is one-way (no reply-to thread) and can't attach
anything. Rather than build file attachments and threaded replies into the
portal's own sender, `distribution-lists.html` (Reports → Distribution
Lists) generates a **Bcc-ready comma-separated address list** for an admin
to copy into a normal Gmail compose window. The portal never sends these —
it only resolves who should be on the list, live, at the moment someone
asks for it.

Four lists, matching what was actually asked for:
1. All active students, all studios (deliberately active-only, not trial —
   the one list where that was explicit)
2. Per studio
3. Per teacher
4. Per instrument — the one genuinely new server-side capability; lists 1-3
   reuse `send-email.js` recipient modes that already existed for
   Notifications (`studios`, `teacher`), plus a new `all` mode

**Backend:** all four go through `send-email.js`'s existing `action:
'preview'` — the same server-side recipient resolution Notifications' own
preview panel uses (service_role, because student login email lives in
`auth.users` and the browser can't read that table) — with a new
`body.full: true` flag that returns the complete recipient list instead of
preview's normal 8-item sample. Two new recipient modes were added:
`all` (every active student, no studio scoping) and `instrument` (active +
trial students of one instrument, mirroring the `teacher` mode's shape).
Which statuses count as "in audience" is now a per-mode `desiredStatuses`
array rather than one hardcoded active+trial filter, specifically so `all`
could be active-only without changing every other mode's behaviour.

**One address per student, deliberately different from Notifications.**
A targeted notification already mails every valid address it can find for
a student (login email AND parent email, if both are on file and distinct)
— more reach for a message going to one family. A distribution list uses
only the highest-priority one (`recipients[i].addresses[0]`, following the
existing login → student email → parent email order) — one address per
student in the count, no near-duplicate sends to the same family, smaller
lists that stay further under Gmail's recipient cap.

**Paste into Bcc, never To/Cc.** The page says so directly, and the reason
matters: pasting a class list into To exposes every family's email address
to every other family, and turns a "reply" into a reply-all blast — the
opposite of what admins asked this for (threads they can actually manage).
Convention is: admin's own studio address in To, the generated list in Bcc.

**Gmail's recipient cap is real and was checked, not assumed:** a personal
Gmail account caps at 500 combined recipients (To+Cc+Bcc) per message
([Google's support page](https://support.google.com/mail/answer/22839));
Google Workspace raises the combined cap to 2,000 but caps *external*
recipients specifically at 500 per message
([Workspace sending limits](https://knowledge.workspace.google.com/admin/gmail/gmail-sending-limits-in-google-workspace))
— and every address on one of these lists is external, so 500 is the
number that actually applies regardless of which kind of account is
sending. The page shows a live count and warns above ~450; if a studio
ever approaches 500 active students, the "all students" list will need
splitting into two sends, which isn't automated — it's just a warning.

## Day Sheet (Sep 2026) — a Google Form embedded, not a portal feature

`day-sheet.html` is a new "Front desk" nav item, admin/superuser only
(`requireAuth(['superuser','admin'])`, same as Tasks/Enquiries/Notifications).
It has no Supabase involvement at all — no table, no query, no RLS. The page
is just a static iframe embed of the studio's existing Google Form
(`?embedded=true` appended to the form's `viewform` URL, the officially
supported way to embed one), plus an "Open in a new tab" link as a fallback
in case the iframe gets clipped or a browser blocks the frame.

The iframe height is a fixed guess (2200px) since there's no reliable way to
auto-size a cross-origin iframe to its content without the embedded page
cooperating, which a Google Form doesn't. If the form is edited and grows or
shrinks a lot, adjust `.form-embed-wrap iframe { height: ... }` in
`day-sheet.html` by eye.

**The nav link had to be added in two different ways.** Most pages build the
sidebar as static inline HTML (copy-pasted per page — see `INSTRUMENTS`
duplication elsewhere in this file for the same pattern's downside); `tasks.html`
and `enquiries.html` instead render it from a small `item()`/`it()` helper
and an `ICONS`/`I` lookup object. Adding "Day Sheet" meant touching both
shapes — 11 files got a pasted `<a class="nav-item">` block, 2 got a new
icon-object entry plus one `item(...)` call. Any future nav item needs both.

## Lesson credits (Sep 2026) — a ledger, not a counter

A per-student record of lesson credits: a student banks one when a lesson
doesn't happen through no fault of their own, and spends one booking a
makeup. Requested piecemeal by the admins, one decision at a time — the
answers baked into this build:

- **1 credit = 1 missed lesson**, flat, regardless of duration or
  private/group. No value-weighting.
- **Only a single-date cancellation prompts for a credit.** "Cancel this and
  all future" or "cancel the series" are for stopping lessons altogether
  (a student leaving, say) — they don't touch attendance or credits.
- **A makeup is always for one student**, even when cloned from a group
  lesson's roster. The other students on the clone aren't touched.
- **Admin/superuser visibility only**, for now — no student/parent-facing
  balance anywhere yet.

`portal/supabase/lesson-credits.sql` adds `lesson_credit_movements` — an
append-only ledger (`student_id`, `delta`, `reason`, `note`, `occurrence_id`,
`initiated_by`, `initiated_by_role`, `created_at`), deliberately **not** a
running balance column on `students`. A balance is `SUM(delta)` for a
student, exposed as the `student_credit_balances` view (balance, last
movement date, last movement note/reason) — the same "compute state from
history" approach `schedule_view`'s `fully_marked` already uses, rather than
a cached counter that can drift from the events that produced it. There is
**no UPDATE/DELETE policy** on the ledger, on purpose: a mistaken credit is
corrected with an offsetting `manual_adjustment` row, never by editing or
deleting the original.

`my_teaching_student_ids()` (SECURITY DEFINER STABLE, same pattern as
`my_owned_occurrence_ids()` and `my_covered_student_ids()`) is what a
teacher's RLS policies check against — their own roster merged with
anything they're covering as a substitute. A teacher can read and log
movements only for those students; admin/superuser can do both for anyone.

**Three trigger points**, all sharing one `offerCreditMovements()` helper
(duplicated once per file — `lessons.html` and `dashboard-teacher.html`
don't share a JS module) that shows a single native `prompt()` covering
every affected student at once, doubling as the note field — clearing the
text and pressing Cancel skips logging anything:

1. **Cancelling a single occurrence** (`cancelOccurrence('single')` in
   `lessons.html`) now also writes a `teacher_cancelled` attendance row per
   roster student (matching what marking a whole group "Teacher Cancelled"
   already does), then offers the credit.
2. **Per-student attendance marking** — admin's dropdown
   (`markAttendanceAsAdmin`), the teacher's single-lesson dropdown
   (`markAttendance`), and the teacher's group-attendance modal
   (`saveGroupAttendance`) — offers the credit whenever a student's status
   is newly set (an actual change, not a re-save of the same value) to
   `absent_notice` or `teacher_cancelled`. Correcting a status away from one
   of these later does **not** auto-reverse the credit — that's a case for
   a manual adjustment, not a silent behind-the-scenes reversal.
3. **Booking a makeup** — there are four separate places a lesson gets
   flagged `is_makeup`, and all four now carry the same gate:
   - The "Clone occurrence" modal's "Book as a makeup for [student]"
     picker, showing each roster student's live balance.
   - **Add Lesson**, choosing pattern "One-off" and kind "Makeup lesson" —
     a completely separate creation path from Clone that used to just set
     `is_makeup` with no credit involved at all (a gap the admins caught
     by asking "will this work the same way?" — it didn't, until this).
     Gained the same "Consume a lesson credit from [student]" picker,
     shown only for that kind.
   - **Edit lesson**, changing an existing one-off's kind to "Makeup" —
     same picker, same gate.
   - **The occurrence modal's own "This is a makeup lesson" checkbox** —
     opened by clicking directly on a lesson block on the schedule,
     distinct from "Edit lesson"/"Edit series". This one had zero credit
     awareness at all until an admin found it by testing: an ad-hoc
     one-off booked via Add Lesson, then flagged as a makeup here instead
     of through Edit lesson, spent no credit and showed no picker (2 Oct
     2026). Gained the same "Consume a lesson credit from [student]"
     picker, shown only when the checkbox is newly ticked.

   All four block the save at a zero balance, and all four spend the
   credit only once: a dataset flag named `wasMakeup` — on `lessonModal`
   for Add/Edit lesson (set by `editSeriesInner()` when opening an
   already-makeup lesson to edit), and on `occurrenceModal` for the
   checkbox (set by `openOccurrenceModal()` from the occurrence's current
   `is_makeup`) — is what stops re-saving one, moving its time or adding a
   note, say, from silently charging a second credit. Only Clone links to
   an *existing* roster the way a real makeup does; the other three pick
   the credited student from whoever is already on the lesson/occurrence,
   since they build or already show their own roster independently of any
   cancelled lesson. None of the four auto-refunds a credit if the
   checkbox or kind is later un-ticked — that's a manual adjustment, same
   as correcting an attendance status (point 2, above).

`credits.html` is the on-demand report (Reports section, admin/superuser
only, same `requireAuth` as Attendance): students with a non-zero balance
by default, a "show all" toggle, a click-through history modal per student,
and a manual "+ Add adjustment" action for anything outside the three
triggers above. Its nav link went into all 14 other admin-facing pages the
same two ways Day Sheet's did — pasted `<a class="nav-item">` in the 12
static-sidebar files, plus an `ICONS`/`I` entry and one more `item()`/`it()`
call in `tasks.html` and `enquiries.html`.

**Known gap, flagged rather than silently patched over:** makeup booking via
"Clone" has never been structurally linked to the occurrence it replaces —
it's a fresh one-off lesson with a note in `series_notes` ("Cloned from
..."), same as before this feature. The credit ledger's `occurrence_id`
records the *new* occurrence a credit was spent on, not a formal link back
to whichever cancellation banked it in the first place. Good enough for the
report as specified; revisit if the two ever need to be queried together.

## How-To Guide (Sep 2026) — documentation for the parallel run with Zoho/MMS

The Portal is being trialled **alongside** the existing setup — the public
website, Zoho CRM (enquiries/tasks) and MyMusicStaff (students/lessons) —
rather than replacing them outright. To get admins, teachers and students up
to speed quickly during that trial, `portal/manuals/` is a small set of HTML
pages styled to match the rest of the Portal:

- `index.html` — the landing page ("How-To Guide"), linked from a new
  **Manuals** sidebar section on every role's sidebar (admin, teacher,
  student alike) via `manuals/index.html`.
- `system-overview.html` — what the Portal does functionally, how it maps
  onto Zoho/MyMusicStaff/the website, and a short technical overview
  (Supabase, Netlify, roles, RLS, email) for anyone curious.
- `admin-guide.html` — one page per sidebar group (Front Desk, Teaching,
  Curriculum, Reports, plus a Super User section for those with access),
  each function explained with the traps that matter to a front-desk user
  (Cancel vs Discard vs Mark lapsed, Notifications vs Distribution Lists,
  studio-scoping as a default not a boundary, hard-delete warnings on
  Studios/Admins, etc.) — condensed from the same ground truth as the
  sections above, in plain "how do I…" language rather than developer notes.
- `teacher-guide.html` / `student-guide.html` — the same treatment for the
  two simplified dashboards.

**Access is role-gated (Sep 2026), the same way the rest of the Portal is.**
Each guide page calls `requireAuth([...])` exactly like any other page —
superuser and admin are allowed on all four guides; a teacher is allowed on
`system-overview.html` and `teacher-guide.html` only; a student is allowed
on `student-guide.html` only. `index.html` itself allows all four roles (it's
just the launcher) but calls `applyManualVisibility(role)` to hide the
sidebar links and guide-cards for anything that role can't open — so a
teacher simply never sees an Admin Guide card rather than seeing one that
403s. That visibility function is duplicated at the bottom of **every**
manual page (not just `index.html`), since each page also renders the same
Manuals sidebar and has to hide the same links for someone who reaches it
directly rather than through the hub. The allowed-roles list passed to
`requireAuth()` on each page is the real gate; `applyManualVisibility()` is
only tidying up what the sidebar/cards show — the two must be changed
together or a link will appear that then bounces the person who clicks it.
A rejected role lands back on `login.html`, which (already logged in)
immediately forwards them to their own dashboard — the same bounce any
other role-mismatched page in the Portal gives.

This reverses the original design, worth remembering if the guide is ever
revisited: it was first built with no auth at all, specifically so a new
hire could be sent the link before their account existed. The studio asked
for it locked down instead once the guides were reviewed, so that trade is
gone — a manual link is only useful to someone who can already log in, and
nothing here should assume otherwise going forward.

**The parallel-run intro paragraph on `index.html` is hidden from students
(Sep 2026).** The "this system is being trialled alongside Zoho CRM and
MyMusicStaff while we decide when it's ready to take over" framing is
internal context meant for staff — a student opening their guide doesn't
need it and shouldn't be worrying about it. `applyManualVisibility(role)`
now also toggles `#introCard` (hidden only for `student`); superuser, admin
and teacher still see it as before. Same pattern as everything else on this
page: purely a display toggle, not a second access gate — there was never
anything sensitive in that paragraph, just tone aimed at the wrong reader.

**Kept in sync by hand, same as the sidebar itself.** There's no shared
include (see Architecture above), so the guide content — and now the
per-page role list and `applyManualVisibility()` copy — will drift from the
real UI the same way the sidebar markup does whenever a page changes; worth
a skim of the relevant manual page after any UI change of substance, and a
check of both the `requireAuth()` list and the visibility function if a
role's access is ever revisited.

**Scope is deliberately narrow.** The guide explains the Portal only. It
does not attempt to prescribe what should still be double-entered in Zoho
or MyMusicStaff during the parallel run — that's a studio operating
decision, not something to bake into a how-to page that outlives it.

### How-To Guide content is now Decap-CMS-managed (Sep 2026)

The studio asked for a WYSIWYG way to edit the four guides themselves
(`system-overview.html`, `admin-guide.html`, `teacher-guide.html`,
`student-guide.html`) — mainly to add screenshots as they come up, without
asking a developer every time. There's no build step on this site (see
Architecture above), so a CMS can't "include" content into a page at build
time the way it would on a static-site generator — the guide pages fetch
their content client-side instead:

- Each guide's editable text now lives in a Markdown file under
  `portal/manuals/content/` (one per guide, matching the collection in
  `admin/config.yml`), with a short YAML frontmatter (`title`, `updated`)
  above the body.
- `guide-content.js` (loaded by all four guide pages, plus `marked` from
  `cdn.jsdelivr.net` — same CDN pattern as `@supabase/supabase-js`) fetches
  the relevant `.md` file after `requireAuth()` succeeds, strips the
  frontmatter, renders the body with `marked.parse()`, and injects the
  result into the page's `.doc-content` card.
- The **"On this page" box is now generated from whatever `<h2 id="…">` /
  `<h3 id="…">` headings actually end up in the rendered content**, instead
  of being hand-typed per page. A heading with no `id` (a few `<h3>`s in
  `teacher-guide.html` are intentionally like this) is simply left out, same
  as before. This means the TOC can never drift out of sync with the guide
  again — editing a heading's wording in the CMS updates the TOC link text
  automatically, but **changing or removing a heading's `id` breaks anything
  that links to that anchor** (e.g. `system-overview.html` links to
  `admin-guide.html#notifications` and `#distribution-lists` — check for
  other cross-links before renaming an `id`).

**The existing guide text was migrated in as raw HTML, not hand-converted to
Markdown.** `marked` passes raw HTML straight through unchanged, so every
guide renders exactly as it did before this change — verified by rendering
all four `.md` files locally and diffing heading/callout counts against the
original pages before shipping. The practical effect for editors: today's
paragraphs and headings will show up as an opaque "raw HTML" block in
Decap's rich-text view rather than editable text nodes — switch that field
to **Markdown/source mode** (the toggle in the field's toolbar) to edit the
existing wording as text, which works fine. Anything typed **fresh** in
rich-text mode — a new paragraph, list, link, or an image dropped in via the
toolbar's image button — becomes real Markdown and is fully WYSIWYG,
screenshots included. Over time, as sections get rewritten by hand in the
CMS, more of each guide will naturally become plain Markdown.

**Callout boxes** (the blue/amber/red tip-warning-caution boxes) aren't a
CMS widget — they're still the same raw HTML, now living in the Markdown
source. To add a new one, switch to source mode and paste one of:

```html
<div class="callout callout-tip">
  <strong>Short bold title</strong>
  <p>The tip itself.</p>
</div>

<div class="callout callout-warning">
  <strong>Short bold title</strong>
  <p>The warning itself.</p>
</div>

<div class="callout callout-caution">
  <strong>Short bold title</strong>
  <p>The caution itself.</p>
</div>
```

**Screenshots** upload to `portal/manuals/images/uploads/` (the
`media_folder`/`public_folder` in `admin/config.yml`) and are committed to
the repo like any other change — they still need the studio's own
`git push`-equivalent, except the CMS does that commit itself via Git
Gateway, straight to `main`, which goes live on the next Netlify deploy
exactly like any other commit to this repo.

**Manual setup still needed in the Netlify dashboard (I have no access to
do this myself):**

1. Site settings → **Identity** → Enable Identity.
2. Identity → registration → set to **Invite only** (otherwise anyone can
   sign up and edit the guides).
3. Identity → Services → enable **Git Gateway**.
4. Identity → **Invite users** → send an invite to each person who should
   be able to edit guides (their own email — they'll set their own
   password on accepting).
5. Open `pathfindermusiclessons.com.au/admin/`, accept the invite / log in,
   and the four guides appear as a "How-To Guides" collection.

**Netlify Identity + Git Gateway is the simplest fit for this site today,
but Git Gateway itself is a deprecated feature with no announced shutdown
date** — Netlify Identity is still fully supported, but has flagged Git
Gateway specifically as being phased out, and the Decap CMS project doesn't
yet have an official first-party replacement. For a small, low-traffic
internal tool like this it's a reasonable bet for now; if Netlify does
retire it, the two live alternatives as of Sep 2026 are **DecapBridge** (a
free-for-small-sites hosted login service built for exactly this
situation) or switching the backend to `github` with a small OAuth-provider
Netlify Function (more setup, but no third-party dependency). Either is a
config-only change (`admin/config.yml`'s `backend:` block plus one script
tag in `admin/index.html`) — the content side (the `.md` files,
`guide-content.js`, the collection schema) doesn't need to change either
way. Worth a re-check of Git Gateway's status if this is ever revisited.

If the domain is ever proxied through Cloudflare (it isn't today), note
that Cloudflare's proxy mode 405s requests to `/.netlify/identity/*` — a
known gotcha, not a misconfiguration, worked around by leaving DNS-only for
this domain or redirecting `/admin/*` to the `.netlify.app` subdomain.

**Invite/confirm/recovery emails link to the bare domain, not `/admin/`
(hit first Sep 2026).** Netlify Identity always builds these email links as
`{SiteURL}/#{token}=…`, never `{SiteURL}/admin/#{token}=…` — the Identity
widget that actually reads that token only runs on `/admin/index.html`, so
clicking the email link on the plain homepage does nothing. The proper fix
(custom Identity email templates pointing straight at `/admin/#…`) needs a
paid Netlify plan; the free-plan workaround, added to the very end of the
root `index.html`, is a small script that checks `location.hash` for
`invite_token` / `confirmation_token` / `recovery_token` /
`email_change_token` and forwards to `/admin/` with the same hash. If a
future invite or password-reset link still lands on the homepage and does
nothing, check that script is still there before assuming Identity itself
is broken — and if the homepage is ever significantly rewritten, make sure
this snippet survives the rewrite.

**Opening a guide in the CMS was a blank screen until `admin/config.yml`
got an explicit `branch: main` (Sep 2026).** Git Gateway silently defaults
to looking for a branch called `master` when `backend.branch` is omitted —
this repo's branch is `main`, so every content fetch 404'd (visible in the
browser console as `.../manuals%2Fcontent`, `....md&sha=master` and
`.../images/uploads` all 404ing) and the entry editor failed to render
anything. The "How-To Guides" collection *list* still showed fine even
while this was broken, because a `files` collection's entry list comes
straight from `config.yml` itself — it never touches the repo — so only
clicking into an actual entry exposed it. If entries ever go blank again,
check the browser console first; a 404 mentioning `sha=master` means this
setting got lost or overwritten, not that Identity/Git Gateway is broken.

**A screenshot added via the CMS can render but not be visible, because
`.doc-content img` had no size rule (Sep 2026).** The first test image
(added to `system-overview.md` through the editor) parsed into a perfectly
valid `<img>` tag — the Markdown and the upload both checked out fine —
but with nothing constraining its size it rendered at its native upload
resolution, which for anything wider than the card blows out the layout
instead of visibly failing, so it can look like "nothing happened." Fixed
by adding `max-width: 100%; height: auto` (plus a border, to match the
callout/table treatment) to `.doc-content img` in `manuals.css`. Any image
inserted through the CMS from here on is automatically capped to the card
width — no per-image sizing needed on the editor side.

**Remember the CMS commits straight to GitHub, not to anyone's local
clone.** Git Gateway pushes directly to the repo — publishing a CMS edit
does not touch `C:\Users\Du\pathfinder` (or any other local checkout) at
all, so checking a CMS-made change by reading the local file, the way
every other change in this project gets checked, will show stale content
until someone does a `git pull` there. Confirm a CMS edit by reading the
live site (or the deployed `.md` file directly, e.g.
`pathfindermusiclessons.com.au/portal/manuals/content/system-overview.md`)
instead — and pull before editing the same file locally afterward, or a
local edit + push can stomp a CMS-made change with no warning.

## Students page load (Sep 2026) — an N+1 that scaled with total student count

Admins reported the Students page taking noticeably longer to load as
studios grew to around 100 students each. The cause wasn't the 100
students themselves — it was `loadProcesses()` in `students.html`,
which ran once for the *whole* student list after every load, and did
several things per student rather than per page:

- **`evaluateAutoChecks(studentId, since)`** was called once per student
  who has ever had an enrolment process (trial confirmation, ongoing
  enrolment, or end enrolment) — in practice, most students who were
  ever onboarded through the Portal. Each call chained ~3-4 sequential
  Supabase round trips (student status, their lessons, an occurrence
  count per active lesson, and a second lessons fetch for the "fully
  ended" check). All of these per-student calls fired at once via
  `Promise.all`, but the browser only runs a handful of requests at a
  time — with a few hundred students in scope, most of that fan-out
  just queued up rather than actually running in parallel.
- The **reconciliation step** that marks a checklist `complete` once its
  auto-items are satisfied ran one sequential `UPDATE ... eq('id', p.id)`
  per newly-completed process, each one blocking the next.
- The **"last lesson date" lookup** for students who'd finished their
  end-enrolment checklist but were still teaching out their notice did
  two more round trips per such student.

None of this scales with what's shown on screen — it scales with how
many students have *ever* had a process, which only grows over time.

**The fix preserves the exact same result, computed differently.**
`evaluateAutoChecksBulk()` (new, in `js/processes.js`, next to the
original per-student `evaluateAutoChecks()` which is left in place and
unused for now) fetches every student's status, lesson memberships,
lessons, and occurrence counts in one small constant set of batched
queries — four or five total, regardless of whether 10 students or 1000
are in scope — then computes the identical per-student booleans in JS.
`loadProcesses()` in `students.html` calls this once instead of
`evaluateAutoChecks()` per student, and the reconciliation update and
the "last lesson date" lookup were similarly rewritten from N sequential
per-student queries to one batched query apiece. Verified against 200+
randomised synthetic scenarios (mixed active/ended lessons, series vs.
one-off, students with no lessons at all, null and non-null `since`
cutoffs) comparing the batched output field-by-field against the
original per-student function — zero mismatches — since this logic
feeds real state changes (a checklist auto-completing, a student later
getting marked inactive) and needed to be provably identical, not just
"probably fine."

Separately, `loadStudents()` itself had one avoidable serial hop: the
`student_current_grades` fetch doesn't depend on anything else the
function loads, but sat *after* the lessons → teachers → teacher
profiles chain instead of riding along in the same initial
`Promise.all`. Moved — a small, free win, unlike the process checks
above which needed an actual rewrite.

**What this deliberately didn't change:** `loadStudents()` still loads
every studio's students in one go and filters client-side by the studio
dropdown (`filterStudents()`), rather than querying only the selected
studio. That's a separate, larger lever — it would cut the base dataset
size proportionally to studio count, on top of the fix above — but it
changes the loading UX (a re-fetch on studio switch, a decision on what
a superuser or multi-studio admin sees by default) rather than being a
pure performance fix, so it's left as a future option rather than bundled
in here.

## Waiting list (Oct 2026) — a fourth enquiry outcome, not a new concept

**Tested live and confirmed working (Oct 2026).** Confirmed against real
enquiries: closing a task via "Add to waiting list" keeps it open with no
due date, logs the automatic note, and the Waiting list stat tile/bucket
view pick it up correctly.

Closing an enquiry's follow-up task always had three outcomes (trial,
enrolling, not proceeding). This adds a fourth, for when the family is ready
but nothing suitable is currently open: **Ready, but no suitable slot — add
to waiting list**, next to the other three in the same "How did it go?"
modal (`tasks.html`, `openOutcome()`/`resolveEnquiry()`).

**It reuses infrastructure that was already there and unused.**
`phase4a-waitlist-and-transfer.sql` gave `tasks` a `kind` column
(`'task'` / `'waitlist'`) specifically so an open-ended, no-due-date entry
wouldn't get lost among day-to-day work — and the Tasks dashboard's
**Waiting list** stat tile, and the bucket view it opens, were built off
that `kind` from the start. Both sat there counting zero until now: the
only piece missing was something that actually turned an enquiry into one.
Picking the new outcome does exactly that **in place** — the same
follow-up task flips to `kind='waitlist'`, `due_date` clears, and an
automatic `task_notes` entry ("Student added to waiting list.") is logged
— it does not close the task or create a new one, so the whole existing
contact-log thread carries over.

**The student's own status stays `prospective`.** They are still,
fundamentally, an undecided enquiry — what changed is only what's gating
them. Keeping `prospective` means every existing rule keyed off it
(excluded from the Students page, from notification recipients, from the
task subject picker) keeps applying with no further changes anywhere else
in the app. A distinct `waitlisted` status was considered and deliberately
not built — it would have meant touching the status check constraint and
every place that branches on `'prospective'`, for a label that the
Waiting list tile already makes visible on its own.

**Gating factors are optional structured fields on the task itself**,
not a new table: `waitlist_teacher_id`, `waitlist_day_of_week` (0=Sun..6=Sat,
same convention as `teacher_availability` and `recurring_tasks.weekday`),
`waitlist_time_from`/`waitlist_time_to`. "Preferred studio" is deliberately
**not** one of them — it's just the task's existing `studio_id`, which the
admin already sets; adding a second studio field would only invite the two
to disagree. All three are editable later from the task's own "Waiting
list details" panel (shown whenever Kind = Waiting list, same place the
manually-created kind already exposed), not just at the moment of
conversion — the admin may not know the family's preferred teacher yet
when they first join the list. The Waiting list bucket's row listing also
summarises them inline (teacher / day / time), so checking entries "one by
one" — today's manual process, see below — doesn't require opening each
task just to see who/when it's waiting for.

**`waitlisted_at` drives the 3-month clock, and is deliberately not
`tasks.created_at`.** The follow-up task may have existed for weeks before
the family actually decided to wait; the clock starts the moment they
join the list, set once when `kind` first becomes `'waitlist'` and left
untouched by later edits (editing an existing entry's preferred time must
not reset how long it's been waiting).

**Lapsing after 3 months is the "Not proceeding" outcome, reached
automatically.** `netlify/functions/lapse-waiting-list.js` runs nightly
(18:00 UTC, `netlify.toml`) and, for every open waitlist entry 90+ days
old, does exactly what an admin choosing "Not proceeding" does by hand:
`students.status → 'lapsed'` with an automatic `lapsed_reason`, the task
closes (`status='done'`), and a `task_notes` entry records why. Guarded on
the student still being `'prospective'` at the moment it runs — if an
admin already moved them on (booked a trial, enrolled, or manually marked
them lapsed) since they joined the list, the sweep leaves that decision
alone rather than overwriting it. No email is sent by this function, or by
adding someone to the waiting list in the first place — the admin has
usually just discussed it with the family directly; easy to add a
lifecycle email later if that turns out to be wanted.

**No automatic "a slot is now free" notification yet.** Checking entries
against current availability is still a manual process: open the Waiting
list tile and work through them one by one, same as today. An automated
version — comparing each entry's preferred teacher/day/time against that
teacher's `teacher_availability` and current bookings, then raising a
follow-up task when a match appears — was deliberately deferred rather
than guessed at; it deserves its own round once there are real waiting-list
entries to define "a suitable slot" against.

## Finance Follow-up (Oct 2026) — email + task in one click

**Tested live and confirmed working (Oct 2026).** Both the student and the
studio received the email, and the task was created with the right
details — the resend-on-close behaviour described further down was then
removed the same day, once seen working, in favour of treating the task
as a normal one (see below).

Admins used to send a "payment failed" email from Gmail by hand, then
separately add a task in the Portal to chase it — two steps for one piece
of work. **Finance Follow-up** on the Students page (`students.html`,
shown only for Trial/Active students) does both at once: send
`{{first_name}}` the fixed email below, and raise a follow-up task with an
automatic log entry, in a single click.

- Subject (not personalised): **"Urgent: Finance Follow-up"**.
- Body is fixed studio wording — payment may have failed, check your
  account, let us know a good time to retry, no lessons run until it's
  resolved, and an offer to help with financial pressure.
- The task: title **"Finance problem for {name}"**, About the student,
  assigned to whichever admin clicked the button, due **the next day** (not
  immediately — the family needs a day to respond before anyone chases
  again), with an automatic log entry explaining what happened and telling
  whoever picks it up not to let it slide.

**Half of this already existed, unwired, from an earlier round.**
`sendFinanceFollowUp()` in `portal/js/processes.js` and the "does this
task have an email that goes with it?" check in `tasks.html`'s
`offerTaskEmail()` were both already in place — written in anticipation of
exactly this feature, but with no button anywhere that actually called
them, and a few details that didn't match what the studio described once
asked directly: the old subject line was personalised instead of the fixed
"Urgent: Finance Follow-up" the studio wants, the task's due date was
*today* rather than *the next day*, the title read "Finance follow-up —
{name}" rather than "Finance problem for {name}", and no automatic log
entry was written at all. All four are now corrected to match.

**The task's studio is the admin's own working studio, not necessarily the
student's.** `triggerFinanceFollowUp()` in `students.html` reads the
Students page's own Studio filter (`#filterStudio`) — same "default, not a
restriction" convention as everywhere else — rather than the student's
`studio_id`, since the admin chasing a payment may not be the one who
normally sees that student. Falls back to the student's own studio if "All
Studios" is selected. `sendFinanceFollowUp()` takes this as an optional
third argument and keeps defaulting to the student's own studio when
nothing is passed, so the one other call site (below) didn't need to
change its own logic, just pass through what it already had on hand.

**No new Netlify Function.** Unlike the website enquiry form, this is an
authenticated admin action — the email still goes out through
`send-email.js` (the one path that can resolve a real address from
`auth.users`), but the task and its log entry are a plain client-side
insert under the admin's own session, the same as every other task created
from the Students or Tasks page. Nothing here needed service-role access.

**Closing a Finance Follow-up task does nothing special (deliberately,
Oct 2026) — it's chased and logged like any other task from here on.**
The first version matched the task's title in `offerTaskEmail()` so that
ticking it done re-offered the email and raised a fresh task due the next
day, looping until someone declined — mirroring how "Check-in with
student" tasks already worked. Tested live and explicitly walked back the
same day: the studio's actual process is an admin chasing the family and
logging contact attempts on the one task via its normal contact log, same
as any other follow-up, until the payment goes through — not a fresh
emailed reminder and a fresh task every single day. `offerTaskEmail()` no
longer matches a Finance problem title at all; only "Check-in with
student" still gets the resend prompt it was originally built for.
**One email, one task, closed by hand once it's resolved** — simpler than
the loop, and what was actually asked for once it was seen working.

## Student "Additional Notes" (Oct 2026)

A short internal note (max 50 characters) on each student, at the bottom
of the Student modal on `students.html`, below Parent / Guardian.
- **Storage:** `students.additional_notes text`, nullable, with a CHECK
  `char_length <= 50` (`students_additional_notes_len`). Migration:
  `supabase/student-additional-notes.sql` — run statement by statement
  **before** deploying the page, because `loadStudents()` now selects the
  column and the whole list would fail to load without it.
- **UI:** single-line input, `maxlength=50`, live "n / 50" counter
  (`updateNotesCount()`); saved on both Add and Edit as `null` when
  blank.
- **Side fix:** the Edit branch of `saveStudent()` used to ignore the
  result of the `students` update, so a failed save still toasted
  "Student updated." It now throws and shows the error.
- Not shown in the student list and not in CSV import/template — modal
  only, as asked.
- Visibility: like `enquiry_notes`, it is an ordinary column on
  `students`, so anyone whose RLS lets them read a student row (e.g. the
  student on their own row) could read it via the API. Don't put anything
  in it you wouldn't want the family to see.
- Tested against a stubbed Supabase in headless Chromium (prefill, 70
  chars typed → 50, update payload, blank on Add); **not yet tested
  live**.

## Recurring tasks: optional description (Oct 2026, migration #44)

The recurring-task editor (tasks.html → 🔁 Recurring tasks → New rule / Edit)
has a **Description** box under Title. It is stored in
`recurring_tasks.description` (nullable, ≤ 1000 chars) and shown, truncated,
in the rule list. When `generate-recurring-tasks.js` creates a task from the
rule it also inserts the description as a `task_notes` row (`logged_by` NULL,
so it appears in the task's log with no author tag). The note is written
**before** the `recurring_task_runs` row and wrapped in its own try/catch: a
failed note is logged but never blocks the run being recorded, because an
unrecorded run would make the next invocation create the task twice.

- **Run `supabase/recurring-task-description.sql` before deploying
  `tasks.html`** — saving a rule sends `description`, which fails until the
  column exists. Statements are run one at a time.
- Editing a rule's description only affects tasks generated **afterwards**;
  tasks already created keep the log entry they were given.
- Rules created before this change have no description and behave as before.

## Student modal: "View Tasks" (Oct 2026)

(Also on `students.html`: the student's name in the list is a link
(`.student-link`) that opens the same Edit modal as the Edit button, via
`openStudentByIndex()`.)

A **View Tasks** button in the footer of the Edit Student modal
(`students.html`) lists every task about that student, open and closed, and
jumps to the one you click.
- **Which tasks:** `tasks` rows with `subject_type = 'student'` and
  `subject_id = students.id` — the same link the Tasks page uses for its
  subject name. Open and closed (`done`, `cancelled`) both included.
- **Button state:** `refreshViewTasksButton()` runs a head-only count query
  when the modal opens. Zero tasks (or the query still running / failed) →
  the button is **disabled and greyed** (`#viewTasksBtn:disabled`); otherwise
  it reads "View Tasks (n)". Hidden on **Add Student** (nothing to show yet).
  A token (`viewTasksStudentId`) stops a slow answer for the previous student
  updating the current one.
- **List:** second modal `#studentTasksModal`, stacked over the student
  modal. Open tasks first (soonest due first, undated last), then closed ones
  newest first. Each row: title, due date (overdue / due today in red),
  Waiting list / Recurring markers, created date, and an Open / Done /
  Cancelled pill. A line at the top gives the open/closed counts.
- **Opening a task:** clicking a row sets `sessionStorage.openTaskId` and
  navigates to `tasks.html`, which opens that task's modal on load — the same
  hand-off the "ending" button on the student list (`openEndTask()`) already
  uses. `tasks.html` switches its status filter to All when the task is
  closed. If the student form has **unsaved changes**, the page asks before
  leaving (`studentFormSnapshot()` compared with the baseline taken when the
  modal opened).
- **Visibility:** whatever the Tasks page would show this admin (RLS on
  `tasks`); the count and the list use the same rule, so they always agree.
- No database change. Tested against a stubbed Supabase in jsdom (button
  states, ordering, escaping, unsaved-changes prompt, hand-off key);
  **not yet tested live**.

## Events (Oct 2026) — year-end concert booking

Admins create an **event** (name, date, start/end, venue, block length, slots
per block); students book a performance by ranking up to three **blocks**; the
Portal places them in the first block with room and everyone sees the grid fill
in. Pages: `events.html` (admins and teachers), `event-book.html` (students),
shared code in `js/events-common.js`; database in `supabase/events.sql`.

- **Model.** An event is split into `ceil((end − start) / block_minutes)`
  blocks, each with `slots_per_block` numbered slots. Block *i* starts at
  `start + (i − 1) × block_minutes`; slot *p* is shown at roughly
  `block start + (p − 1) × block_minutes / slots_per_block` (always labelled
  "about" — it is a guide, students are told to arrive at the start of their
  block). Times are local wall-clock `date` + `time`, not `timestamptz`.
  Defaults: 60-min blocks, 12 per block, overall cap of 5 performances per
  student (1–10).
- **One performance per instrument.** A student (or parent) can book once per
  instrument — Guitar, Piano, Band and so on — which covers students with
  several individual pieces and a band slot. Students can cancel their own
  booking from **My performances** ("Cancel booking") or from inside the edit
  form ("Cancel this booking") until bookings close; admins can always cancel.
- **Tables.** `events` and `event_bookings`. A partial unique index
  `(event_id, assigned_block, assigned_position) WHERE status = 'booked'` is the
  last line of defence against two performances in one slot; cancelled rows
  stay (history) and free their slot. Position 1000 is reserved as a parking
  slot while two performances swap.
- **Capacity is enforced in the database, not the page.** `submit_event_booking`
  locks the event row (`FOR UPDATE`), so two families pressing Submit together
  can't be given the same slot (tested with 10 simultaneous requests for 3
  places: exactly 3 succeed, 7 get `none_available`). It checks: caller is the
  student's own login (active/trial) or an admin in scope; event is `open` and
  before `booking_deadline` (Melbourne date; admins bypass); the per-student
  limit (admins bypass); 1–3 distinct valid blocks. Placement = first preferred
  block with a free slot, lowest free slot number. **Editing** keeps the current
  slot if the preferences are unchanged (so an admin's manual move survives a
  student fixing a typo); otherwise it re-places, counting the booking's own
  seat as free; if nothing fits it errors and changes nothing.
- **Privacy is enforced in the database.** Students and teachers have **no**
  table access (RLS: admins only). Everything goes through `SECURITY DEFINER`
  functions: `list_events_for_me()`, `get_event_grid()`, `get_my_event_students()`,
  `get_event_form_options()`, `submit_event_booking()`, `cancel_event_booking()`,
  `move_event_booking()` (admin only; `p_swap` swaps with whoever is there).
  `get_event_grid` masks by role: admins see everything; a teacher sees full
  detail for their own students (via `student_teachers` or the booking's
  teacher) and masked rows for others; a student sees their own family's
  bookings in full and everyone else as "Ava L." + instrument + piece +
  accompaniment *type* — never the teacher, comments, peer's name or
  preferences. Draft events are invisible to non-admins; events are scoped to
  the event's studio (NULL = all studios).
- **Layout guard.** A trigger on `events` refuses an edit that would leave a
  booked performance outside the new blocks/slots (`layout_conflict`) — move or
  cancel them first.
- **"Real time" is polling**, every 10–12 s while the tab is visible
  (`PF.poll`), not Supabase Realtime: Realtime honours RLS, and students have
  no table access, so it would show them nothing. The grid skips re-rendering
  when nothing changed, so the page never flickers.
- **Booking form** (`PF.bookingForm`) is one component used by the student page
  and the admin "add / edit performance" modal. Instruments and teachers come
  from `get_event_form_options` (the student's `student_instruments` +
  `student_teachers` **plus the teachers and instruments of their active lesson
  series**, private (`lessons.student_id`) or group (`lesson_students`), via the
  internal `_event_student_teachers()` — many students only have the series, no
  `student_teachers` row; the teacher list narrows to those who teach the chosen
  instrument; "Someone else / not sure" allows free text, and left blank is
  saved as "Not sure"). Siblings on one login get a
  picker; the active child follows `sessionStorage.activeStudentId`.
- **Admins** click a free slot to add a performance *in that slot* (the booking
  is made, then moved there), click a booked slot for details / Edit / Move
  (taken target = swap) / Cancel, switch between **Grid** and **Running order**
  (printable), and Open / Close bookings. Close = students can still view but
  not book, change or cancel. Delete is only allowed with no bookings.
- **Sharing.** The event page shows the booking link
  (`event-book.html?event=<id>`) with **Copy** and **Send invitation…**, which
  stores a drafted subject/body in `sessionStorage.notifPrefill` and opens
  Notifications (`applyPrefill()` in `notifications.html` ticks the event's
  studio and fills the message; the admin still reviews and sends it). The body
  uses `{{first_name}}` and a Markdown link, which `send-email.js` already
  understands. The same link appears on the student dashboard
  ("Upcoming events" card) and in the student sidebar.
- **Login return.** `event-book.html` sends a signed-out visitor to
  `login.html?next=event-book.html?event=<id>`; `login.html` honours `next` only
  if it matches that exact page + a UUID (`safeNext()`), so it cannot become an
  open redirect. Staff following the link are sent to `events.html` for the same
  event. A user forced to change their password first loses the `next`.
- **Teachers' view (Oct 2026, `supabase/events-teachers.sql`, migration #45).**
  A teacher now sees **only** their own students' performances and the ones they
  are asked to accompany, not the whole event. "Their student" = the booking
  names them as teacher, **or** they appear in `_event_student_teachers(student)`
  (`student_teachers` + active lesson series). "Accompany" =
  `accompaniment = 'teacher'` **and** `booking.teacher_id` = that teacher.
  `get_event_grid` filters server-side for teachers (so it can't be bypassed from
  the browser), adds an `accompany` flag to every row and sets `own` for the
  teacher's own students; admin and student output is unchanged. The page
  (`PF.renderGrid` with `teacherView`) shows only blocks that contain one of the
  teacher's performances, tags accompanied ones "♪ You accompany" (orange), and
  the Running order highlights them and says "With you".
  `get_event_teacher_summary(event)` (teachers only) feeds the **Your summary**
  card: X of your students performing, Y would like to be accompanied by you
  (names and pieces), and the backing tracks to prepare (student, piece,
  instrument, the notes the student left when booking, and the task's due /
  Done / Overdue state).
- **Backing-track tasks.** `event_bookings` has a trigger that keeps one task per
  booking (`tasks.event_booking_id`, unique) when `accompaniment = 'backing_track'`
  and the booking names a teacher from the list: subject = that teacher,
  `source = 'system'`, studio = the event's studio, no assignee (so it shows to
  admins/superusers exactly like a task an admin creates about a teacher, and
  the teacher sees it in My Tasks). The task's log holds the student, piece,
  instrument, event and the student's notes. **Due date = the later of (event
  date − 14 days) and the day of booking** (Melbourne), so a late booking is
  due that day rather than in the past. Changes follow the booking: piece /
  instrument / notes / teacher edits update an open task (and add a log line);
  cancelling the booking or switching away from a backing track **cancels** the
  open task with a reason; switching back reopens it; a *done* task is reopened
  only if the piece or teacher changed. Changing the event date re-dates open
  tasks that still have the automatic due date (hand-edited dates are left
  alone). Migration step 9 back-fills tasks for bookings that already exist.
  **Caveat:** a student who picks "someone else / not sure" (free-text teacher)
  gets no task, because there is no teacher to give it to; and the task belongs
  to the booking's `teacher_id` only — a student's other teacher sees the
  performance in the grid but not that backing-track task.
- **Backing-track task owner (fix, `supabase/events-teachers-fix1.sql`, migration
  #46).** The first version created these tasks with no studio and no assignee,
  so the admin Tasks page (which opens on the admin's own studio) filtered them
  out and the teacher's task popup showed blank Studio / Assigned to. Now
  `_event_backing_task_owner()` picks the **studio** = the event's studio, else
  the student's studio, else the teacher's first studio, and the **assignee** =
  an active admin of that studio (an admin set up for exactly that studio wins
  over one who covers every studio; oldest first; none → left in the studio
  queue). Later edits only fill a *missing* studio and never re-assign, so an
  admin's manual change stands. The migration also repairs existing tasks
  (blank studio and/or unassigned) without touching anything already set.
  `tasks.html` also fills About / Studio / Assigned to for **teachers** (their
  admin-only pickers were never loaded, so those boxes were blank on every task
  they opened; the assignee shows as "Studio admin" because a teacher can't
  read the admin list).
- **Send invitation → Students / Teachers / Both.** The button now opens a small
  chooser. Each audience has its own wording (`invitationDrafts()` in
  `events.html`): students are asked to book; teachers are told their students
  are invited, shown the link to `events.html?event=<id>` and told about the
  summary and the automatic backing-track tasks. The drafts go to Notifications
  in `sessionStorage.notifPrefill` as `{drafts: [...]}`; **Both** loads the
  student draft first and, after it has been sent, loads the teacher draft
  (`pendingDrafts` in `notifications.html`, in memory only — leaving the page
  drops the queue). `send-email.js` has a new recipient mode **`teachers`**
  (`{ studioIds? }`: active teachers at those studios, plus teachers with no
  studio set; none ticked = all). Teachers are emailed at their login address;
  `{{first_name}}` / `{{student_name}}` are the teacher's name; `{{portal_link}}`
  is refused for teachers. The studio summary email and `email_log` say
  "teachers" (`recipient_mode = 'teachers'`). Unlike the long-standing student
  modes, `teachers` **requires a signed-in admin**: Notifications now sends the
  Portal session token and the function checks it and the caller's role.
  *Still true and worth fixing separately:* the student modes of `send-email.js`
  have no caller check at all.
  **Deploy order:** run `events-teachers.sql`, then `events-teachers-fix1.sql`
  (each one statement at a time in the Supabase SQL editor), then `git push`.
- **Not built (ideas):** automatic emailing of a confirmation when a booking is
  made; waiting list when a block is full; per-event "accompanist/venue
  equipment" fields; exporting the running order to PDF/CSV (use Print for now).
- **Tests run:** unit tests for the slot/time maths (node); 83 database checks
  on a local Postgres 16 with stand-in tables (RLS, privacy masks, limits,
  deadline, swap, layout guard, 10-way race); jsdom runs of the admin, teacher
  and student pages against that database (create → open → book → move →
  cancel, sibling picker, live update, closed event, other-studio isolation,
  login `next`, notification prefill). The teacher additions were tested the same
  way (41 database checks on the filtered grid, accompany flag, task create /
  update / cancel / reopen / re-date / late booking / back-fill / uniqueness,
  summary and permissions; jsdom runs of the teacher page, the invitation
  chooser and the Notifications queue; the email function with a mocked
  Supabase and Resend). **Not yet tested live** — run the SQL
  first, then follow the go-live checks in the hand-over notes.

## Gift vouchers (Oct 2026) — front-desk PDF vouchers

Admins issue a gift voucher on demand and the Portal emails it as a PDF.
Page: `vouchers.html` (Front desk → Vouchers, admins/superusers only). PDF
drawing: `js/voucher-pdf.js` + `fonts/Inter-*.ttf` + `img/voucher-logo.png`.
Email: `netlify/functions/send-voucher.js`. Database: `supabase/gift-vouchers.sql`
(migration 43).

- **Flow.** New voucher → form (studio, recipient, subject, purchaser, date,
  value, message) → **Preview** (the real PDF in an iframe) → **Send**. Send
  inserts the register row, rebuilds the PDF from what the database stored, then
  calls the function. If the email fails, the row is kept (`emailed_at` null,
  `email_error` set; the page offers *Retry* and the register shows "Not sent"),
  so a retry never inserts twice.
- **PDF is drawn in the browser** (jsPDF 2.5.1 from jsDelivr, A4 landscape,
  vector, text stays selectable) so the preview *is* the attachment. Fonts are
  Inter subsets (Latin + Latin Extended, ~80 KB each) embedded as TrueType;
  characters outside them (emoji) are stripped, not printed as boxes
  (`PFVoucher.clean`). The logo is `img/voucher-logo.png`, the site logo with
  its orange background keyed out to transparency so it sits on charcoal.
  Layout is auto-fitting: the headline shrinks to two lines (18 pt minimum), the
  message box sizes to the text (7 pt minimum, then an ellipsis).
- **Voucher numbers** are `PF-XXXX-XXXX` from an alphabet without 0/O/1/I/L,
  random (not sequential, so not guessable), generated in the browser so the
  preview shows the final number; `UNIQUE` + a format `CHECK` in the database,
  and the page picks a new number and retries on the (very unlikely) collision.
- **Expiry** is `purchase_date + 1 year`, set by the insert trigger (29 Feb →
  28 Feb) — the browser shows the same date but never decides it. Purchase date
  cannot be in the future. *Expired* is derived on the page (`issued` and past
  `expires_on`), not stored.
- **What can change.** A trigger freezes everything the PDF printed (number,
  subject, value, names, message, dates, studio). Only contact emails, status and
  the email-tracking columns can change. Status: `issued → redeemed | void`;
  `void` is final. There is **no delete** (privileges revoked) — mistakes are
  voided so the number stays on record. RLS: admins and superusers only; teachers
  and students cannot see the table.
- **Email.** `send-voucher.js` uses Resend's *single-message* endpoint because
  the batch endpoint `send-email.js` uses does not support attachments. From and
  Reply-To = issuing studio's email; To = recipient; Cc = purchaser (only if an
  address was recorded and differs from the recipient); Bcc = the studio. Subject
  `Your Voucher for {subject}`; body is short and upbeat and uses the same
  branded shell copied from `send-email.js`. Unlike `send-email.js`, this
  function **verifies the caller**: it checks the Supabase access token and that
  the profile is an active admin/superuser. It also refuses void, redeemed or
  expired vouchers, checks the attachment really is a PDF (≤ 3 MB), sends an
  `Idempotency-Key` (a double-click can't mail twice), stamps
  `emailed_at/emailed_to/send_count`, and writes an `email_log` row
  (`recipient_mode = 'voucher'`). A resend to a corrected address updates the
  stored recipient email.
- **Student link.** Choosing a student in the picker records
  `recipient_student_id`; overwriting the name unlinks it (the voucher is then
  for someone else). Picker data comes from `students` (active/trial/prospective),
  email = the student's contact email, else the parent's.
- **Tested** against a local Postgres (guard trigger, RLS, privileges, leap day,
  idempotent re-run), the function with a mocked Resend (auth, status gating,
  attachment, cc/bcc, failure handling) and the page in jsdom with a fake
  database (picker, validation, preview, save-then-fail-then-retry, resend,
  redeem, expiry, number clash). **Not yet tested live** — run the SQL first,
  then send a voucher to yourself.

## Teachers utilisation report (Oct 2026) — superuser only

Page: `teacher-utilisation.html` (sidebar → **Super User → Teachers utilisation**;
`requireAuth(['superuser'])`, so an admin who types the URL is sent to the login
page). Calculations: `js/utilisation-calc.js` (pure functions, `window.PFUtil`,
also loadable from Node for tests). **No database change** — it reads existing
tables as the signed-in superuser: `teacher_availability`, `schedule_view` and
`attendance`.

- **Controls.** Teacher drop-down (inactive teachers are listed and labelled),
  From / To calendar pickers (both days inclusive: `gte` / `lte`), defaulting to
  the last complete **Wednesday–Tuesday fortnight** (ends on the most recent
  Tuesday *before* today, starts 13 days earlier). The report runs as soon as a
  teacher and a valid period are set; the limit is 13 months. Export CSV and
  Print are included.
- **Grid.** One column per *day + studio* in the format
  `Tue 29/09/2026 (Ringwood)`, plus a Total column. A column exists for every
  date that has availability for that weekday **or** any lesson (so an
  available-but-empty day shows zeros, and a lesson outside the set availability
  still appears with "—" for availability). Rows: **Availability** (each range
  as `03:00 PM-08:00 PM (5 Hrs)`; several ranges on a day are listed in time
  order), **Lessons booked** (`n (x Hrs)`), **Lessons taught**
  (`n (% of booked)` and `x Hrs (% of booked time)`), **Billable lessons**
  (same shape).
- **Counting rules (agreed with the superuser).** One lesson = one scheduled
  occurrence; a group lesson counts once with its length. *Booked* = every
  occurrence, including ones later cancelled. *No-show* = the occurrence is
  cancelled, or every student on its roster is marked Absent (no credit),
  Absent (notice given) or Teacher cancelled. *Taught* = booked less no-shows.
  A lesson that hasn't been marked yet counts as taught (not billable) — the
  page lists how many are unmarked. *Billable* = at least one student marked
  Present (a cancelled occurrence is never billable). Whoever actually taught
  the occurrence gets it (`schedule_view.teacher_id` already resolves
  substitutes), so a covered lesson counts for the substitute.
- **Limitations.** Availability is the teacher's *current* weekly availability
  applied to every matching date (there is no history of past availability, so
  a changed roster rewrites past periods). Percentages are rounded to whole
  numbers; hours to two decimals.
- **Menu.** The link is a hidden `utilLink` in each page's Super User section,
  revealed in the same place as `studiosLink` / `adminsLink`; the pages that
  build their sidebar in JavaScript (Tasks, Enquiries, Events, Vouchers) add it
  inside their `if (me.role === 'superuser')` block.
- **Tests run.** 37 unit checks on the sums (default fortnight incl. year-end,
  clock/hours formatting, availability ranges, every attendance outcome, group
  lessons, cancelled/unmarked, empty periods, CSV) and a jsdom run of the page
  against a fake database (superuser-only, query bounds, validation, error
  display, CSV file name, non-superuser). **Not yet tested live** against the
  real data.

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
- **A filter dropdown has to trigger every view that reads it, not just the
  obvious one.** `tasks.html`'s studio filter (Sep 2026) changed the table
  rows but the summary tiles (Overdue / Due today / Unassigned / …) stayed
  at the studio-wide total, because `bucketCounts()` never read the filter
  and nothing recomputed it on change — only the table's own `render()` was
  wired to `onchange`. Fixed with a dedicated `onStudioFilterChange()` that
  calls both `renderBuckets()` and `render()`. Worth checking for the same
  shape anywhere a page has more than one thing reading a shared filter
  control: each one needs its own path back from that control's `onchange`,
  not just the one a change happened to be tested against.
- **A studio summary email can fail with nothing to show for it in Resend.**
  `netlify/functions/send-email.js`'s bulk-send summary (5b) called a
  `summaryTemplate()` that didn't exist in the file — a `ReferenceError`
  thrown while building the request, before `fetch()` to Resend ever ran.
  Caught by the surrounding `try/catch` so the student batch still sent fine
  and the function returned normally, but the studio never got its "record"
  email and nothing shows in the Resend dashboard either, because the
  request was never actually sent. The toast still correctly said "summary
  copy failed" (`email_log.summary_error` had the real reason), but there
  was no Resend log entry to point at, which is what made this look like a
  Resend-side problem rather than a code one. Fixed Sep 2026 — check
  `email_log.summary_error` first whenever "sent to students but not to
  the studio" comes up again; if it's non-null but Resend shows no attempt
  at all, the summary send is throwing before the network call, not being
  rejected by Resend.
- **`lessons.recurrence_type` does NOT accept `'oneoff'`.** That string is
  only ever a UI selector value (`lPattern` in the Add Lesson / Clone
  modals) — the `lessons_recurrence_type_check` constraint only allows
  `'indefinite'`, `'occurrences'`, or `'date_range'`. A single dated lesson
  (a trial, a makeup, a clone) is stored as `recurrence_type: 'occurrences'`
  with `recurrence_count: 1`, same as `saveLesson()` already does. Got this
  wrong once (Sep 2026) writing the clone-lesson feature — insert failed
  with the check-constraint error, not a silent no-op, so at least it's
  loud.
- **"Which instrument(s) does this student play" is `student_instruments`,
  not active lesson bookings.** The distribution-lists "by instrument" mode
  (Sep 2026) was first written like `teacher` mode — deriving students from
  `lessons?instrument=eq.X&status=eq.active` — and returned 0 for a real,
  active Saxophone student because she had no currently-booked lesson series
  in that exact shape at the moment of testing (between terms / not yet
  scheduled). `student_instruments` (`student_id, instrument, skill_level`)
  is the actual enrolment record — the same table `students.html` reads to
  show a student's instrument tags — and is independent of whether a lesson
  is currently booked. Fixed `mode === 'instrument'` in
  `netlify/functions/send-email.js` to query `student_instruments` directly.
  `teacher` mode is still correctly lesson-booking-derived (a teacher's
  student list genuinely is "who currently has lessons with this teacher"),
  so don't reflexively copy that pattern onto anything answering "what does
  this student play" instead of "who currently has lessons with X."
- **Grading report "Show ungraded students" uses `student_instruments` to
  decide which instruments count (Oct 2026).** It builds (student, instrument)
  pairs from the lesson roster, and `lessons.instrument` is whatever the Add
  Lesson dropdown said — which defaults to the *teacher's* first instrument
  and is never checked against the student. A guitar student with a
  guitar-and-piano teacher could therefore sit on a Piano lesson and be listed
  as "Piano — not yet graded". The report now drops any instrument the student
  has no `student_instruments` row for. A student with no `student_instruments`
  rows at all keeps the old lesson-derived behaviour, so a gap in that table
  can't hide anyone. The underlying mislabelled lesson is not corrected.

## Known limitations & open decisions

- **The private (acquired) studio is deliberately *not* in the Portal.** It
  needs its own admins/teachers/students, invisible to Pathfinder admins and
  vice versa. That isn't achievable by a UI default: most tables' RLS is
  role-based only (see migration 27, "studio is a UI default, not a database
  boundary"), `get_my_studio_ids()` treats an admin with empty `studio_ids` as
  all studios, views and service-key Netlify functions bypass RLS, and the
  Pathfinder name/domain is hardcoded across pages and emails. Doing it safely
  means end-to-end re-testing the whole Portal, which was judged too much risk
  while the Portal is still new to users. Instead the studio has a separate
  tool: a Google Sheet + Apps Script ("Private Studio Manager" — students,
  teachers, lessons timetable, attendance, GST invoices, bulk email), kept out
  of this repo (`Private studio/` is in `.gitignore`). Revisit only if the
  studio needs the full Portal feature set.
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
18. `phase4b-enquiries.sql` — `prospective` and `lapsed` statuses, enquiry fields
19. `phase4c-processes.sql` — `student_processes`, `process_items`
20. `phase4c-confirmation-emails.sql` — `process_items.sent_at`
21. `phase4c-series-check.sql` — series vs one-off trial lesson
22. `phase4c-deferrable.sql` — `process_items.can_defer`
23. `phase4c-lesson-created-at.sql` — `lessons.created_at`
24. `phase5-security-lints.sql` — drops the `zoho_leads_import` staging table
25. `phase5-view-rls.sql` — `my_lesson_ids()`, four student read policies,
    `security_invoker` on both views
26. `phase5-scope-students.sql` — admins see only their own studios' students
    *(superseded by 27)*
27. `phase5-unscope-with-defaults.sql` — reverts 26; studio is a UI default,
    not a database boundary
28. `phase5-notification-images.sql` — public bucket for pasted screenshots
29. `phase5-lesson-reminders.sql` — opt-in reminders, `reminder_log`
30. `phase5-admin-attendance.sql` — admins may mark attendance
31. `phase5-substitute-teachers.sql` — substitute columns, both views rebuilt
32. `phase5-substitute-access.sql` — what a substitute may see
33. `phase5-makeup-lessons.sql` — `is_makeup`, both views rebuilt
34. `phase5-fortnightly-lessons.sql` — `lessons.frequency` (weekly/fortnightly)
35. `phase5-require-contact-email.sql` — `students` must have email or parent_email (NOT VALID check)
36. `attendance-owner-check-perf-fix.sql` — `my_owned_occurrence_ids()`,
    replaces the slow inline subquery in "Teacher marks attendance for own
    lessons" (see Row Level Security section above)
37. `lesson-credits.sql` — `lesson_credit_movements`, `student_credit_balances`
    view, `my_teaching_student_ids()` (see Lesson credits section above)
38. `phase10-student-own-name.sql` — `students.first_name`/`last_name`, backfilled
    (see "A student's name now lives on `students`, not `profiles`" below)
39. `phase11-schedule-view-own-student-name.sql` — `schedule_view` rebuilt to use
    the new columns
40. `phase12-waiting-list.sql` — `tasks.waitlist_teacher_id`/`waitlist_day_of_week`/
    `waitlist_time_from`/`waitlist_time_to`/`waitlisted_at` (see Waiting list
    section above)
41. `events.sql` — `events`, `event_bookings`, `event_block_count()`, layout-guard
    trigger, admin-only RLS, and the seven booking functions (see Events
    section above). Run statement by statement, **before** deploying
    `events.html` / `event-book.html` / the updated dashboard
42. `events-per-instrument.sql` — one performance **per instrument** per student
    (case-insensitive; "Band" is always offered as its own instrument). Raises
    `instrument_booked`; admins bypass it. `max_per_student` becomes an overall
    cap (default 5, allowed 1–10) and events still on the old default of 1 are
    lifted to 5. Fresh installs already get this from `events.sql`. Run
    statement by statement **before** deploying the matching pages
43. `gift-vouchers.sql` — `gift_vouchers` register, insert/update guard trigger,
    admin-only RLS, table privileges (see Gift vouchers section above). Run
    statement by statement **before** deploying `vouchers.html`,
    `js/voucher-pdf.js` and the `send-voucher` function

*(Several migrations applied between 27 and 35 — schedule performance
indexes, BoK grading, fortnightly lessons, recurring tasks, and others —
aren't individually numbered above; see `portal/supabase/` for the full set
and each file's own header for what it does.)*

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

**Phase 4b (enquiries) complete and tested.** Enquiries registry, manual entry,
automatic follow-up tasks, three distinct exits, converted history, and
duplicate detection against existing and past students.

**Navigation is grouped** (Events joined Front desk in Oct 2026) as Teaching (Schedule, Lessons, Students, Teachers),
Front desk (Enquiries, Tasks, Notifications), Reports, and Super User. Teacher
pages are ungrouped — three items don't need it.

**Phase 4c (enrolment processes) built, partly tested.** Three checklists with
live automatic checks, deferrable items, six lifecycle emails, automatic tasks
with calculated due dates, and a monthly lessons view with a student filter.

Tested: enquiry acknowledgement, trial confirmation, conversion to trial and to
enrolment, task date realignment, check-in email, deferred items clearing.
**Not yet tested: the full end-enrolment path**, including `End lessons…` and
the student going inactive on completion.

**Supabase security lints closed.** Both views now run with
`security_invoker = on` and enforce RLS; the `zoho_leads_import` staging table
was dropped. Verified against all four roles in the browser.

**Inactive accounts can no longer log in.** `profiles.status` and
`students.status` are separate — ending an enrolment sets the student record
inactive and leaves the profile alone — so login checks both. Note this is
checked at login only: an existing session survives until it expires.
`isAccountBlocked()` in `supabase-client.js` is there for wiring into
`requireAuth` if per-page enforcement is ever wanted.

**Phase 4d complete and tested live (Oct 2026) — website enquiries go to
the portal only, Zoho retired from this path.** Confirmed in production on
both `index.html` and `pricing.html`: enquiries create the student + task
for the right studio, no longer reach Zoho, the enquirer lands on the
thank-you page and gets the acknowledgement email, the studio gets its
notification, and server-side reCAPTCHA verification is active (after
`RECAPTCHA_SECRET_KEY` was added under the site's own environment
variables — not the account-wide "shared" ones, which need a paid plan; a
per-site variable doesn't).

The contact form on `index.html` and
`pricing.html` no longer posts to Zoho at all; it submits via `fetch` to
`receive-enquiry.js`, which is now the sole destination and sends both emails
Zoho used to send — the acknowledgement to the enquirer and the notification
to the studio (reply-to set to the enquirer, so the studio can just hit
reply). On success the browser redirects to the same thank-you page Zoho used
to redirect to; on failure the form shows an inline error rather than losing
the enquiry silently, and the submit button and reCAPTCHA widget both reset so
the visitor can retry.

These two emails are built with their own small, fully-`escapeHtml`'d
templates in `receive-enquiry.js` — deliberately **not** `send-email.js`'s
`emailTemplate()` markdown-lite renderer, since these carry free text an
enquirer typed into a public form, and that renderer's `**bold**`/
`[link](url)` syntax would let an enquirer's own message turn itself into a
styled callout or a clickable link in the studio's inbox.

Protections are an origin check, a honeypot field, duplicate suppression
within the hour, and now **server-side reCAPTCHA verification** (the form's
existing checkbox widget was always client-side only — Zoho consumed the
token itself, and Google only allows one verification per token, so this
function never could have also checked it against the same token). This
needs `RECAPTCHA_SECRET_KEY` set in Netlify (the secret for the sitekey
already on the form, from the Google reCAPTCHA admin console) — without it,
`verifyRecaptcha()` logs an error and **skips verification rather than
rejecting every submission**, so the form stays up but isn't actually
protected until that key is set. Same fail-open philosophy if Google itself
is unreachable at submit time. Missing `RESEND_API_KEY` degrades similarly:
the enquiry and its task are still created, the two emails are just skipped
(logged) — never the other way around.

**Lesson reminders** run from a Netlify scheduled function at 20:00 UTC — 6 AM
Melbourne in winter, 7 AM in summer. Netlify cron is UTC only, so an
early-morning window avoids the daylight-saving drift rather than fighting it.
Opt-in, per family, with a token-based unsubscribe link. Needs Resend's paid
tier at scale: ~100 lessons a day is the free tier's entire daily allowance.

**Pasted images in notifications** go to a public Supabase Storage bucket —
email clients fetch images with no session, so it cannot be otherwise. The URLs
are unguessable but permanent, and the composer warns about it. Nothing removes
them; `phase5-notification-images.sql` has a housekeeping query.

**Substitute teachers, makeup and one-off lessons** are in. A one-off is a
first-class choice on the lesson form — trial, makeup, or ad-hoc request — which
replaced booking a "series of one" and editing it afterwards. Makeup lessons show
amber; the daily and monthly views now share one colour scheme.

**Attendance shows on the schedule.** Green tick, red cross, or struck through
for a teacher cancellation. A group shows one state: all present, all absent, or
amber for a mix.

**Lifecycle emails were not BCCing the studio.** `send-email.js` only BCCs when
told where to, and the lifecycle sends passed `from` but not `bcc`. Affected the
trial and enrolment confirmations, the enquiry acknowledgement, check-in,
payment follow-up and farewell — silently, for weeks. Fixed in `processes.js`;
`email_log` has the record of everything that went out regardless.

**Lesson cancellation emails now carry the occurrence's own note (Oct
2026).** `sendCancellationEmail()` in `lessons.html` builds its own
`bodyText` client-side and already had the cancelled occurrence (`occ`)
in hand, including `occurrence_notes` — it just wasn't being used. A
single-occurrence cancellation ("Cancel this lesson only") now adds
`Note from the studio: {text}` into the email when that occurrence has
one. Deliberately **not** added to the "this + future" / "entire series"
scope: `occ` there is still just the one occurrence that happened to be
open when Cancel was clicked, and its note was very likely written for
something unrelated (bring sheet music, online this week) — attaching it
to a blanket "cancelled from X onwards" notice would more likely mislead
than help, so that case is left exactly as it was.

**Typing a note and clicking Cancel straight away, with no Save in
between, used to lose it (fixed same day, Oct 2026).** `occ.occurrence_notes`
came from `allOccurrences` — whatever was last loaded from the database —
not from the `#occNotes` textarea itself, so a note typed just before
clicking "Cancel this lesson only" was never persisted and never made it
into the cancellation email either. `cancelOccurrence('single')` now reads
the textarea directly at the moment Cancel is clicked and writes it into
the same `lesson_occurrences` update that sets `status: 'cancelled'`, so
the note is saved and emailed in one action — no separate Save required.
Still scoped to the single-occurrence cancel only, same as above.

**Lessons: teacher filter and teacher weekly grid (Oct 2026).** A new
"All teachers" dropdown sits beside the student filter on `lessons.html`.
Picking a teacher switches to **Weekly** and, instead of the card list,
`loadTeacherWeekGrid(teacherId)` draws a grid: Mon–Sun columns for the
week held in `weekStart`, the same half-hour time-slot rows as the daily
grid, and each lesson drawn as in the daily grid (private / group /
makeup / cancelled, online badge, notes, attendance ticks). The ‹ Today ›
arrows and date picker move the week as usual. Clearing the dropdown
(or the "show all teachers" link) returns to the normal weekly cards.
- *Taught by* includes lessons they **cover** for someone else (labelled
  "Covering X") and shows their own lessons **covered by** someone else
  ("Covered by X"); it is matched on `lessons.teacher_id` or
  `lesson_occurrences.substitute_teacher_id`, filtered client-side.
- Teacher and student filters are mutually exclusive — choosing one
  clears the other (student → Monthly, teacher → Weekly).
- The Studio and Status filters still apply. With "All Studios" and more
  than one studio, each block also carries the studio name.
- Daily view honours the teacher filter too (only that teacher's column);
  Monthly view filters by that teacher's lesson ids.
- Availability greying is per weekday. If the teacher has any
  availability on record, a weekday or slot with none is greyed; with
  none on record nothing is greyed. (Slightly stricter than the daily
  grid, where an empty day stays neutral.) Empty cells are clickable and
  prefill the Add Lesson modal with that column's date.
- **Deliberate duplication:** the overlap-clustering and block-drawing
  code is a copy of `loadDailyView`'s, not a shared helper, so as not to
  risk regressions in the heavily-fixed daily grid. If one is fixed,
  check the other (a comment in the code says so). Clustering must be fed
  `allOccurrences` (which carries each lesson's roster), not the raw
  query rows — an early version used the latter and showed blank names.
- Tested against a stubbed Supabase in headless Chromium (column
  placement, overlaps, week arrows, studio filter, cover labels, filter
  exclusivity, add-lesson prefill); **not yet tested live**.

**Next up:** finish end-enrolment testing; attendance report page; RLS on
views before go-live.

**Teacher landing page.** The teacher dashboard shows an open-task count —
red when non-zero — and a strip listing outstanding tasks above the schedule.
The strip is hidden entirely when there is nothing outstanding, so the schedule
stays the main thing on a normal day.

**Small gaps worth knowing:** the Admins page only lists accounts that have an
`admins` row, so a profile with `role='admin'` and no row is invisible and
unmanageable there. Password reset links always point at production, because
the redirect is hardcoded in `create-user.js` — they still work from local
development, they just land on the production page.

**Siblings sharing a login all showed the same name, and editing one renamed
them all (fixed 1 Oct 2026).** Surfaced the day after the sibling-login
consolidation (see "Shared family logins" above) linked several families'
students onto one shared login each: an admin noticed a family of three all
displaying as "Nainika Sinha" in the students list, a teacher's two students
looking like one, and two lessons showing the same student name. Root cause:
`students` had no name of its own — every page read `first_name`/`last_name`
from `profiles` via `user_id`, which is also the shared login's own single
profile row. Siblings on the same login therefore all resolved to whichever
name happened to be on that one profile, and the edit form wrote a new name
straight onto it, overwriting every sibling at once.

Fixed by giving `students` its own `first_name`/`last_name`
(`phase10-student-own-name.sql`), backfilled from each student's then-current
profile — correct for everyone except the 22 students who'd just been
relinked onto a sibling's login, whose individual name had already been
deleted along with their old placeholder profile. Those 22 were restored from
the relink script's own record of who was who, not from any live data (it had
already been overwritten). Every student-facing read/write that used to go
through `profiles` was then switched to the student's own columns: the
students list and edit form, `lessons.html`, `dashboard-teacher.html`,
`my-students.html`, `teacher-detail.html`, `attendance-report.html`,
`credits.html`, `enquiries.html`, `tasks.html`, `processes.js` (automatic
tasks and lifecycle emails), and `send-email.js` (so notifications — including
the Sunday portal-launch send — greet the right child, not the login's).
`schedule_view.student_name` had the same bug baked into the SQL view itself
(`phase11-schedule-view-own-student-name.sql`). The one deliberate exception:
the shared login's own top-nav identity (`supabase-client.js`) shows
"`{{last_name}} family`" for a student role rather than privileging whichever
sibling first registered.

**Student creation now sets `students.first_name`/`last_name` directly** —
`receive-enquiry.js`, the Enquiries page's manual-add form, and the Add
Student and CSV-import paths in `students.html` all write both now, so this
can't regress by a new student record going through the old, profile-only path.
