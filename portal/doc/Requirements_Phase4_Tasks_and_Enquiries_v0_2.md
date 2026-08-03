# Pathfinder Music Lessons — Student Portal
## Phase 4: Enquiries, Tasks & Enrolment Processes

**Version:** 0.2 — Reviewed, questions resolved
**Date:** 31 July 2026
**Companion documents:** `Requirements_Specification_v0_4.md`,
`TECHNICAL_SPECIFICATION.md`, `DEPLOYMENT.md`

---

## 1. Purpose

Phases 1–3 manage **state**: students, lessons, attendance, notes. Phase 4 adds
**activity**: enquiries, the work they generate, and the record of how each was
resolved.

The goal is to retire two systems:

- **Zoho CRM** — currently holds enquiries and tasks, but not lessons, so every
  piece of work spans two systems
- **Sticky notes and admin-to-admin email** — where work actually gets tracked
  today, because it is faster than Zoho

The As-Is and To-Be process diagrams differ only in **which system each step sits
in**. The process itself does not change. That is the strongest argument for
bringing it into the portal: nothing new has to be learned, and the work stops
being split across tools.

### 1.1 The bar to clear

Zoho already does tasks, and admins route around it. **The measure of success is
not feature parity with Zoho — it is beating a sticky note.** A sticky note takes
three seconds, needs no login, has no mandatory fields, and stays in view until
it is done.

This shapes the design throughout: capture must be almost free, structure is
added afterwards rather than demanded upfront, and the day's outstanding work must
be visible without navigating anywhere.

---

## 2. Scope

### In scope
- Enquiry capture and follow-up, with a Prospective student status
- Task management — student-linked, teacher-linked, or generic
- Contact logging within a task, forming an activity thread
- Three fixed enrolment checklists, tracked as processes
- Automatic Trial and Enrolment confirmation emails from templates
- A task dashboard scoped by studio
- Website contact form posting to the portal *(deferred — see §10)*

### Out of scope
- Xero and eWay integration — the portal creates checklist items reminding an
  admin to act; it does not talk to either system
- Automated internal-staff announcements — remains a manual checklist item
- Editable email templates — fixed in code (§7.3)
- Migration of historical Zoho tasks — closed tasks stay in Zoho as an archive

---

## 3. Student lifecycle

### 3.1 Statuses

| Status | Meaning | Enters | Leaves |
|---|---|---|---|
| **Prospective** | Enquired, not yet committed | Contact form, phone or walk-in | → Trial, Active, or Lapsed |
| **Lapsed** | Enquiry that came to nothing | Uncontactable after 5 attempts, or declined | → Prospective if they return |
| **Trial** | Booked a trial lesson | Trial checklist completed | → Active or Inactive |
| **Active** | Enrolled in ongoing lessons | Enrolment checklist completed | → Inactive |
| **Inactive** | No longer taking lessons | End-enrolment checklist completed | → Active if they return |

**Prospective and Lapsed are new.** Trial, Active and Inactive already exist.

### 3.2 How Prospective students behave differently

A Prospective student is not yet in a relationship with Pathfinder. Therefore:

- They appear on a separate **Enquiries** page, not in the main student list
- They are **excluded from notification recipients** (§3.9 of v0.4). Notifications
  target `active` and `trial` only — Prospective and Lapsed are not included
- They have a studio, taken from the enquiry, which may change on enrolment
- They need no auth account until they enrol

### 3.3 Enquiry record

Captured from the contact form or entered by an admin:

Mapped directly from the website enquiry form:

| Form field | Portal field | Required |
|---|---|---|
| Student First Name | `profiles.first_name` | Yes |
| Student Last Name | `profiles.last_name` | Yes |
| Your Name (parent/guardian) | `students.parent_name` | No |
| Phone | `profiles.phone` | Yes |
| Email | `students.email` | Yes |
| Preferred Studio | `students.studio_id` | Yes |
| Instrument | `student_instruments` (skill level 0) | Yes |
| How can we help? | `students.enquiry_notes` | Yes |

**Instrument is a structured dropdown, not free text.** It can therefore create a
`student_instruments` row at enquiry, with skill level 0, so the instrument is
known before the first conversation and carries through enrolment without
re-keying.

The description field frequently contains the student's age and experience, and
sometimes health or accessibility information such as a mild disability. **This
is stored on the student record and carried through to enrolment** — it is often
the most useful thing an admin knows before the first conversation, and it is
currently lost when a Lead is re-keyed into MyMusicStaff.

**Visible to teachers.** Comparable information is already passed to teachers in
the internal announcement, and families share it expecting it to reach whoever
teaches them. Showing it on the student record replaces a manual step rather than
exposing anything new.

---

## 4. Tasks

### 4.1 Fields

| Field | Notes |
|---|---|
| Title | Required — everything else optional |
| Subject | A student, a teacher, or nothing (generic) |
| Studio | Which studio owns the work |
| Assigned to | An admin, or unassigned — meaning the studio queue |
| Due date | Optional |
| Status | Open / Done / Cancelled |
| Source | Manual, or created by a process |
| Created by, created at, completed at | |

**A task needs only a title.** Everything else can be added later or left blank.
This is deliberate: a mandatory-field form loses to a sticky note.

### 4.2 Contact log

A task holds **many notes over time**, not one description. Each note records:

| Field | Notes |
|---|---|
| Note text | What was said or done |
| Contact method | Phone / Email / SMS / In person / None |
| Outcome | Reached / Unreachable / Left message / N/A |
| Logged by, logged at | |

This mirrors what admins already do inside Zoho's task fields: a note per contact
attempt, with the due date pushed forward to bring the task back. Making it
explicit means the thread is readable afterwards — *why did this enquiry go
nowhere?* becomes answerable.

**Attempt count is displayed, not enforced.** The "max 5 attempts over 2 weeks"
guidance stays guidance. The portal shows the count and the date of the first
attempt so an admin can see where they are; it does not block or auto-lapse.

### 4.3 Handover

Reassigning a task to another admin, or to another studio, records who passed it
to whom and when. The task keeps its full history — the receiving admin sees every
prior contact attempt, not just the title.

### 4.4 Dashboard

The morning view. Scoped to the studios the admin can access:

- **Overdue** — due before today, still open
- **Due today**
- **Unassigned** — the studio queue, work nobody has picked up
- **Coming up** — next 7 days

Each row shows the title, the subject with a link, the due date and the assignee.

> This screen is the sticky-note replacement. If an admin cannot see their day at
> a glance, they will keep using paper regardless of what else is built.

---

## 5. Enrolment processes

### 5.1 Concept

A **process** is an instance of a fixed checklist attached to a student. It is
complete when every item is ticked; until then it is **in progress**, and an
admin can see what is outstanding. If a step cannot be completed — a payment
setup fails, for instance — the process is **stalled** and stays visible.

Three processes, each with a fixed set of items.

### 5.2 A — Trial Confirmation

Started when a prospective student agrees to a trial.

1. Added a Trial student to the Portal
2. Added a trial lesson to the Portal
3. Created a Xero invoice for the trial lesson
4. Announced the trial to internal staff

**Also created automatically:**
- Task: *Check payment for trial lesson*
- Task: *Trial follow-up*, due on the trial date
- Email: **Trial Confirmation** to the student (§7)

### 5.3 B — Ongoing Enrolment

Started when a student enrols in ongoing lessons — either directly, or after a
successful trial.

1. Added an Active student to the Portal
2. Added a lesson series to the Portal
3. Created repeating invoices in Xero
4. Created recurring payments in eWay
5. Announced the enrolment to internal staff

**Also created automatically:**
- Task: *Check payment for first lesson*
- Task: *Checking-in*, due after the second lesson (§5.5)
- Email: **Enrolment Confirmation** to the student (§7)

### 5.4 C — End Enrolment

Started when a student cancels.

1. Explained the cancellation policies
2. Set end date for lessons
3. Deleted invoices in Xero
4. Set end date for payments in eWay
5. Announced the unenrolment to internal staff

On completion, student status becomes **Inactive**.

### 5.5 Automatic due dates

Task due dates are calculated, not typed:

| Task | Due |
|---|---|
| Check payment for trial lesson | Trial date |
| Trial follow-up | Trial date |
| Check payment for first lesson | First lesson date |
| Checking-in | Day after the second lesson occurrence |

The *Checking-in* date comes from the generated lesson occurrences, so it lands
correctly whatever the schedule. **An admin can shift any due date** to handle
the unexpected.

### 5.5.1 Completing a Trial follow-up

A trial follow-up may run for some time — there is no limit, and deciding when a
trial is unlikely to convert is an admin's judgement. When the task is marked
complete, the portal asks the outcome:

| Outcome | Effect |
|---|---|
| **Enrolling** | Starts the Ongoing Enrolment process |
| **Not enrolling** | Sets student status to Inactive |
| **Still deciding** | Task stays open; admin sets a new due date |

This removes the risk of a converted trial being left at status Trial, or a lost
one lingering indefinitely.

### 5.6 Items the portal can verify itself

Some checklist items describe work done *in the portal*, so the portal can check
whether they were done:

| Item | Verifiable |
|---|---|
| Added a Trial/Active student | Yes — student status |
| Added a trial lesson / lesson series | Yes — a lesson exists |
| Set end date for lessons | Yes — series cancelled |
| Xero invoice, eWay payments, staff announcement | No — external |

**Proposal:** the portal auto-ticks what it can verify and leaves the rest to the
admin. This removes four of the fourteen manual ticks and prevents a process being
marked complete when the underlying work was not actually done.

**Confirmed.** The portal auto-ticks verifiable items and marks them as
system-verified, so it is clear which were checked automatically and which an
admin confirmed.

---

## 6. Enquiries page

A dedicated page, separate from Students.

- List of Prospective and Lapsed students, filtered by studio and status
- Each row: name, contact details, studio, enquiry date, attempt count, next task
  due date
- **Add enquiry** for phone and walk-in enquiries
- Opening an enquiry shows contact details, the enquiry description, the full
  contact log, and buttons to start the Trial or Ongoing Enrolment process
- **Mark as Lapsed** with an optional reason

Sorted by next task due date, so the enquiries needing attention are at the top.

---

## 7. Confirmation emails

### 7.1 Structure

Fixed welcome text, dynamically generated lesson details, fixed policy text.

```
[ Fixed welcome ]

Your lesson details:
  Student      Jasmine Caran
  Instrument   Guitar
  Lesson type  Private
  Teacher      Bill Vu
  Studio       Kilsyth
  Day & time   Thursdays, 4:00 PM
  Duration     30 minutes
  First lesson Thursday 7 August 2026

[ Fixed policies ]
```

### 7.2 When sent

Automatically when the lesson has been added — that is, when checklist item 2
completes and the lesson details exist to populate the email. Sent to the student
and, where present, the parent, using the existing address resolution rules.

Logged in `email_log` like any other send, and BCC'd to the studio.

### 7.3 Templates fixed in code

Policies rarely change, and when they do, the existing Notifications function can
send an update to affected students. Templates therefore live in code and are
changed on request rather than through a template editor.

> Revisit if this proves inconvenient. A template editor is a page and a table —
> not difficult, just not obviously worth it yet.

---

## 8. Data model additions

| Table | Purpose |
|---|---|
| **tasks** | id, title, subject_type, subject_id, studio_id, assigned_to, due_date, status, source, process_id, created_by, timestamps |
| **task_notes** | id, task_id, note_text, contact_method, outcome, logged_by, logged_at |
| **task_handovers** | id, task_id, from_user, to_user, to_studio, note, moved_at |
| **student_processes** | id, student_id, process_type, status, started_by, started_at, completed_at |
| **process_items** | id, process_id, item_order, label, is_done, done_by, done_at, auto_verified |

**Changes to existing tables:**

- `students.status` — add `prospective` and `lapsed` to the allowed values
- `students.enquiry_notes` — free text from the contact form
- `students.enquiry_date`
- `students.lapsed_reason`

`process_items` stores a row per item per instance rather than referencing a
template. Checklists are fixed today, but storing the labels means an existing
process is unaffected if the checklist is later changed — a completed enrolment
still shows what was actually ticked.

---

## 9. Access

| Role | Enquiries | Tasks | Processes |
|---|---|---|---|
| Super User | All studios | All studios | All studios |
| Admin | Their studios | Their studios, plus unassigned in those studios | Their studios |
| Teacher | No access | **Read-only, own tasks** — tasks where they are the subject | No access |
| Student | No access | No access | No access |

---

## 10. Delivery sequence

Building in stages, each independently useful:

| Stage | Scope | Why this order |
|---|---|---|
| **4a** | Tasks, contact log, dashboard | Standalone value — admins can stop using Zoho tasks immediately, even before enquiries move |
| **4b** | Prospective/Lapsed statuses, Enquiries page, manual enquiry entry | Enquiries move to the portal; the website form still posts to Zoho |
| **4c** | Processes and checklists, automatic tasks, confirmation emails | The enrolment workflow |
| **4d** | Website form posts to the portal; Zoho retired | Only once 4a–4c are proven |

### 10.1 Transition

Running the website form into Zoho while enquiries are managed in the portal
means every enquiry is keyed in twice. **Admins will quietly stop doing one of
them.** The parallel period should therefore be as short as possible, and 4d
should follow as soon as 4b and 4c are working — not once everything is perfect.

A nominated admin trials the new functions and coordinates with the others, as
agreed.

---

## 11. Questions resolved

| # | Question | Answer |
|---|---|---|
| 1 | Should teachers see tasks that concern them? | **Yes — read-only**, limited to tasks where they are the subject |
| 2 | Auto-tick verifiable checklist items? | **Yes**, marked as system-verified |
| 3 | Is enquiry description hidden from teachers? | **No — visible.** Comparable information already reaches them via the internal announcement |
| 4 | Should a Prospective student auto-lapse? | **No.** Marking Lapsed is an admin's judgement |
| 5 | What happens to a trial that does not convert? | Simple status change, prompted on completing the Trial follow-up task (§5.5.1) |
| 6 | Can one student have two open processes? | Trial is a state of the student, independent of instrument. A second instrument can only be added for an **Active** student, so Trial and Enrolment never overlap |

## 11a. New issues raised by the enquiry form

### Instrument list mismatch — needs resolving before stage 4d

The website form and the portal use different instrument lists:

| Website form | Portal |
|---|---|
| Piano / Keyboard | **Piano** |
| — | Saxophone |
| — | Band |
| Guitar, Bass, Drums, Voice / Singing, Violin, Ukulele, Music Theory, Other | same |

**"Piano / Keyboard" and "Piano" are different strings and will not match.**
Skill levels, lesson instrument filtering and teacher-instrument validation all
compare these values exactly, so a mismatch silently fails rather than erroring.

This is not hypothetical — the Zoho import already brought in "Piano / Keyboard"
values, so both spellings exist in `student_instruments` today. A student with
"Piano / Keyboard" whose teacher teaches "Piano" would accumulate a second,
duplicate skill record rather than updating the first.

**Recommended:** settle on one canonical list, align the form and the portal, and
run a migration normalising existing values. Worth doing before the enquiry form
starts writing directly (§10, stage 4d), and worth checking the current data
regardless.

Also worth deciding whether **Saxophone** should appear on the form — it is taught
but cannot currently be enquired about. **Band** is reasonably absent, since it is
not an entry point.

### reCAPTCHA

The form uses reCAPTCHA, which currently protects the Zoho endpoint. When the form
posts to the portal instead, the receiving Netlify Function must verify the
reCAPTCHA token server-side — otherwise the endpoint is an open door for creating
student records. To be handled as part of stage 4d.

## 12. Estimate

Comparable in size to Phases 1 and 2 combined.

| Stage | Scope |
|---|---|
| 4a | Two tables, task list, dashboard, task detail with contact log |
| 4b | Status changes, Enquiries page, enquiry form |
| 4c | Process engine, three checklists, automatic task creation, two email templates |
| 4d | Website form change, Zoho retirement |

Each stage is independently deployable and independently useful — 4a alone
replaces Zoho tasks.

---

*Reviewed draft · Pathfinder Music Lessons · pathfindermusiclessons.com.au*
