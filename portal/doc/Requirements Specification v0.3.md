# Pathfinder Music Lessons — Student Portal
## Project Requirements Document

**Version:** 0.3  
**Date:** 27 July 2026  
**Status:** Draft — Under Review
**Change Summary from version 0.2:
- Added details for lessons, such as lesson types (e.g. private or one-on-one vs group)
- "Band" as a new "Instrument" taught by teacher or available for lesson booking. We currently have "Other" option that can be used, but it's preferred to have "Band" explicityly listed as an available option
- Added constraints of lessons booking, such as a a student can be in only one lesson at a time or a teacher can only be teaching a lesson at a time, etc.
- Added new requirement for Daily view in addition to Weekly view of Schedule for Admins and Teachers
- Default view of schedule for Admins and Teachers to be Daily, with an option to switch to Weekly view
- Added new requirement on creating agenda in PDF format

---

## 1. Project Overview

### 1.1 Background
Pathfinder Music Lessons operates two studios in Kilsyth and Ringwood, Victoria, with plans to open two more in the near future. We currently use MyMusicStaff to manage scheduling, attendance and lesson notes but cannot integrate it with our Zoho CRM and Google Drive where we store lesson recordings and large files for students. A custom portal gives us full control and a simpler, unified way to manage students and their lessons.

### 1.2 Goals
- Replace MyMusicStaff with a portal we own and control
- Give teachers a simple way to mark attendance, write lesson notes, and track student skill levels per instrument
- Give students (or their parents) visibility of their upcoming lessons, practice notes, and shared Google Drive files
- Give admins a central place to manage students, teachers and lessons across their assigned studios
- Give the Super User full control over studios, admins, and system-wide settings

### 1.3 Out of Scope (v1)
- Zoho CRM integration (manual CSV upload instead — daily export by admin)
- Online lesson booking by students
- Payment processing
- Native mobile app (mobile-responsive web is sufficient)
- Branded email notifications (plain text via Gmail is sufficient)

---

## 2. Users & Roles

### 2.1 Super User
**Who:** One designated Super User (the ultimate administrator)  
**Can do everything an Admin can, plus:**
- Add, edit and deactivate Admin accounts
- Restrict which studios each Admin has access to (an Admin can span multiple studios)
- Add, edit and delete studios (studios are dynamic — new studios can be added without a code change)
- Full visibility across all studios at all times

### 2.2 Admin
**Who:** Studio admins — up to 5, each potentially spanning multiple studios  
**Can do:**
- Add, edit and deactivate students
- Add, edit and deactivate teachers
- Add, edit and delete teacher shifts/availability
- Create, edit and cancel lessons (with soft warning if lesson falls outside teacher's availability)
- View all attendance and lesson notes across their accessible studios
- Customise dashboard view by studio and/or teacher — default view on login shows today's schedule for their studio(s)
- Send plain-text email notifications to students using various criteria:
  - All students across all studios
  - Students of a selected studio
  - Students of a selected teacher on a selected day
- Include a teacher's virtual room (e.g. Zoom) link in a notification email when a student switches to an online lesson
- Upload new students from a CSV export (using a predefined template)
- Create an Agenda PDF for a teacher for a selected date. The Agenda contains the Teacher's name and the date as headings followed by line items of timeslot (e.g. 3-30:PM), Student's name, lesson type (Private or Group), location (teacher's teaching room or Zoom link).
- Default dashboard view is Daily presented in a grid of Teachers' names at the top and timeslots of blocks of 30-minutes on the left, while each cell has the student's name or if it's a group or band lesson, the number of students and on click will reveal the students' names. Something like this:



  |             | **Adele Long**                       |
  |-------------|--------------------------------------|
  | **3:30-4:00 PM** | **Arjun Roberts** <br>Private lesson |
  | **4:00-4:30 PM** | **4 Students** <br>Group lesson      |
  | **4:30-5:00 PM** | Merge with cell above (not sure how to do it)              |
  |||

### 2.3 Teacher
**Who:** Instrumental and vocal music teachers — up to 20  
**Can do:**
- View their own lesson schedule, default view is Daily showing students in time order with the notes from the last lessons. A Teacher can switch to weekly view, navigate forward/back for an overview of scheduled lessons only
- Mark attendance for each lesson
- Write and edit lesson notes after each session
- Update skill level/grading per instrument for each of their students (0–8 scale)
- Share Google Drive links (clickable URLs) with their students via the lesson notes or a dedicated field

**Cannot do:**
- See other teachers' students, notes or schedules
- See students' contact details (phone number or email address)

### 2.4 Student (or Parent/Guardian)
**Who:** Students or their parents/guardians — up to 500. One shared login per student using a single registered email address (parent's email for minors, student's own email for adults)  
**Can do:**
- View their own upcoming lesson schedule
- Read lesson notes written by their teacher
- View their own attendance history
- Access Google Drive links shared by their teacher

**Cannot do:**
- Book or cancel lessons
- See other students' data

---

## 3. Functional Requirements

### 3.1 Authentication
- [x] Login with email and password
- [x] Role-based access: Super User / Admin / Teacher / Student
- [x] "Remember me" on login
- [x] Password reset via email, Admin can initiate a PW change upon request
- [x] Session timeout after 5 hours of inactivity
- [x] Must change the temporary password after at the first login


### 3.2 Schedule
- [x] Super User sees all lessons across all studios
- [x] Admin sees all lessons across their accessible studios, filterable by studio / teacher / date
- [x] Teacher sees only their own lessons
- [x] Student sees their own upcoming lessons
- [x] Default view: weekly, starting today — navigate forward/back by week
- [x] Cancelled lessons shown greyed out (not hidden)
- [x] Lesson card shows: time, duration, student name, instrument, teacher, studio, lesson type
- [x] Admin is warned (soft warning, not blocked) if a lesson is scheduled outside a teacher's stated availability

### 3.3 Attendance
- [x] Teacher can mark each lesson with one of four statuses:
  - **Present**
  - **Absent — No Makeup Credit**
  - **Absent — Notice Given**
  - **Teacher Cancelled**
- [x] Admin can edit any attendance record
- [x] Student can view their own attendance history
- [x] Attendance must be marked within 7 days of the lesson date
- [x] Admin receives a notification (email) if attendance has not been marked within 5 days of the lesson

### 3.4 Lesson Notes
- [x] Teacher can write a plain-text note after each lesson
- [x] Teacher can edit their own notes at any time
- [x] Student can read notes written for their own lessons immediately after saving
- [x] Admin can read all lesson notes across their accessible studios
- [x] No rich text formatting required — plain text only
- [x] Teacher can include a clickable Google Drive link within a lesson note or in a dedicated link field

### 3.5 Student Management (Admin + Super User)
- [x] Add a new student manually
- [x] Import students from a CSV file using a predefined template
- [x] Edit student details
- [x] Deactivate a student (hidden from active lists, record preserved)
- [x] Assign a student to one or more teachers (one per instrument)
- [x] View a student's full lesson history, attendance records and notes
- [x] Send plain-text email notifications to students using criteria:
  - All students across all studios
  - Students of a selected studio
  - Students of a selected teacher
  - Students of a selected teacher on a selected day

### 3.6 Teacher Management (Admin + Super User)
- [x] Add a new teacher
- [x] Edit teacher details: name, email, instruments taught, studios, availability (days of week + hours per studio), teaching room being a phisical room at a studio (default room name: Studio Name + " - " + Teacher's first name's "Room", e.g. Ringwood - Dave's room or virtual room link
- [x] Deactivate a teacher (hidden from active lists, record preserved)
- [x] View a teacher's full schedule and student list

### 3.7 Lesson Management (Admin + Super User)
- [x] Each lesson has: student, instrument, teacher, studio, day, time, duration
- [x] Lesson type can be: Private (1:1) or Group of up to 6 students to cater for Band lesson
- [x] Create a recurring weekly lesson — recurring options:
  - Indefinite (until manually cancelled)
  - Fixed number of occurrences
  - Between a start and end date
- [x] Edit or cancel a single occurrence of a recurring lesson
- [x] Edit or cancel all future occurrences of a recurring lesson
- [x] Supported lesson durations: 30 min / 60 min / 90 min / 120 min
- [x] Studios are dynamic (managed by Super User) — Kilsyth and Ringwood pre-loaded at launch
- [x] A student can only be in one class/with one teacher at a time
- [x] A teacher can teach only one student in a private lesson and up to 6 students in a group lesson or a band lesson 
- [x] A teacher can teach only one class at a time
- [x] A place/field to add scheduling notes like "Joe is having a makeup lesson for 20 July 2026"
- [x] Cancelled lessons are to be shown on dashboard with an indication, e.g. red X icon. The timeslot of a cancelled lesson is considered available for a new booking


### 3.8 Skill Level / Grading (Teacher)
- [x] Teachers can update a student's skill level per instrument
- [x] Scale: 0–8 numeric, mapping to three bands:
  - **Beginner:** 0–3
  - **Intermediate:** 4–6
  - **Advanced:** 7–8
- [x] A student can have different levels on different instruments (e.g. Beginner in singing, Intermediate in bass, Advanced in guitar)
- [x] Skill level is stored on the student–instrument relationship, not on the student record itself

### 3.9 Email Notifications (Admin)
- [x] Admin can compose and send a plain-text email notification to a selected group of students
- [x] Selection criteria: all students / by studio / by teacher / by teacher + day
- [x] Sent via the studio's Gmail account (no third-party email service required in v1)
- [x] Admin can optionally include a teacher's virtual room link when notifying a student of an online lesson

---

## 4. Non-Functional Requirements

### 4.1 Performance
- The system should support up to 25 concurrent users without degradation
- Pages should load within 3 seconds on a standard broadband connection

### 4.2 Devices & Browsers
- Must work on desktop: Chrome, Safari, Firefox
- Must be usable on mobile (teachers marking attendance on their phone is a primary use case)
- No native app required — mobile-responsive web is sufficient

### 4.3 Security
- All data transmitted over HTTPS
- Passwords stored as hashed values — never plain text (handled by Supabase Auth)
- Each user can only access data permitted by their role — enforced at database level via Supabase Row Level Security (RLS)
- Student contact details (phone, email) not visible to teachers

### 4.4 Availability
- Target: 99% uptime (Supabase and Netlify free tiers both exceed 99%)
- Planned maintenance outside studio hours: before 9:00am or after 9:00pm AEST

---

## 5. Data Model

### 5.1 Tables

| Table | Key fields |
|---|---|
| **studios** | id, name, address, email (Gmail), status |
| **users** | id, first_name, last_name, email, phone, role, status, remember_token |
| **admins** | id, user_id, studio_ids[] (array of accessible studios) |
| **teachers** | id, user_id, virtual_room_link, studio_ids[] |
| **teacher_availability** | id, teacher_id, studio_id, day_of_week, start_time, end_time |
| **students** | id, user_id, parent_name, parent_phone, parent_email, status (Trial/Active/Inactive) |
| **student_instruments** | id, student_id, instrument, skill_level (0–8) |
| **student_teachers** | id, student_id, teacher_id, instrument (links a student to a teacher per instrument) |
| **lessons** | id, student_id, teacher_id, studio_id, instrument, day_of_week, start_time, duration, recurrence_type, recurrence_end, status |
| **lesson_occurrences** | id, lesson_id, date, status (scheduled/cancelled/completed), is_online |
| **attendance** | id, lesson_occurrence_id, status (Present / Absent-No-Credit / Absent-Notice / Teacher-Cancelled), marked_at, marked_by |
| **lesson_notes** | id, lesson_occurrence_id, teacher_id, note_text, drive_link, created_at, updated_at |

### 5.2 Student data fields

| Field | Notes |
|---|---|
| First name | |
| Last name | |
| Email address | Login email — parent's if minor, student's own if adult |
| Phone number | Not visible to teachers |
| Parent name | Optional — for minors |
| Parent phone | Optional — for minors |
| Parent email | Optional — for minors |
| Studio(s) | Kilsyth / Ringwood / future studios |
| Status | Trial / Active / Inactive |
| Instruments + skill level | Up to 5 — stored in student_instruments table (0–8 per instrument) |
| Assigned teacher(s) | One per instrument — stored in student_teachers table |

### 5.3 Initial data load
- ~500 students imported via CSV (predefined template to be provided)
- ~20 teachers entered manually by admin
- Lesson schedule manually entered by admin at launch
- Kilsyth and Ringwood studios pre-loaded

### 5.4 Ongoing data entry
- New students: exported from Zoho CRM daily, imported via CSV by admin
- New lessons: created by admin in the portal

---

## 6. Design & Branding

### 6.1 Visual style
- Match existing website style: dark charcoal nav, orange accent (#E8491E), Inter font
- Reference: https://pathfindermusiclessons.com.au
- Clean and functional — this is a tool, not a marketing page

### 6.2 Logo
- Use `Logo_-_long.png` in the portal header (white version on dark nav)

---

## 7. Technical Stack

| Layer | Technology | Notes |
|---|---|---|
| Frontend | HTML / CSS / Vanilla JS | Hosted on Netlify |
| Database + Auth + API | Supabase (free tier) | PostgreSQL + Row Level Security |
| Email notifications | Gmail (studio accounts) | Via Gmail SMTP or Gmail API |
| File storage | Google Drive | Teachers paste links — no file upload to portal |
| Zoho CRM | Manual CSV upload | No API integration in v1 |

### 7.2 Hosting
- Portal URL: `portal.pathfindermusiclessons.com.au`
- Hosted on Netlify alongside the main website

---

## 8. Open Questions — All Resolved

| # | Question | Answer |
|---|---|---|
| 1 | Super User — one or many? | One Super User only |
| 1 | Admin — one or multiple studios? | Admin can span multiple studios |
| 2 | Multiple instruments — profile only or multiple lessons? | Students can have multiple lessons on multiple instruments with different teachers |
| 3 | Google Drive — link only or structured folders? | Clickable link only — Drive access managed separately |
| 4 | Teacher availability — informational or enforced? | Soft warning to admin — admin can override |
| 5 | Email notifications — branded or plain text? | Plain text via studio Gmail accounts |
| 6 | Studios — hardcoded or dynamic? | Dynamic table — Kilsyth and Ringwood pre-loaded |
| 7 | Skill level — per instrument? Same 0–8 scale? | Yes per instrument, yes 0–8 (Beginner 0–3 / Intermediate 4–6 / Advanced 7–8) |
| 8 | Virtual room link — profile only or shown to students? | Profile + admin can include in notification email |
| 9 | Parent login — shared or separate? | Shared login — one email per student account |

---

## 9. Acceptance Criteria

- [ ] All four roles can log in and are restricted to what their role permits
- [ ] A teacher can mark attendance and write a lesson note; the student can read both immediately
- [ ] An admin can create a recurring lesson; it appears correctly in both teacher and student schedules
- [ ] A cancelled lesson appears greyed out (not removed) in the schedule
- [ ] 500 students can be imported from CSV without errors
- [ ] A teacher outside their stated availability triggers a soft warning on lesson creation
- [ ] Admin can send a plain-text email notification to a filtered group of students
- [ ] Skill level can be updated per instrument by the teacher and is visible on the student profile
- [ ] Google Drive links saved in a lesson note are clickable for the student
- [ ] The portal is fully usable on Chrome mobile (attendance marking primary use case)
- [ ] Super User can add a new studio and assign an admin to it

---

## 10. Revised Build Estimate

| Phase | Scope | Estimate |
|---|---|---|
| Phase 1 | Supabase setup · auth + roles · schedule view per role · studios + teacher availability | ~5 days |
| Phase 2 | Attendance · lesson notes · Google Drive links · skill level grading · student/teacher management | ~5 days |
| Phase 3 | Email notifications via Gmail · CSV import · admin dashboard · Super User controls | ~4 days |
| **Total** | | **~14 working days** |

> Note: The revised scope is larger than the original 8-day estimate due to the addition of:
> multi-instrument lessons, skill level grading per instrument, soft availability warnings,
> Gmail email notifications, Super User role, and dynamic studio management.

---

*Document prepared for Pathfinder Music Lessons · pathfindermusiclessons.com.au*  
*Version 0.2 — updated following requirements review on 24 July 2026*
