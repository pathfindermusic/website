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
    │   └── manuals.css
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
replacement together — `.find()` showed whichever came back first. Live lessons
get the space; cancelled ones collapse to one line each.

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

**Navigation is grouped** as Teaching (Schedule, Lessons, Students, Teachers),
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

**Website enquiries reach the portal (parallel run).** The contact form still
posts to Zoho, which stays authoritative and still sends both the
acknowledgement and the studio notification. A `keepalive` fetch also creates
the enquiry and its follow-up task in the portal, so admins can work it in both
systems. `receive-enquiry.js` sends nothing — see `SEND_ACKNOWLEDGEMENT` for
the cutover.

Protections are an origin check, a honeypot field and duplicate suppression
within the hour. reCAPTCHA is **not** verified: Zoho consumes the token and
Google allows one verification per token. At cutover the portal takes it over.

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

**Next up:** finish end-enrolment testing; Phase 4d (website form posts to the
portal, Zoho retired); attendance report page; RLS on views before go-live.

**Teacher landing page.** The teacher dashboard shows an open-task count —
red when non-zero — and a strip listing outstanding tasks above the schedule.
The strip is hidden entirely when there is nothing outstanding, so the schedule
stays the main thing on a normal day.

**Small gaps worth knowing:** the Admins page only lists accounts that have an
`admins` row, so a profile with `role='admin'` and no row is invisible and
unmanageable there. Password reset links always point at production, because
the redirect is hardcoded in `create-user.js` — they still work from local
development, they just land on the production page.
