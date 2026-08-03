# Pathfinder Music Lessons — Student Portal
## Technical Specification

**Version:** 1.0
**Date:** 31 July 2026
**Companion documents:** `Requirements_Specification_v0_4.md` (what it does),
`DEPLOYMENT.md` (how to set it up and run it)

---

## 1. Architecture at a glance

```
                        ┌──────────────────────────────┐
   Browser              │  Netlify (static hosting)     │
   ───────              │  /portal/*.html + css + js    │
   Admin  ──────────────▶                               │
   Teacher              └───────────────┬──────────────┘
   Student                              │
       │                                │ /.netlify/functions/*
       │  supabase-js (anon key)        ▼
       │                    ┌──────────────────────────────┐
       │                    │  Netlify Functions (Node)     │
       │                    │  create-user.js               │
       │                    │  send-email.js                │
       │                    │  — hold the service role key  │
       │                    └────────┬───────────┬─────────┘
       │                             │           │
       ▼                             ▼           ▼
┌────────────────────────┐  ┌──────────────┐  ┌──────────────┐
│  Supabase              │  │  Supabase    │  │  Resend      │
│  PostgreSQL + RLS      │◀─│  Admin API   │  │  Email API   │
│  Auth (auth.users)     │  │  (auth mgmt) │  │              │
└────────────────────────┘  └──────────────┘  └──────┬───────┘
                                                     │
                                      ┌──────────────▼───────────────┐
                                      │  Google Workspace            │
                                      │  MX — receives all replies   │
                                      │  info@ is a Group → both     │
                                      │  studio mailboxes            │
                                      └──────────────────────────────┘
```

**No build step.** Static HTML with vanilla JavaScript. No framework, no bundler,
no transpilation. A file edited on disk is the file the browser runs.

**Two trust zones.** The browser holds the *anon* key and is constrained by Row
Level Security. The Functions hold the *service role* key, which bypasses RLS
entirely. Everything requiring elevated privilege lives server-side.

---

## 2. Why each building block exists

| Block | Role | Why not something else |
|---|---|---|
| **Netlify static hosting** | Serves the portal and marketing site | No build step needed; same host as the existing site |
| **Supabase Postgres** | All application data | Relational data with real constraints; RLS gives per-role access without an API layer |
| **Supabase Auth** | Identity and sessions | Bundled with the database; RLS policies can reference `auth.uid()` directly |
| **Netlify Functions** | Server-side operations | The service role key cannot reach the browser; without these, admins would need Supabase dashboard access |
| **Resend** | Outbound email | Gmail SMTP requires an App Password behind 2-Step Verification tied to the studio phone — unusable for admins working remotely |
| **Google Workspace** | Receives mail | Retained; MX records untouched, so replies still arrive normally |
| **Google Drive** | Lesson files | Teachers paste links; no upload or storage burden on the portal |

### 2.1 The design constraint that shapes everything

**Student email addresses live in `auth.users`, not in `profiles`.** Supabase owns
that table and the browser cannot read it. Consequently:

- Any screen showing an email calls a Function (`get-email`) — this is why edit
  modals briefly display "Loading…"
- Notification recipients are resolved **server-side**; the browser sends a
  *description* of the audience ("all students at Kilsyth"), never a list of
  addresses
- Bulk-imported students, who have no auth account at all, need
  `students.email` as a fallback or they are unreachable

---

## 3. Data model

### 3.1 Entity relationships

```
studios ──┬── admins.studio_ids[]
          ├── teachers.studio_ids[]
          ├── teacher_availability.studio_id
          ├── students.studio_id
          └── lessons.studio_id

profiles (1:1 auth.users) ──┬── admins.user_id
                            ├── teachers.user_id
                            └── students.user_id

lessons ──┬── lesson_students ── students        (many-to-many)
          └── lesson_occurrences ──┬── attendance ── students
                                   └── lesson_notes

students ── student_instruments   (skill level per instrument)
```

### 3.2 Three modelling decisions worth understanding

**Lesson membership is a junction table.** `lessons.student_id` could not
represent a group, so `lesson_students` replaced it. The old column remains,
nullable and unread, to avoid data loss. Code written before this change caused
several bugs — anything assuming one student per lesson is stale.

**Attendance is keyed on (occurrence, student).** A group of four produces four
attendance rows. This is what allows one band member to be marked absent.

**Lesson notes are keyed on occurrence only.** Deliberate, and deliberately
inconsistent with attendance: a band note addresses the whole group.

### 3.3 Views

Two views exist because the two audiences need different grains.

| View | Grain | Consumers |
|---|---|---|
| `schedule_view` | one row per **occurrence** | admin, teacher dashboards |
| `student_schedule_view` | one row per **occurrence × student** | student dashboard |

`schedule_view` joins attendance by **subquery, not `LEFT JOIN`**. A join would
fan the view out to one row per student and duplicate every group lesson on the
admin grid.

It exposes three derived columns:

- `student_count` — students on the lesson
- `attendance_marked_count` — attendance rows recorded
- `fully_marked` — true once every student is marked

`attendance_status` is only meaningful where `student_count = 1`; for a group it
is NULL by design, because a group has no single status. **Any query treating a
NULL `attendance_status` as "unmarked" will count every group lesson as unmarked
forever.** This caused a real defect.

### 3.4 Row Level Security

Policies use two helper functions, `get_my_role()` and `get_my_teacher_id()`,
which read the current session.

| Role | Access |
|---|---|
| Super User | Everything |
| Admin | Their accessible studios |
| Teacher | Own lessons; students enrolled in them; those students' profiles and skill levels |
| Student | Own records only |

Teacher access derives from `lesson_students` → `lessons.teacher_id`. It
previously derived from `student_teachers`, which is now unused — when membership
moved, those policies silently matched nothing and teachers saw an empty student
list.

**Known gap:** views run as owner and do not enforce RLS. The frontend always
filters correctly, so no user currently sees another's data — but a view queried
directly with the anon key would return everything. Closing this needs
`security_invoker = on` plus read policies across the underlying tables.

---

## 4. Frontend

### 4.1 Structure

```
portal/
├── login.html              4-role login, forgot password
├── change-password.html    forced on first login, voluntary from nav
│
├── dashboard-admin.html    weekly schedule + stats        (admin, super user)
├── dashboard-teacher.html  own schedule, attendance, notes (teacher)
├── dashboard-student.html  lessons, notes, attendance, progress (student)
│
├── students.html           CRUD + bulk import             (admin, super user)
├── teachers.html           CRUD + availability            (admin, super user)
├── teacher-detail.html     read-only overview             (admin, super user)
├── lessons.html            daily grid, booking, agenda PDF (admin, super user)
├── notifications.html      bulk email composer            (admin, super user)
├── my-students.html        roster + skill grading         (teacher)
├── studios.html            CRUD                           (super user)
├── admins.html             CRUD                           (super user)
│
├── css/portal.css          all styling; design tokens as CSS variables
└── js/supabase-client.js   client init, auth guard, shared helpers
```

Each page is self-contained: its own markup, page-specific CSS in a `<style>`
block, and its own JavaScript. Shared concerns live in the two files above.

### 4.2 `supabase-client.js`

Holds the anon key and the helpers every page depends on.

**Auth guard.** `requireAuth(['admin','superuser'])` runs at the top of each page:
checks the session, loads the profile, verifies the role, and redirects to
`change-password.html` if `must_change_password` is set — which is why a
temporary password cannot be bypassed by navigating directly to a dashboard.

**Date helpers — the important ones.** `toISODate()` builds from local date parts
and `parseLocalDate()` parses as local time. Both exist because
`new Date("2026-07-29")` parses as **UTC midnight**, which in AEST is the previous
day. This caused Wednesday lessons to display on Thursday. `getWeekStart()` sets
noon rather than midnight for the same reason: midnight AEST converts to the
previous day in UTC.

**Formatting.** `formatTime`, `formatDuration`, `formatShortDate`,
`formatLongDate`, `attendancePill`, `skillLabel`, `showToast`.

### 4.3 Patterns worth knowing

**Nested Supabase joins are avoided.** Related tables are fetched separately and
merged in JavaScript. PostgREST rejects filters and ordering on joined columns
(`.order('profiles(last_name)')`, `.eq('profiles.status','active')`), and the
resulting 400s are opaque. Several early failures traced to this.

**Handlers pass identifiers, not objects.** `onclick="openTeacherByIndex(3)"`,
never `onclick="edit(${JSON.stringify(obj)})"`. Serialising an object into an HTML
attribute breaks the moment the data contains a quote — an empty note produced
`""`, which terminated the attribute and silently killed the handler.

**`.maybeSingle()`, not `.single()`,** for existence checks. `.single()` treats
"no rows" as an error.

**Upsert where a row may not exist.** Skill levels are set for instruments taken
from the *lesson*, which may have no matching `student_instruments` row. An
`UPDATE` matched zero rows and reported success while saving nothing.

---

## 5. Netlify Functions

Plain CommonJS using the built-in `fetch`. **No npm dependencies** — nothing to
install, nothing to bundle, no `package.json` required in the functions directory.

### 5.1 `create-user.js`

Four actions, dispatched on an `action` field.

| Action | Purpose |
|---|---|
| `create` | Create an auth user with a generated temporary password; returns 409 with the existing role if the email is taken |
| `get-email` | Look up an email by user ID |
| `reset-password` | Trigger a password reset |
| `delete-user` | Remove the auth account |

**`reset-password` has a trap.** `redirect_to` must be a **query parameter** on
`/auth/v1/recover`. Placed in the body it is silently ignored and Supabase falls
back to the project's Site URL — the user lands on the homepage with an
`otp_expired` fragment, which misleadingly suggests an expiry problem.

Temporary passwords use the readable form `Welcome-4729!` — an admin reads these
aloud or types them into a message.

### 5.2 `send-email.js`

Two actions: `preview` resolves recipients and returns counts without sending;
`send` resolves and sends.

**Recipient modes.** `studios`, `teacher`, `day`, `teacher_date`, `students`,
`occurrence`. The browser sends a mode plus parameters — never addresses.

**Address resolution**, in order, deduplicated case-insensitively:
1. Login email from `auth.users`
2. `students.email` — the fallback for bulk-imported students
3. `parent_email`

Only `active` and `trial` students are included.

**Validation before sending.** Resend's batch endpoint is **all-or-nothing per
chunk** — one malformed address rejects every email in that batch. Addresses are
therefore validated first, and anything invalid is skipped and reported by name.
Without this, a single typo among 500 imported students would block a hundred
emails with no indication of the cause. Resend also rejects `example.com` and
similar reserved test domains.

**Studio copy.** Single-recipient sends BCC the studio. Bulk sends produce **one
summary email** instead, listing the message, every recipient, and anyone skipped.
500 BCC copies would be unreadable.

**Templating.** `{{placeholder}}` substitution in subject and body. A paragraph
wrapped entirely in `**asterisks**` renders as a highlighted callout block;
`**bold**` works inline.

**Logging.** Every send writes to `email_log`, including each recipient's Resend
message ID, so delivery status can be looked up later. Logging failures never
block a send.

---

## 6. Email architecture

### 6.1 Two systems, one domain

| | Notifications | Auth emails |
|---|---|---|
| Sent by | `send-email.js` → Resend API | Supabase Auth → Resend SMTP |
| From | The studio's own address | `info@` |
| Templates | In `send-email.js` | Supabase dashboard |
| Limit | Resend plan (free = 100/day) | 30/hour, configurable |

Routing Supabase Auth through Resend's SMTP removed the 2/hour cap and the
"Powered by Supabase" branding. The trade-off: **a Resend outage now blocks
password resets as well as notifications.** The fallback is setting a password
directly in the Supabase dashboard.

### 6.2 DNS

Resend and Google Workspace coexist because their records sit on different
hostnames:

| Record | Host | Purpose |
|---|---|---|
| TXT | `resend._domainkey` | Resend DKIM |
| TXT | `google._domainkey` | Google DKIM |
| MX | `send` | Resend bounce handling |
| TXT | `send` | Resend SPF — **subdomain only** |
| MX | apex | Google — receives all mail |
| TXT | apex | Google SPF — **untouched** |
| TXT | `_dmarc` | `p=none` |

**Never add a second SPF record to the same hostname.** Two SPF records on one
host break authentication for both systems. Two on *different* hosts, as here, is
correct and normal.

DKIM is signed on the root domain, so mail sent via Resend authenticates as
`pathfindermusiclessons.com.au` and passes DMARC even though the bounce path runs
through the `send` subdomain — DMARC passes if *either* SPF or DKIM aligns.

`info@` is a **Google Group** containing both studio mailboxes, which is why it
appears nowhere under Users. Replies reach whichever studio is working.

---

## 7. Recurring lessons

A lesson is a **pattern** (day, time, duration, recurrence); occurrences are
**generated rows** in `lesson_occurrences`.

| Recurrence | Generated |
|---|---|
| Indefinite | 52 weeks ahead |
| Fixed count | Exactly that many |
| Date range | Until the end date |

Cancellation has three scopes, and they differ in more than reach:

| Scope | Occurrences | `lessons.status` | Grid |
|---|---|---|---|
| Single | This one → cancelled | unchanged | Shows with a red ✕ |
| This + future | From here → cancelled | **cancelled** | Hidden from here; earlier remain |
| Entire series | From **today** → cancelled | **cancelled** | Same |

Setting `lessons.status` matters beyond display: **clash detection only considers
active lessons**, so without it the slot stays blocked and cannot be rebooked.

"Entire series" deliberately starts from today rather than the beginning — past
occurrences are history and may already carry attendance records.

---

## 8. Booking constraints

All hard blocks, validated before insert:

| Constraint | Check |
|---|---|
| Teacher double-booking | Any overlapping active lesson on that weekday |
| Student double-booking | Any overlapping lesson containing that student |
| Group capacity | Maximum 6 |
| Teacher instrument | Instrument must be in `teachers.instruments` |
| Teacher availability | Must fall inside a `teacher_availability` slot for that studio and day |
| Availability overlap | Slots for one teacher cannot overlap on a day, at the same or different studios |

The booking form filters the instrument and studio dropdowns to the selected
teacher, so invalid combinations are hard to reach; the blocks are the backstop.

Time comparison converts `HH:MM:SS` to minutes and tests
`newStart < existingEnd && newEnd > existingStart`.

---

## 9. Conventions to preserve

**"Past" means the lesson has ended**, not that the date is before today. A lesson
in progress has not happened yet. All three dashboards use the same test, and the
student attendance rate depends on it.

**Attendance rate is present ÷ lessons ended**, so unmarked counts against the
student. Chosen over "present ÷ marked", which hid the gap. The consequence is
that late marking briefly worsens students' rates — which is also the incentive
to mark promptly.

**Group lessons show progress, not status.** "2 of 4 marked", never a single pill.

**Errors are surfaced, not swallowed.** Multi-step writes check each result; a
failed second write would otherwise leave inconsistent data behind a success
message.

---

*Prepared for Pathfinder Music Lessons · pathfindermusiclessons.com.au*
