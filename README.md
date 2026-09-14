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

## Planned: Guitar grading / Body of Knowledge framework

Requested Sep 2026, source document `Pathfinder_Guitar_Grading_Framework.pdf`
(Guitar Studio, four tiers/nine grades: Foundation → Pre-Grade 1, Beginner →
Grades 1–3, Intermediate → Grades 4–6, Advanced → Grades 7–8). This section
is the agreed design so implementation can proceed without re-litigating it.
Scope for this phase was confirmed with the studio:

- **Build now:** an artefact library (chord charts, songs, backing tracks,
  etc.) filed by instrument/grade/component, a per-student grade history, and
  a teacher-facing "pick artefacts for this lesson" flow that feeds the
  existing shared lesson notes.
- **Deliberately deferred:** the framework's weighted Repertoire 50% /
  Technique 30% / Knowledge 20% scoring engine, the ≥60% overall & ≥50%
  per-strand progression rule, Pass/Merit/Distinction banding, and
  certificate/recital tracking. Grades are recorded as a milestone a
  teacher/admin sets directly (same trust level as today's skill_level edit),
  not calculated from sub-scores. Revisit once the simpler version is in use.
- Guitar only, to start. The schema is instrument-generic (see below) so the
  same tables can carry a second instrument's BoK later without a redesign —
  but only Guitar gets grade levels and artefacts populated in this phase.

### Relationship to `student_instruments.skill_level`

The portal already has `student_instruments.skill_level` — a plain
`integer 0–8`, hand-set by a teacher/admin, no history, no grade concept.
It's read/written in five places: `dashboard-student.html` (student's own
read-only bar), `my-students.html` (teacher edits it per student), `teacher-detail.html`
and `students.html` (admin views/edits, including CSV bulk-import columns
`instrument_N`/`skill_level_N`), and defaulted to `0` on enrolment in
`enquiries.html`. It's banded client-side into Beginner (≤3) / Intermediate
(≤6) / Advanced (>6) — a coarse, informal echo of the same four-tier idea the
new framework formalises.

Decision: **for Guitar students, the new Foundation–Grade 8 badge replaces
the skill-level bar** on all four display screens above. The `skill_level`
column, table and every non-Guitar instrument's editing flow are untouched —
other instruments have nothing else to show yet. A Guitar student's
`student_instruments` row still exists (instrument list, CSV import, teacher
assignment all key off it) but its `skill_level` value stops being displayed
once a grade-milestone row exists for that student/instrument; nothing
deletes or migrates the old integer.

### Google Drive vs. querying Drive live

Recommendation: **keep the files on Drive, store structured metadata + a
Drive share link per artefact in Supabase.** Reasons:

- The library is curated, not dynamic — admins decide what's "in" the BoK and
  what grade/component it belongs to. That classification has to be typed in
  somewhere regardless; it may as well be the row that also holds the link.
- Querying Drive live means a service account or OAuth flow, Drive API scopes,
  keeping folder structure and naming in sync with grade/component tags, and
  a new failure mode (Drive API down/rate-limited) on every lesson-planning
  screen. None of that is needed to answer "which artefacts exist for Grade 3
  Repertoire" — a Supabase table answers that instantly and is already how
  the rest of the portal works.
- Existing precedent: `dashboard-teacher.html`'s lesson-note modal already has
  a free-text `drive_link` field a teacher pastes in by hand today. This
  design formalises that same pattern (a link stored in Postgres, opened in a
  new tab) rather than replacing it with something architecturally new.

### Data model (Phase 1)

New tables, additive only — no changes to existing tables beyond one new link
table referencing `lesson_occurrences`:

- **`bok_grade_levels`** — generic, instrument-agnostic reference list: 9 rows,
  `sort_order` 0–8, `code` (`pre_grade_1`, `grade_1`…`grade_8`), `tier`
  (`Foundation`/`Beginner`/`Intermediate`/`Advanced`), `label`. Shared across
  every instrument's BoK, today and in future.
- **`bok_artefacts`** — the library: `instrument`, `grade_level_id` (FK),
  `component` (`repertoire`/`technique`/`knowledge`, CHECK-constrained —
  matches the document's three strands), `title`, `description`, `drive_url`,
  `tags`, `is_active`, `created_by`, `created_at`. The document's "living,
  approved repertoire list" per grade is just this table filtered to
  `component = 'repertoire'` for that grade — no separate table needed.
- **`student_grade_milestones`** — the per-student timeline: `student_id`,
  `instrument`, `grade_level_id` (FK), `achieved_on` (date), `notes`,
  `recorded_by`. A student's *current* grade for an instrument is simply the
  row with the latest `achieved_on`; every prior row stays as history, which
  is what answers "when did they reach each grade."
- **`lesson_occurrence_artefacts`** — link table: `occurrence_id` (FK to
  `lesson_occurrences`), `artefact_id` (FK to `bok_artefacts`), `added_by`,
  `created_at`. One row per artefact picked for a lesson occurrence (whole
  occurrence, not per student — matches how `lesson_notes` already works for
  group lessons: one shared note per occurrence). This table alone answers
  "what artefacts has this student gone through": join it through the
  occurrence's existing roster (`lesson_students`, same `rosterFor` logic
  `lessons.html` already uses for ad-hoc vs. permanent students).

### UI changes (Phase 1)

- **New admin page — Artefact Library.** CRUD for `bok_artefacts`: filter by
  instrument/grade/component, paste a Drive link, tag, activate/retire.
  Same pattern as the existing admin list+modal pages (`students.html` etc.).
- **Teacher lesson planning — `dashboard-teacher.html`'s existing note modal
  (`openNoteModal()` / `saveNote()`).** Add an artefact picker above the
  current free-text fields, pre-filtered to the occurrence's instrument (and
  ideally the primary student's current grade level once that's known). Picks
  are saved to `lesson_occurrence_artefacts`. The existing hand-typed
  `drive_link` field stays as-is, for a one-off file that isn't in the
  library yet — the two aren't mutually exclusive.
- **Notes shared with students stay automatic, not manual.** Today
  `notifyStudentOfNote()` emails `note_text` + `drive_link`, and
  `dashboard-student.html`'s note-box renders the same two fields. Both gain
  a generated "Materials covered" list sourced live from
  `lesson_occurrence_artefacts` for that occurrence — the teacher never types
  artefact names into the note by hand, it's assembled from what they picked.
- **Grade badge.** Guitar students' entries in `dashboard-student.html`,
  `my-students.html`, `teacher-detail.html`, `students.html` show the current
  `student_grade_milestones` grade (Foundation…Grade 8) instead of the
  skill-level bar, editable by teacher/admin the same way skill_level is
  today — except saving writes a new milestone row rather than overwriting a
  single field, so the history builds itself.
- **Student grade & materials history.** A read-only panel (student profile,
  and the student's own dashboard) listing every grade milestone and every
  artefact they've been given by date — the explicit "report historically
  what they've gone through" requirement.

### Status

**Built:**

- Schema (migration #38, `phase6-bok-grading.sql`) plus a correction
  (migration #39, `phase6b-bok-retired-artefact-visibility.sql` — the
  original `bok_artefacts` read policy hid a retired artefact from
  *everyone* but an admin, which silently broke a student's own history the
  moment anything they'd covered was retired; fixed to also allow reading an
  artefact already linked to an occurrence the caller can see).
- Admin **Artefact Library** page (`bok-artefacts.html`, linked from every
  admin page's sidebar under a new "Curriculum" section): add/edit/retire an
  artefact, filter by instrument/grade/component/tag, paste its Drive link.
  Nine grade levels are seeded by the migration; no artefacts are seeded —
  the library starts empty and admins populate it against real Drive content.
- Teacher picker in `dashboard-teacher.html`'s lesson-note modal
  (`openNoteModal()`/`saveNote()`): three multi-select dropdowns grouped by
  component (Repertoire/Songs, Technique, Musical knowledge — chosen over a
  single flat checklist since a grade can have ~15 items per component),
  filterable by grade (defaulted to the student's current grade for a
  private lesson, where one is on record), writing to
  `lesson_occurrence_artefacts`. Shown whenever the occurrence has an
  instrument on record, library-populated or not.
- **"Add your own" (migration #40, `phase6c-bok-teacher-custom-artefacts.sql`).**
  When a student wants to work on a song/technique that isn't in the library
  yet, the teacher adds it themselves from that same picker
  (`openCustomArtefactModal()`/`saveCustomArtefact()`) — title, grade and
  component, same as an admin would. It's saved as a real `bok_artefacts`
  row (`is_custom=true`) so it's correctly attached to that lesson and shows
  in "Materials covered"/history right away, but lands `is_active=false` so
  it isn't offered to other teachers until an admin reviews it. The
  Artefact Library page flags these as "Pending review" (kept visible by
  default — not lumped in with "Show retired") with a pending-count pill by
  the page title, a "Teacher-added only" filter, and "Added by <name>";
  approving one is the same Retire/Reactivate button, relabelled "Approve".
  Teachers can edit their own pending item (fix a typo) but can't activate
  it themselves.
- **Read-only lesson view also shows "Last lesson".** Clicking a lesson
  card opens `openLessonView()`, a separate read-only modal from the note
  editor — it now shows the same "Last lesson" recap (previous occurrence's
  note, shared file, materials) via a shared `fetchPreviousLessonData()` /
  `previousLessonBoxHtml()` pair, plus this occurrence's own picked
  materials, which it never showed before. Everything is fetched before the
  modal body renders (one paint, not a fetch-then-reflow) so opening it
  doesn't flash a bare version first.
- "Materials covered" generated wherever a note reaches a student: the
  emailed note (`notifyStudentOfNote()`), the upcoming-lessons note-box and
  the notes-history tab in `dashboard-student.html` — all three read live
  from `lesson_occurrence_artefacts`, so nothing is typed twice.

- **Grade badge**, replacing the skill-level bar for Guitar students
  everywhere it showed: `dashboard-student.html` (read-only, own progress),
  `teacher-detail.html` (read-only, admin's view of a teacher's roster),
  `my-students.html` (teacher records a new milestone via a small modal —
  always an insert, never overwriting the last one), `students.html` (the
  admin Add/Edit Student modal's instrument row swaps its skill slider for a
  grade select when the row's instrument is Guitar; saving inserts a
  milestone only if the grade actually changed). All four read
  `student_current_grades`. **Not wired:** the CSV bulk-import path in
  `students.html` still only writes `skill_level` — a Guitar student
  imported by CSV needs their grade set afterwards in the edit modal.
- **Student grade & materials history**, on the student's own Progress tab
  (`dashboard-student.html`): every grade milestone by date, and every
  artefact linked to one of their lessons, newest first — both read
  straight from the tables above (`lesson_occurrence_artefacts` needs no
  explicit "my lessons" filter; RLS already scopes it to the caller's own
  occurrences).

Everything above assumes migrations #38, #39 and #40 are run.

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
36. `phase5-schedule-performance-indexes.sql` — indexes on lesson_occurrences/lessons/lesson_students/attendance fixing a "statement timeout" on the teacher schedule view
37. `phase5-occurrence-only-students.sql` — `lesson_students.added_for_occurrence_id`, both views rebuilt; lets an admin add a student to a single occurrence only, without enrolling them in the whole series
38. `phase6-bok-grading.sql` — `bok_grade_levels` (seeded, 9 rows), `bok_artefacts`, `student_grade_milestones`, `lesson_occurrence_artefacts`, `student_current_grades` view, RLS on all four tables — Body of Knowledge / grading framework, milestone 1 (see "Planned" section above)
39. `phase6b-bok-retired-artefact-visibility.sql` — fixes the `bok_artefacts` read policy so a retired artefact stays visible to a teacher/student already looking at a past lesson that used it, instead of vanishing from their history
40. `phase6c-bok-teacher-custom-artefacts.sql` — adds `bok_artefacts.is_custom`, plus RLS letting a teacher insert/update their own pending (`is_active=false`) custom artefact and read it back — lets a teacher add a song/technique that isn't in the library yet, straight from the lesson-note picker

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
