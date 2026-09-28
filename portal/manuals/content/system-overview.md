---
title: System Overview
updated: 2026-09-28
---
<h2 id="functional">What the Portal does</h2>
<p>
The Portal is a purpose-built system for Pathfinder Music Lessons that brings
together four areas of studio work, matching the four groups on the admin
sidebar:
</p>
<ul>
<li><strong>Front Desk</strong> — tracking enquiries from first contact through
to trial or lapse, a shared task list so nothing gets forgotten, and two
different ways to send a message to a group of families.</li>
<li><strong>Teaching</strong> — the lesson timetable, the student roster, and
the teacher directory, including clash-checked scheduling and attendance.</li>
<li><strong>Curriculum</strong> — a Tier/Grade skill-level ladder for every
instrument, plus a library of teaching materials (currently built out for
Guitar).</li>
<li><strong>Reports</strong> — an attendance rollup across students, teachers
and studios, plus Gmail-ready distribution lists for mass email.</li>
</ul>
<p>
Teachers and students each get their own simplified view of the same
underlying data — a teacher sees their own schedule, students and a task
inbox; a student (or parent) sees their own lessons, notes, attendance and
progress.
</p>

<h2 id="mapping">How it relates to the website, Zoho and MyMusicStaff</h2>
<p>
Nothing about your existing tools changes because the Portal exists. The
website keeps working exactly as it does today, and enquiries submitted
through its form continue to flow through in the same way. Here's roughly how
the Portal's areas line up with what you already know from Zoho CRM and
MyMusicStaff:
</p>
<table>
<tr><th>Today</th><th>Portal equivalent</th></tr>
<tr>
<td>Zoho CRM — leads / enquiries</td>
<td>Front Desk → <strong>Enquiries</strong></td>
</tr>
<tr>
<td>Zoho CRM — tasks &amp; follow-ups</td>
<td>Front Desk → <strong>Tasks</strong></td>
</tr>
<tr>
<td>MyMusicStaff — student &amp; family records</td>
<td>Teaching → <strong>Students</strong></td>
</tr>
<tr>
<td>MyMusicStaff — lesson scheduling &amp; timetable</td>
<td>Teaching → <strong>Lessons</strong></td>
</tr>
<tr>
<td>MyMusicStaff — teacher availability</td>
<td>Teaching → <strong>Teachers</strong></td>
</tr>
<tr>
<td>MyMusicStaff — attendance</td>
<td>Reports → <strong>Attendance</strong></td>
</tr>
<tr>
<td><em>Not previously available</em></td>
<td>Curriculum (skill grading + artefact library), Distribution Lists,
in-app Notifications, and the teacher/student self-service dashboards</td>
</tr>
</table>
<p>
The Portal was built to fit how Pathfinder actually works — the instrument
list, email wording, cancellation policy and enrolment steps all match what
the studio already uses, rather than asking staff to adapt to generic
software.
</p>

<h2 id="parallel">Why we're running two systems side by side</h2>
<p>
The Portal is new, and the safest way to introduce a system this central to
day-to-day work is to run it in parallel with the tools it may eventually
replace, rather than switching everything over at once. During this period:
</p>
<ul>
<li>The website and its enquiry form are unaffected.</li>
<li>Zoho and MyMusicStaff keep working as they do today.</li>
<li>The Portal is available for the studio to trial, compare against the
existing workflow, and provide feedback on.</li>
</ul>
<div class="callout callout-tip">
<strong>Scope of this guide</strong>
<p>
This guide only covers the Portal. It doesn't set out rules for what to
enter where during the parallel run — that's a decision for the studio to
make and communicate separately. If you're unsure whether something should
also be recorded in Zoho or MyMusicStaff right now, check with your studio
admin.
</p>
</div>

<h2 id="roles">Roles: who sees what</h2>
<p>
Every Portal account has exactly one role, which decides what you see when
you log in:
</p>
<table>
<tr><th>Role</th><th>Typically</th><th>What they get</th></tr>
<tr>
<td><strong>Superuser</strong></td>
<td>Studio owner / senior admin</td>
<td>Everything an Admin has, plus Studios and Admins management, and
visibility across every studio without a default filter.</td>
</tr>
<tr>
<td><strong>Admin</strong></td>
<td>Front-desk staff</td>
<td>Front Desk, Teaching, Curriculum and Reports. See the
<a href="admin-guide.html">Admin Guide</a>.</td>
</tr>
<tr>
<td><strong>Teacher</strong></td>
<td>Teaching staff</td>
<td>My Schedule, My Students, My Tasks. See the
<a href="teacher-guide.html">Teacher Guide</a>.</td>
</tr>
<tr>
<td><strong>Student</strong></td>
<td>Students &amp; parents</td>
<td>My Lessons, Practice Notes, Attendance, My Progress. See the
<a href="student-guide.html">Student Guide</a>.</td>
</tr>
</table>
<p>
Only a superuser can create Admin accounts (from Super User → Admins), and
only a superuser can add or edit studios. A person can currently only hold
one role at a time — someone who both teaches and administers needs two
separate logins with two different email addresses.
</p>

<h2 id="technical">How it's built (technical)</h2>
<p>
For anyone curious about what's under the hood — this section is optional
reading and isn't needed to use the Portal day to day.
</p>
<ul>
<li><strong>No app to install.</strong> The Portal is a website
(<code>pathfindermusiclessons.com.au/portal</code>) that works from any
modern browser on a computer, tablet or phone — there's nothing to
download.</li>
<li><strong>Hosting:</strong> the site is hosted on Netlify, the same
platform serving the public website.</li>
<li><strong>Database:</strong> all Portal data — students, lessons,
attendance, tasks, enquiries — lives in Supabase, a hosted database
service. Access rules built into the database (not just the screen you're
looking at) control who can see or change which records.</li>
<li><strong>A handful of small server-side helpers</strong> handle the few
things that need elevated privileges the browser shouldn't have directly —
creating a login for a new admin, teacher or student, resetting a
password, and resolving/sending bulk emails.</li>
<li><strong>No native mobile app.</strong> The Portal is fully usable from a
phone's browser; it adapts its layout to a smaller screen automatically.</li>
</ul>

<h2 id="email">How email works</h2>
<p>
The Portal sends email in a few different ways, each suited to a different
purpose:
</p>
<table>
<tr><th>Tool</th><th>Used for</th><th>Sent from</th></tr>
<tr>
<td>Notifications (Front Desk)</td>
<td>One-way announcements to a targeted group, sent by the Portal itself</td>
<td>The chosen studio's address</td>
</tr>
<tr>
<td>Distribution Lists (Reports)</td>
<td>Generates a Bcc-ready address list for an email you send yourself from
Gmail — for anything needing a reply or an attachment</td>
<td>Your own Gmail account</td>
</tr>
<tr>
<td>Password reset / account emails</td>
<td>Automatic account emails (temporary passwords, password resets)</td>
<td>The studio's info@ address</td>
</tr>
</table>
<p>
See the <a href="admin-guide.html#notifications">Notifications</a> and
<a href="admin-guide.html#distribution-lists">Distribution Lists</a> sections
of the Admin Guide for exactly when to use which.
</p>

<h2 id="help">If something looks wrong</h2>
<p>
If a page shows data that looks incorrect, a button doesn't do what this
guide says it should, or something is missing, let your studio admin know
with a description of what you saw — that's the fastest way for it to get
looked at and, if needed, fixed.
</p>

