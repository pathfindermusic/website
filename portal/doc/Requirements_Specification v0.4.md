# Pathfinder Music Lessons — Student Portal
## Project Requirements Document

**Version:** 0.4
**Date:** 31 July 2026
**Status:** Built and in testing — reflects what has actually been implemented

**Change Summary from version 0.3:**

This revision brings the specification into line with what was built. Most changes
came from testing rather than a change of mind, and the reasoning is recorded so
the decisions don't get quietly reversed later.

| # | Change | Why |
|---|---|---|
| 1 | Teacher availability is now a **hard block**, not a soft warning | Testing produced impossible schedules — teachers booked at studios they don't work at, teaching instruments they don't teach. Reverses open question 4. |
| 2 | Email moved from **Gmail SMTP to Resend**, and from plain text to branded HTML | Gmail App Passwords require 2-Step Verification tied to a phone kept at the studio; admins working from home couldn't send. Resend needs no device. |
| 3 | Attendance is recorded **per student**, not per lesson occurrence | A student absent from a band lesson could not be recorded. |
| 4 | Lesson notes remain **per occurrence** and shared across a group | Deliberate: band notes address the whole group. |
| 5 | Notification scenarios expanded from 4 to **7** | Added teacher→student messages, automatic notes notification, automatic cancellation notice. |
| 6 | Lesson membership moved to a **`lesson_students` junction table** | `lessons.student_id` cannot represent a group. |
| 7 | Students carry a **contact email** independent of their login | Bulk-imported students have no auth account and were silently unreachable by every notification. |
| 8 | Bulk sends produce **one studio summary email**, not one BCC per student | 500 BCC copies would bury the studio inbox. |
| 9 | Default schedule view is **Daily**; a date picker supplements week navigation | As specified in v0.3, plus the picker added after testing. |
| 10 | Portal is served from **`/portal/`** on the main domain, not a subdomain | Simpler hosting; one Netlify site. |
| 11 | Attendance rate defined as **present ÷ lessons that have ended** | Needed a definition once students could see the number. |
| 12 | Two requirements **deferred** (see §11) | The 7-day marking rule and the 5-day unmarked reminder need scheduled jobs. |

---

## 1. Project Overview

### 1.1 Background
Pathfinder Music Lessons operates two studios in Kilsyth and Ringwood, Victoria,
with plans to open two more. We currently use MyMusicStaff for scheduling,
attendance and lesson notes but cannot integrate it with Zoho CRM or with Google
Drive, where lesson recordings and large files are stored. A custom portal gives
full control and a unified way to manage students and lessons.

### 1.2 Goals
- Replace MyMusicStaff with a portal we own and control
- Give teachers a simple way to mark attendance, write lesson notes, and track
  skill levels per instrument
- Give students and parents visibility of lessons, practice notes, attendance and
  shared Google Drive files
- Give admins a central place to manage students, teachers and lessons across
  their assigned studios
- Give the Super User full control over studios, admins and system-wide settings

### 1.3 Out of scope (v1)
- Zoho CRM API integration — bulk import via SQL migration instead
- Online lesson booking by students
- Payment processing
- Native mobile app — mobile-responsive web is sufficient
- Multiple roles per person (see §11)

> **Changed from v0.3:** "Branded email notifications" was listed as out of scope.
> It is now delivered — moving to Resend made branded HTML the path of least
> resistance rather than an extra.

---

## 2. Users & Roles

Each account holds **exactly one role**. A person who both teaches and administers
needs a separate email address per role. See §11.

### 2.1 Super User
One designated Super User. Everything an Admin can do, plus:
- Add, edit, deactivate and delete Admin accounts
- Restrict which studios each Admin can access
- Add, edit, deactivate and delete studios — dynamic, no code change needed
- Full visibility across all studios at all times

### 2.2 Admin
Up to 5 studio admins, each potentially spanning multiple studios.
- Add, edit, deactivate and delete students and teachers
- Manage teacher availability
- Create, edit and cancel lessons — **blocked**, not warned, on a clash or an
  availability conflict
- View all attendance and lesson notes across accessible studios
- Send email notifications to students (§3.9)
- Generate a teacher's Agenda PDF for a given date
- Import students in bulk (§5.3)

**Default view** is Daily: a grid per studio with teachers as columns and 30-minute
blocks as rows. A cell shows the student's name, or for a group lesson the number
of students; clicking reveals the full roster. Lessons spanning multiple blocks
merge vertically. Clicking an empty cell opens the booking form pre-filled with
that teacher, studio, day and time.

| | **Adele Long** |
|---|---|
| **3:30–4:00 PM** | **Arjun Roberts** <br>Private · Guitar |
| **4:00–5:00 PM** | **4 students** <br>Group · Band |

A Weekly view is available via toggle, and a date picker jumps to any date.

### 2.3 Teacher
Up to 20 instrumental and vocal teachers.
- View their own schedule, defaulting to Daily, with the previous lesson's notes
- Mark attendance — **per student** for group lessons
- Write and edit lesson notes after each session
- Update skill level per instrument for their own students (0–8)
- Share Google Drive links with students
- **Email an individual student** (added in v0.4)
- View a read-only summary of any lesson, including the full group roster

**Cannot:** see other teachers' students, notes or schedules; see student phone
numbers or email addresses.

### 2.4 Student (or Parent/Guardian)
Up to 500. One login per student — the parent's email for minors, the student's
own for adults.
- View their upcoming lessons
- Read lesson notes
- View their own attendance history and attendance rate
- Access Google Drive links shared by their teacher

**Cannot:** book or cancel lessons; see other students' data; see who else is in
a group lesson.

---

## 3. Functional Requirements

### 3.1 Authentication
- [x] Login with email and password
- [x] Role-based access: Super User / Admin / Teacher / Student
- [x] "Remember me"
- [x] Password reset by email — self-service from the login page, or initiated by
      an admin from the Students, Teachers or Admins page
- [x] Session timeout after 5 hours of inactivity
- [x] Temporary password must be changed at first login — enforced on every page,
      not just at login
- [x] Any user can change their own password at any time

### 3.2 Schedule
- [x] Super User sees all lessons across all studios
- [x] Admin sees all lessons across accessible studios, filterable by studio and status
- [x] Teacher sees only their own lessons
- [x] Student sees only their own lessons
- [x] **Default view: Daily**, with a Weekly toggle *(changed from v0.3, which said weekly)*
- [x] Navigate by day or week, jump to today, or **pick any date** *(new in v0.4)*
- [x] A cancelled **occurrence** within a running series shows with a red ✕ and its
      slot is bookable
- [x] A cancelled **series** disappears from the schedule from the cancellation
      point onwards; earlier occurrences remain as history *(clarified in v0.4)*
- [x] Lesson card shows time, duration, student or group size, instrument,
      teacher, studio, lesson type and attendance state
- [x] **Booking is blocked** where the teacher is unavailable *(changed from v0.3)*

### 3.3 Attendance
- [x] Four statuses: **Present**, **Absent — No Makeup Credit**,
      **Absent — Notice Given**, **Teacher Cancelled**
- [x] **Recorded per student per occurrence** *(changed from v0.3)*. Private lessons
      mark inline; group lessons open a modal listing each student separately
- [x] A group lesson shows "2 of 4 marked" until everyone is recorded
- [x] Admin can edit any attendance record
- [x] Student can view their own attendance history
- [x] **Unmarked attendance count** on the teacher, teacher-detail and admin
      dashboards, counting lessons that have **ended** but aren't fully marked
- [x] **Attendance rate = present ÷ lessons that have ended** *(new in v0.4)*.
      Unmarked counts against the student — deliberately, so the gap is visible
      rather than hidden. A lesson in progress is not yet counted.
- [ ] Attendance must be marked within 7 days — **deferred**, see §11
- [ ] Email to admin if unmarked after 5 days — **deferred**, see §11

### 3.4 Lesson Notes
- [x] Plain-text note per lesson occurrence, editable at any time
- [x] Student can read notes for their own lessons immediately
- [x] Admin can read all notes across accessible studios
- [x] Clickable Google Drive link in a dedicated field
- [x] **Notes are shared across a group lesson** — one note, visible to every
      student in that lesson *(clarified in v0.4)*
- [x] Saving a note **automatically emails the student** *(new in v0.4)*

### 3.5 Student Management (Admin + Super User)
- [x] Add, edit, deactivate and delete students
- [x] Duplicate email detection with a clear message naming the existing role
- [x] Temporary password shown in a copyable modal on account creation
- [x] Bulk import (§5.3)
- [x] **Contact email stored on the student record** *(new in v0.4)* — students
      imported in bulk have no login account, and without this are unreachable
      by every notification
- [x] Instruments and skill levels, up to 5 per student
- [x] Parent name, phone and email for minors

### 3.6 Teacher Management (Admin + Super User)
- [x] Add, edit, deactivate and delete teachers
- [x] Name, email, phone, instruments, studios, availability, teaching room,
      virtual room link
- [x] Teaching room defaults to `Studio Name - FirstName's Room`
- [x] **Availability slots are validated** — overlapping slots on the same day are
      rejected, whether at the same studio or two different ones *(new in v0.4)*
- [x] **Teacher detail page** *(new in v0.4)*: profile, availability laid out by day,
      weekly schedule with its own date picker, student list with skill levels, and
      stats for active students, lessons this week and unmarked attendance

### 3.7 Lesson Management (Admin + Super User)
- [x] A lesson has: teacher, studio, instrument, day, time, duration, type
- [x] Type is **Private (1 student)** or **Group (up to 6)**
- [x] **Band is always a group lesson** — selecting it forces the type *(new in v0.4)*
- [x] Students are added to a group **incrementally**, including after the series
      has started
- [x] Recurrence: indefinite, fixed number of occurrences, or between two dates
- [x] Series notes and per-occurrence notes, e.g. *"Makeup for 20 July"*
- [x] Cancel a single occurrence, this and all future, or the whole series
- [x] Cancelling this-and-future **ends the series and frees the slot** for
      rebooking *(clarified in v0.4)*
- [x] Cancelling the whole series does **not** rewrite past occurrences
- [x] Durations: 30 / 60 / 90 / 120 minutes, defaulting to 30
- [x] Studios are dynamic — Kilsyth and Ringwood pre-loaded

**Booking constraints — all hard blocks:**
- [x] A student can be in only one lesson at a time
- [x] A teacher can teach only one lesson at a time
- [x] A group lesson cannot exceed 6 students
- [x] **A teacher can only be booked at a studio and time they are available**
      *(changed from soft warning)*
- [x] **A teacher can only be booked for an instrument they teach** *(new in v0.4)*

The booking form filters the instrument and studio dropdowns to the selected
teacher, so invalid combinations are difficult to reach in the first place; the
blocks are the backstop.

### 3.8 Skill Level / Grading (Teacher)
- [x] Per instrument, 0–8: **Beginner 0–3**, **Intermediate 4–6**, **Advanced 7–8**
- [x] Different levels on different instruments
- [x] Stored on the student–instrument relationship
- [x] Instruments a teacher grades come from the lessons they teach; a level can
      be set even where no prior record exists

### 3.9 Email Notifications
*Substantially expanded in v0.4 — v0.3 listed four admin scenarios; there are now
seven, three of them automatic.*

**Admin-initiated:**
1. All students at one or more studios
2. All students of a teacher
3. All students with lessons on a given weekday
4. Students of a teacher on a specific date

**Teacher-initiated:**
5. A message to one of their own students

**Automatic:**
6. Student notified when a teacher saves a lesson note
7. Student notified when a lesson is cancelled — wording differs for a single
   occurrence versus an ongoing series

**Delivery rules:**
- [x] Sent via **Resend** *(changed from Gmail SMTP)*, from the studio's own address
- [x] **Branded HTML** *(changed from plain text)*, matching the portal
- [x] Each recipient receives an **individual email** — no shared recipient lists
- [x] Where a student has a parent email, **both** addresses receive it
- [x] Placeholders: `{{first_name}}`, `{{student_name}}`, `{{instrument}}`,
      `{{teacher_name}}`, `{{lesson_time}}`, `{{lesson_day}}`, `{{lesson_weekday}}`,
      `{{studio}}`
- [x] A paragraph wrapped in `**asterisks**` renders as a highlighted callout
- [x] Recipient count and sample shown before sending, with a confirmation step
- [x] Students with a missing or malformed address are **skipped and reported**,
      not silently dropped
- [x] **Single-recipient sends BCC the studio. Bulk sends produce one summary
      email** listing everything sent, who received it and who was skipped
      *(changed from v0.3's per-message BCC)*
- [x] Replies reach the studio inbox — MX records remain with Google Workspace
- [x] Every send is recorded in `email_log`, including each recipient's Resend
      message ID for later delivery lookup

---

## 4. Non-Functional Requirements

### 4.1 Performance
- Up to 25 concurrent users without degradation
- Pages load within 3 seconds on standard broadband

### 4.2 Devices & Browsers
- Desktop: Chrome, Edge, Safari, Firefox
- Mobile-responsive — teachers marking attendance on a phone is a primary case
- No native app

### 4.3 Security
- HTTPS throughout
- Passwords hashed by Supabase Auth, never stored in plain text
- Role-based access enforced by Row Level Security
- The Supabase **service role key** is held only in server-side environment
  variables and never reaches the browser
- Student contact details are not visible to teachers
- **Open item:** database views do not currently enforce RLS (§11)

### 4.4 Availability
- Target 99% uptime
- Maintenance outside studio hours

---

## 5. Data Model

### 5.1 Tables

| Table | Key fields | Changed in v0.4 |
|---|---|---|
| **studios** | id, name, address, email, status | |
| **profiles** | id, first_name, last_name, phone, role, status, must_change_password | `must_change_password` added; **email lives in `auth.users`, not here** |
| **admins** | id, user_id, studio_ids[] | |
| **teachers** | id, user_id, instruments[], studio_ids[], virtual_room_link, teaching_room | `teaching_room` added |
| **teacher_availability** | id, teacher_id, studio_id, day_of_week, start_time, end_time | |
| **students** | id, user_id, studio_id, **email**, parent_name, parent_phone, parent_email, status | `studio_id` and `email` added |
| **student_instruments** | id, student_id, instrument, skill_level | |
| **lessons** | id, teacher_id, studio_id, instrument, lesson_type, max_students, day_of_week, start_time, duration_mins, recurrence_*, series_notes, status | `lesson_type`, `max_students`, `series_notes` added; **`student_id` deprecated** |
| **lesson_students** | id, lesson_id, student_id, joined_at | **New** — replaces `lessons.student_id` |
| **lesson_occurrences** | id, lesson_id, date, status, is_online, occurrence_notes | `occurrence_notes` added |
| **attendance** | id, lesson_occurrence_id, **student_id**, status, marked_at, marked_by | `student_id` added; unique key is now (occurrence, student) |
| **lesson_notes** | id, lesson_occurrence_id, teacher_id, note_text, drive_link, timestamps | Unchanged — deliberately per occurrence |
| **email_log** | id, sent_at, sent_by, subject, body, recipient_mode, recipient_count, recipients, bcc, status | **New** |
| ~~**student_teachers**~~ | — | **Deprecated.** Teacher–student links are now derived from `lesson_students`. |

### 5.2 Views

| View | Grain | Used by |
|---|---|---|
| **schedule_view** | one row per occurrence | admin and teacher dashboards |
| **student_schedule_view** | one row per occurrence × student | student dashboard |

`schedule_view` exposes `student_count`, `attendance_marked_count` and
`fully_marked`. Its `attendance_status` is meaningful only for single-student
lessons — a group cannot have one status.

### 5.3 Initial data load
- ~500 students imported via `zoho-migration.sql`. Zoho CRM covers only students
  who arrived through enquiry; walk-ins enrolled directly in MyMusicStaff are not
  in Zoho and need adding separately. MyMusicStaff exports PDF only.
- The import runs a **pre-flight check** for missing names, missing or malformed
  emails, duplicate emails, duplicate names, unrecognised studios and invalid
  statuses — all before any record is created.
- Imported students receive **no login account**. They remain contactable via
  `students.email`; an account is created on demand when portal access is needed.
- ~20 teachers entered manually
- Lesson schedule entered manually at launch

> **Changed from v0.3:** CSV import through the portal UI exists but is untested.
> Bulk import is done by SQL migration, which allows validation before writing.

---

## 6. Design & Branding
- Dark charcoal nav, orange accent `#E8491E`, Inter font
- `Logo_-_long.png` in the portal header
- Notification emails use the same palette

---

## 7. Technical Stack

| Layer | Technology | Changed |
|---|---|---|
| Frontend | HTML / CSS / vanilla JS on Netlify | |
| Database, auth, API | Supabase (PostgreSQL + RLS) | |
| Server-side operations | Netlify Functions | Needed for anything requiring the service role key |
| **Email** | **Resend** | **Was Gmail SMTP** |
| Auth emails | Supabase Auth via Resend SMTP | Removes the 2/hour cap and Supabase branding |
| File storage | Google Drive links | |
| Zoho CRM | SQL migration | Was CSV upload |

### 7.1 Why Netlify Functions exist
Student emails live in `auth.users`, which the browser cannot read. Creating auth
users, resolving notification recipients and sending email all require the service
role key, which must never reach the browser.

### 7.2 Hosting
- **`www.pathfindermusiclessons.com.au/portal/`** *(changed from a subdomain)*
- Same Netlify site as the marketing pages

---

## 8. Open Questions — Resolved

| # | Question | Answer | Changed |
|---|---|---|---|
| 1 | Super User — one or many? | One | |
| 2 | Admin — one or multiple studios? | Multiple | |
| 3 | Multiple instruments? | Multiple lessons, multiple teachers | |
| 4 | Teacher availability — informational or enforced? | **Enforced — hard block** | **Changed from soft warning** |
| 5 | Email — branded or plain text? | **Branded HTML via Resend** | **Changed from plain text via Gmail** |
| 6 | Studios — hardcoded or dynamic? | Dynamic | |
| 7 | Skill level per instrument, 0–8? | Yes | |
| 8 | Virtual room link visible to students? | Profile, plus notification emails | |
| 9 | Parent login — shared or separate? | Shared, one email per student | |
| 10 | Group lessons — all students at once or incrementally? | **Incrementally** | New |
| 11 | Clash detection — hard block or override? | **Hard block** | New |
| 12 | Group attendance — per group or per student? | **Per student** | New |
| 13 | Group lesson notes — per group or per student? | **Per group, shared** | New |
| 14 | Attendance rate — how calculated? | **Present ÷ lessons ended; unmarked counts against** | New |

---

## 9. Acceptance Criteria

- [x] All four roles log in and are restricted appropriately
- [x] A teacher marks attendance and writes a note; the student sees both immediately
- [x] An admin creates a recurring lesson; it appears in teacher and student schedules
- [x] A cancelled occurrence shows with a red ✕; a cancelled series disappears from
      the cancellation point while earlier lessons remain
- [x] Booking a teacher outside their availability is **blocked**
- [x] Booking a teacher for an instrument they don't teach is **blocked**
- [x] A student or teacher double-booking is **blocked**
- [x] An admin emails a filtered group of students; each receives an individual,
      personalised email and the studio receives one summary
- [x] A group lesson records attendance per student
- [x] Skill level is updated per instrument and appears on the student's dashboard
- [x] Google Drive links are clickable for the student
- [x] Super User can add a studio and assign an admin
- [ ] 500 students import without errors — pre-flight check built, full import pending
- [ ] Fully usable on Chrome mobile — responsive but not yet tested on a phone

---

## 10. Build Status

| Phase | Scope | Status |
|---|---|---|
| Phase 1 | Supabase setup, auth and roles, schedule per role, studios, availability | ✅ Complete |
| Phase 2 | Attendance, notes, Drive links, skill grading, student and teacher management | ✅ Complete |
| Phase 3 | Email notifications, bulk import, admin dashboard, Super User controls | ✅ Complete |
| Remaining | Attendance report, view-level RLS, mobile testing, production import | ⏳ Outstanding |

---

## 11. Deferred and Outstanding

### Deferred — need scheduled jobs
Both require a scheduled task, which the current architecture has no mechanism
for. Supabase `pg_cron` or a Netlify scheduled function would be the route.

- **Attendance must be marked within 7 days** (v0.3 §3.3). Nothing currently
  enforces or expires this. The unmarked count is the interim substitute.
- **Email to admin when attendance is unmarked after 5 days** (v0.3 §3.3).

### Outstanding before go-live

| Item | Note |
|---|---|
| **RLS on views** | `schedule_view` and `student_schedule_view` run as owner and do not enforce row-level security. The frontend always filters correctly, so no user currently sees another's data — but the views would return it if queried directly with the anon key. Needs `security_invoker` plus read policies on the underlying tables. **Treat as a blocker.** |
| **Attendance report page** | Sidebar link exists; page not built. Must be written against per-student attendance. |
| **Mobile testing** | Responsive but never tested on a phone, despite teachers marking attendance being a primary use case. |
| **Production import** | Pre-flight check ready; the real import has not run. |
| **Resend paid tier** | Free tier allows 100 emails/day. A studio-wide announcement to 500 students exceeds it. |

### Known limitations

| Item | Note |
|---|---|
| **One role per account** | Roughly 3 staff both teach and administer. Workaround is a second email address. Proper fix is `role` → `roles[]` with matching RLS and login changes. |
| **Email history page** | Every send is logged with Resend message IDs, but there is no page to view it. Per-recipient delivery and bounce status would want Resend webhooks. |
| **Teacher Lesson Notes page** | Notes are reachable from the schedule; a dedicated page was removed rather than left broken. |
| **CSV import via portal UI** | Exists, untested. Bulk import uses the SQL migration. |
| **`lessons.student_id`** | Nullable legacy column, nothing reads it. Left in place to avoid data loss. |

---

*Document prepared for Pathfinder Music Lessons · pathfindermusiclessons.com.au*
*Version 0.4 — revised 31 July 2026 to reflect the delivered system*
