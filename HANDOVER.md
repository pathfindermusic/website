# Pathfinder Portal — where things stand

*Paste this, and `README.md`, as the first message in a new conversation.*

---

## What this is

A custom student portal for Pathfinder Music Lessons, replacing MyMusicStaff
and Zoho CRM. Two studios (Kilsyth, Ringwood), around 20 teachers, heading for
500 students. Live and in daily use.

Static HTML and vanilla JS on Netlify, Supabase for data and auth, Netlify
Functions for anything needing the service role key, Resend for email.

**Read `README.md` first.** It carries the architecture, the traps that have
already cost time, and the reasoning behind decisions that look odd without it.
Most of it was written after getting something wrong.

## The other documents

| File | What it holds |
|---|---|
| `README.md` | Architecture, conventions, every trap worth knowing |
| `Requirements_Specification_v0_4.md` | What it does, and why it differs from v0.3 |
| `Requirements_Phase4_Tasks_and_Enquiries_v0_2.md` | Tasks, enquiries, enrolment processes |
| `TECHNICAL_SPECIFICATION.md` | Building blocks and how they fit |
| `DEPLOYMENT.md` | Setting the stack up, and the local dev workflow |

## Working agreements

**SQL before files.** A page querying a column that does not exist fails the
whole query and takes the page down. A missed migration does not degrade one
feature — it breaks the screen.

**Run every verification block in a batch, not just the last.** The Supabase
editor shows only the final statement's result, which is exactly how a whole
migration file gets skipped unnoticed.

**One DDL statement at a time.** Several sent together can apply partially —
policy names created while the bodies stay stale, with no error.

**Check the URL before diagnosing.** Local and production share a database, so
the data looks identical while the code differs by however long since the last
deploy. A wrong number is more often a stale page than a bug.

**Develop locally with `netlify dev`.** Netlify bills roughly 15 credits per
deploy, flat. One early session spent 1,005 of 1,015 credits across 67 deploys.

## Outstanding

**Untested**
- Lesson reminders — need a deploy; scheduled functions do not run locally
- Weekly attendance marking report — same
- End-enrolment path with notice given and lessons still running

**Not built**
- Attendance report page (the sidebar link is dead)
- Email history page — every send is logged with its Resend id, so the data is
  there
- Teacher Lesson Notes page

**Decisions waiting on the admins**
- Should a teacher see a parent's phone number? Tasks like "call Jamie's mum"
  arrive with no number, because teachers are deliberately blocked from contact
  details. Either the admin pastes it in, teachers see their own students'
  details, or details appear only on tasks about that student.
- Whether "Absent — no credit" and "Absent — notice given" need distinct
  markers on the schedule; they share a red cross today

**Known gaps**
- Nothing extends a lesson series as time passes. `INDEFINITE_YEARS` is 3, so
  that is a real deadline, just a distant one.
- Deleting a studio does not check for live lessons
- Inactive accounts are blocked at login only; an existing session survives
- Lessons are not studio-scoped (students and tasks are not either, by choice —
  studio is a UI default, not a boundary)
- Resend's free tier is 100 emails a day. Lesson reminders at scale, or a
  studio-wide announcement to 500 students, exceed it.

## Phase 4d — the remaining migration step

The website enquiry form posts to **both** Zoho and the portal. Zoho is still
authoritative and still sends the acknowledgement and the studio notification,
so `receive-enquiry.js` sends nothing — see `SEND_ACKNOWLEDGEMENT` in that file.

Cutting over means switching that flag on, pointing the form only at the portal,
and taking over reCAPTCHA verification, which Zoho currently consumes.

**The parallel run means every enquiry is handled twice.** People do not sustain
that, so it should be short.
