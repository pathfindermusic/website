# Pathfinder Music Lessons — Student Portal
## Project Requirements Document

**Version:** 0.1  
**Date:** 24 July 2026
**Status:** Draft  

---

## 1. Project Overview

### 1.1 Background
<!-- Brief description of Pathfinder Music Lessons and why this portal is being built. -->
Pathfinder Music Lessons operates two studios in Kilsyth and Ringwood, Victoria.
We currently use MyMusicStaff to manage scheduling, attendance and lesson notes but cannot integrate it with our Zoho CRM and Google Drive where we store our lessons recordings and large files for students. 
A custom portal gives us full control and a simpler way to manage students and their lessons

### 1.2 Goals
<!-- What does success look like? What problems does this portal solve? -->
- Replace MyMusicStaff with a portal we own and control
- Give teachers a simple way to mark attendance and write lesson notes
- Give students visibility of their upcoming lessons and practice notes
- Give students read access to large files (e.g. recordings or backing tracks) that we keep in our Google Drive
- Give admins a central place to manage students, teachers and lessons

### 1.3 Out of Scope
<!-- What are we explicitly NOT building in this version? -->
- Zoho CRM integration (manual CSV upload instead)
- Online lesson booking by students
- Payment processing

---

## 2. Users & Roles

### 2.1 Super User
**Who:** The Super User  
**Can do:**
- All what an Admin can do (see below)
- Add, edit and deactivate Admin
- Restrict which studios (and their students, teachers and lesson schedule) an Admin can work with
- Add, edit and delete studios

### 2.1 Admin
**Who:** Studio Admins  
**Can do:**
- Add, edit and deactivate students
- Add, edit and deactivate teachers
- Add, edit and delete teachers' shifts/availability
- Create, edit and cancel lessons
- View all attendance and lesson notes across all studios
- Customise their own dashboard/view of schedule based on the studio they are in or the teachers they select. By default when they log in they should be presented with the schedule of their studio's students of the day
- Send emails to students of 
    - all studios, e.g. when the school is closed on a public holiday
    - a selected studio, e.g. when a studio is closed for maintenance
    - a selected teacher on selected day, e.g. when a teacher is unable to teach
- Upload new students from CSV export

### 2.2 Teacher
**Who:** Music Teachers - Instrumental or Vocal Teachers 
**Can do:**
- View their own lesson schedule
- Mark attendance for each lesson
- Write lesson notes after each session
- Update their own students' skill level/grading
- Share links to large files stored on Pathfinder Music's Google drive

**Cannot do:**
- See other teachers' students or notes
- See students' contact details (phone number or email address)

### 2.3 Student
**Who:** Students or their parents
**Can do:**
- View their own upcoming lesson schedule
- Read lesson notes written by their teacher
- View their own attendance history
- View the links to shared files published in Google Drive by their teachers

**Cannot do:**
- Book or cancel lessons
- See other students' data

---

## 3. Functional Requirements

### 3.1 Authentication
- [X] Login with email and password
- [X] Role-based access (super user/ admin / teacher / student)
- [X] "Remember me" on login
- [X] Password reset via email
- [X] Session timeout after 5 hours

### 3.2 Schedule
- [X] Admin sees all lessons across the studios they have access to as defined by the Superuser, filterable by studio / teacher / date
- [X] Teacher sees only their own lessons
- [X] Student sees their own upcoming lessons
- [X] Weekly view by default, with ability to navigate forward/back
- [X] Show lesson details: time, student name, studio, lesson type

### 3.3 Attendance
- [X] Teacher can mark each lesson as: Present / Absent - No Makeup Credit / Absent - Notice Given/ Teacher Cancelled
- [X] Admin can edit attendance records
- [X] Student can view their own attendance history
- [X] Attendance must be marked within 7 days of the lesson
- [X] Admin receives a notification if attendance is not marked after 5 days

### 3.4 Lesson Notes
- [X] Teacher can write a note after each lesson
- [X] Teacher can edit their own notes
- [X] Student can read notes written for their lessons
- [X] Admin can read all notes
- [X] Notes support plain text only (no rich text/formatting needed)
- [X] Notes are visible to the student immediately after saving

### 3.5 Student Management (Admin and Super User)
- [X] Add a new student manually
- [X] Import students from a CSV file, using a predefined template
- [X] Edit student details (name, email, instrument, studio, teacher)
- [X] Deactivate a student (hide from active lists without deleting)
- [X] Assign a student to a teacher or multiple teachers
- [X] View a student's full lesson history, attendance and notes
- [X] Send emails to students using various selection criteria: student across all studios, student of a certain studios, students of certain teachers, students of a certain day

### 3.6 Teacher Management (Admin and Super User)
- [X] Add a new teacher
- [X] Edit teacher details (name, email, instruments, studio, availability: days of weeks, hours of day, studios)
- [X] Deactivate a teacher
- [X] View a teacher's schedule and student list

### 3.7 Lesson Management (Admin and Super User)
- [X] Create a recurring weekly lesson for a student + teacher. Recurring lessons can be indefinite or certain number of occurences or between a date range
- [X] Edit or cancel a single occurrence
- [X] Edit or cancel all future occurrences
- [X] Supported lesson durations: 30 min, 60 min, 90 min or 120 min
- [ ] <!-- e.g. Supported studios: Kilsyth, Ringwood -->

---

## 4. Non-Functional Requirements

### 4.1 Performance
- <!-- e.g. Pages should load within 2 seconds on a standard broadband connection -->
- The system should support up to 25 concurrent users without degradation

### 4.2 Devices & Browsers
- Must work on desktop (Chrome, Safari, Firefox)
- Must be usable on mobile (teachers may mark attendance on their phone)
- <!-- e.g. Does not need to be a native app -->

### 4.3 Security
- All data transmitted over HTTPS
- Passwords stored as hashed values, never plain text

### 4.4 Availability
- Portal should be available 90% of the time (Supabase + Netlify both offer this on free tier)
- Planned maintenance can occur outside studio hours (before 9am or after 9pm AEST)

---

## 5. Data

### 5.1 Initial data load
- ~500 existing students to be imported via CSV from Zoho CRM export
- ~20 teachers to be entered manually
- Current schedule to be manually added by an Admin

### 5.2 Ongoing data entry
- New students: exported from Zoho CRM daily and uploaded to portal by admin
- New lessons: created by admin in the portal

### 5.3 Data we need per user
- First name
- Last name
- Email address
- Phone number
- Instrument 1/Level of experience (Beginner: 0-3, Intermediate: 4-6, Advanced: 7-8)
- Instrument 2/Level of experience (Beginner: 0-3, Intermediate: 4-6, Advanced: 7-8)
- Instrument 3/Level of experience (Beginner: 0-3, Intermediate: 4-6, Advanced: 7-8)
- Instrument 4/Level of experience (Beginner: 0-3, Intermediate: 4-6, Advanced: 7-8)
- Instrument 5/Level of experience (Beginner: 0-3, Intermediate: 4-6, Advanced: 7-8)
- Assigned Studios (Kilsyth / Ringwood / Other)
- Status: Trial / Active / Inactive
- Role specific data
    - Student
        - Assigned teacher
        - Parent's name
        - Parent's phone number
        - parent's email address
    - Teacher
        - Availability: days of week and hours of day at certain studios
        - Virtual room (e.g. Zoom) link

---

## 6. Design & Branding

### 6.1 Visual style
- Match the existing website style (dark charcoal nav, orange accent, Inter font) https://pathfindermusiclessons.com.au
- Keep it clean and functional — this is a tool, not a marketing page

### 6.2 Logo
- Use Logo_-_long.png in the portal header

---

## 7. Technical Constraints

### 7.1 Stack
| Layer | Technology | Notes |
|---|---|---|
| Frontend | HTML / CSS / Vanilla JS | Hosted on Netlify |
| Database + Auth + API | Supabase (free tier) | PostgreSQL, Row Level Security |
| Zoho CRM | Manual CSV upload | No API integration in v1 |

### 7.2 Hosting
- Portal to be hosted on Netlify at portal.pathfindermusiclessons.com.au

---

## 8. Open Questions

<!-- List anything that still needs a decision before or during the build.
Examples: -->
- [X] Do students log in with the same email they used when enrolling? Yes
- [X] Should cancelled lessons still appear in the schedule (greyed out)? Yes
- [X] Do we need email notifications for anything (e.g. teacher gets email when lesson is assigned)? Yes, admins should be able to notify students of any event impacting the schedule, e.g. a teacher in unavailable to teach, a studio is closed, etc.
- [X] What is the URL for the portal - portal.pathfindermusiclessons.com.au

---

## 9. Acceptance Criteria

<!-- How do we know when the portal is done and ready to launch?
Example: -->
- [X] All the roles can log in and perform what they can/cannot do for their role
- [X] A teacher or admin can mark attendance and write a note; the student can see both
- [X] An admin can create a lesson and it appears in both the teacher's and student's schedule
- [X] 500 students can be imported from CSV without errors
- [X] The portal works correctly on Chrome (desktop and mobile)

---

*Document prepared for Pathfinder Music Lessons · pathfindermusiclessons.com.au*