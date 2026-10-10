---
title: Admin Guide
updated: 2026-10-05
---
<h2 id="getting-started">Getting started</h2>
<p>
Sign in at <code>pathfindermusiclessons.com.au/portal/login.html</code> with
the email and password your superuser set up for you. If it's your first
time in, you'll be taken straight to a "set your password" screen before you
can do anything else — you can't skip this step on a temporary password.
After that, every login lands you on <strong>Tasks</strong>, which is the
admin landing page.
</p>
<p>
Your sidebar is organised into four groups — <strong>Front Desk</strong>,
<strong>Teaching</strong>, <strong>Curriculum</strong> and
<strong>Reports</strong> — and this guide follows that same order. If you're
a superuser you'll also see a <strong>Super User</strong> group at the
bottom, covered at the end of this guide.
</p>
<div class="callout callout-tip">
<strong>Studio filters are a default, not a restriction</strong>
<p>
Most pages pre-select your own studio in a filter dropdown so your day
starts with your own work. That's a convenience, not a lock — every studio
is one dropdown selection away, and you can see and work on the other
studio's records whenever you need to.
</p>
</div>

<h2 id="front-desk">Front Desk</h2>
<p>
Front Desk is where enquiries and day-to-day admin work gets tracked and
chased. It's the first thing you see when you log in.
</p>

<h3 id="tasks">Tasks</h3>
<p>
A shared to-do list for the whole studio — enquiry follow-ups, waitlist
entries, and anything else that needs doing on a given day.
</p>
<ul>
<li><strong>Quick-add:</strong> type into "What needs doing?" at the top and
press Enter to create a bare task, assigned to you, in whichever studio
you have selected.</li>
<li><strong>Jump to a day</strong> with the <code>‹ Today ›</code> controls
or the date picker. The page always shows everything overdue plus whatever
is due on the day you're looking at.</li>
<li><strong>Bucket tiles</strong> narrow the list to one purpose: Overdue,
Due today, Unassigned, Next 7 days, Teacher replied, or Waiting list.
Clicking an already-active tile returns you to the default view.</li>
<li><strong>Filters:</strong> Studio, Assignee (anyone / assigned to me /
unassigned / a named admin), and Status (Open / Done &amp; cancelled /
Everything).</li>
<li>Click any row to open it. Required: a <strong>Title</strong>. You can
also set what/who it's <strong>About</strong>, its Studio, who it's
<strong>Assigned to</strong>, and a <strong>Due date</strong> (with
one-click "Due tomorrow" / "Due next week" / "Due today" shortcuts).</li>
<li>If the task is about a prospective enquiry, the enquiry's own notes and
a link straight to that enquiry appear at the top of the task.</li>
<li><strong>Contact log:</strong> record how you reached someone (phone /
SMS / email / in person), the outcome, and a note. This is also how you
clear a "Teacher replied" flag — logging a response marks it handled.</li>
<li><strong>Recurring tasks</strong> (🔁 button): set up a rule — daily,
weekly on a chosen day, or monthly on a date or a weekday like "1st
Monday" — and a real task is generated automatically each time it's due.</li>
</ul>
<div class="callout callout-warning">
<strong>Three ways to close a task mean three different things</strong>
<p>
<strong>Cancel</strong> is for a task that turned out not to be needed —
it's blocked on enquiry follow-ups, because every enquiry genuinely needs
chasing. <strong>Discard as spam</strong> permanently deletes the enquiry,
its record and its task(s) — use it only for fake/spam enquiries, never
for a real person who simply didn't proceed. <strong>Mark done</strong> on
a real enquiry or trial opens a "How did it go?" prompt — <strong>Booked a
trial</strong>, <strong>Enrolling</strong>, <strong>Not proceeding</strong>,
or <strong>Ready, but no suitable slot — add to waiting list</strong> —
that updates the student's status correctly; this is almost always the
right button for a genuine enquiry or trial.
</p>
</div>

<h4 id="waiting-list">Waiting list</h4>
<p>
Sometimes a family is ready and keen to enrol, but there's no suitable
lesson slot open right now. Rather than leaving the enquiry hanging or
closing it as "Not proceeding," pick <strong>Ready, but no suitable slot —
add to waiting list</strong> from the "How did it go?" prompt.
</p>
<ul>
<li>The task <strong>stays open</strong>, with no due date, instead of
closing — this is what keeps it out of Overdue/Due today and off your
daily radar until you come looking for it.</li>
<li>The student's status doesn't change — they stay <strong>prospective</strong>,
the same as any other undecided enquiry.</li>
<li>A note — <em>"Student added to waiting list"</em> — is added to the
task's contact log automatically, so there's always a record of when and
why someone went on the list.</li>
<li>You can record <strong>Preferred teacher</strong>, <strong>Preferred
day</strong> and <strong>Preferred time</strong> on the task — either at
the moment you add someone to the list, or later, once you've actually
discussed it with the family. Open the task and look for the Waiting list
details section; any of the three can be left blank if you don't have
that detail yet, and you can come back and fill them in or change them at
any time.</li>
<li>"Preferred studio" isn't a separate field — it's just whichever studio
the task is already set to.</li>
</ul>
<p>
Checking the waiting list for openings is currently a manual process:
click the <strong>Waiting list</strong> bucket tile and work through the
entries, comparing what each one is waiting for against the current
timetable. There's no automatic alert yet when a matching slot opens up —
if that would be useful, mention it to your developer.
</p>
<div class="callout callout-tip">
<strong>Waiting list entries are easy to forget</strong>
<p>
Waitlist tasks don't have a due date and are deliberately left out of
Overdue/Due today/Next 7 days, so they don't clutter those counts — but
that also means they're invisible unless you click "Waiting list" or
switch Status to "Everything."
</p>
</div>
<div class="callout callout-tip">
<strong>Entries lapse automatically after 3 months</strong>
<p>
A family is unlikely to still be waiting three months on, so a waiting
list entry that's been open that long closes itself overnight — the
student is marked lapsed, with a note explaining why, exactly as if you'd
chosen "Not proceeding" by hand. If you've since booked a trial or
enrolled the student yourself, this won't touch them — it only acts on
entries nobody has moved on from.
</p>
</div>

<h3 id="enquiries">Enquiries</h3>
<p>
A register of every prospective student — from the website form or logged
manually here — so you can see who's been contacted and what happened to
each lead.
</p>
<ul>
<li>Website enquiries arrive automatically; use
<strong>+ Add enquiry</strong> only for a phone call or walk-in. Required:
first/last name, phone, email, studio, instrument, how they got in touch,
and the enquiry date.</li>
<li>Adding an enquiry always creates a follow-up task automatically and
attempts to send the same acknowledgement email a website enquiry gets.</li>
<li><strong>Filters:</strong> Studio and Status (Open enquiries / Converted /
Lapsed / All).</li>
<li>The table shows how many contact attempts have been logged and when the
next follow-up is due — "Overdue," "Today," or the actual date. "Needs a
task" in amber means the enquiry has no open task chasing it — add one from
Tasks, or mark it lapsed.</li>
<li>Click a row for the full detail, including a "possible match" warning if
another student record shares the same email, phone or name.</li>
</ul>
<div class="callout callout-caution">
<strong>Delete vs. Mark lapsed</strong>
<p>
<strong>Delete</strong> (only available on prospective/lapsed enquiries)
permanently removes the enquiry, its task and its login record — it cannot
be undone, and is meant for spam or fake enquiries only. For a genuine
person who simply didn't go ahead, use <strong>Mark lapsed</strong>
instead, which keeps them as history and closes the open task for you.
</p>
</div>

<h3 id="notifications">Notifications</h3>
<p>
Send a one-way, personalised bulk email straight from the Portal — each
recipient gets their own individually addressed email.
</p>
<ol>
<li><strong>Pick an audience:</strong> all students at one or more studios,
all students of one teacher, everyone with a lesson on a given weekday, or
one teacher's students on a specific date.</li>
<li><strong>Compose:</strong> choose the studio to send from (only studios
with an email address on file can be selected), then a Subject and
Message. Use <code>{{first_name}}</code> or <code>{{student_name}}</code>
to personalise the message. You can paste an image directly into the
message box to include it.</li>
<li><strong>Refresh recipients</strong> before sending — this is required,
and shows you the exact list, plus anyone who'll be skipped for having no
email on file or an invalid-looking address.</li>
<li><strong>Send</strong> after confirming the recipient count and sending
studio in the pop-up.</li>
</ol>
<p>
A copy always goes to the sending studio's inbox afterwards — a direct Bcc
if there was exactly one recipient, or a single summary listing everyone
else it went to.
</p>
<div class="callout callout-warning">
<strong>Pasted images stay public</strong>
<p>
An image pasted into a Notification is hosted at a public web address
indefinitely, even after you delete the email. It's fine for a flyer or a
map — never paste anything showing other families' names or payment
details.
</p>
</div>

<h3 id="events">Events</h3>
<p>
Events is where you run a concert or recital: you set up the day, students
book their own performance slots, and everyone sees the programme fill in
live. It is in the <strong>Front desk</strong> section of the sidebar.
</p>
<p><strong>Create an event</strong> with <strong>＋ New event</strong>:</p>
<ul>
<li><strong>Name, date, start and end time, venue name and address.</strong></li>
<li><strong>Block length</strong> (default 60 minutes) — students choose a block,
for example 2:00 – 3:00 pm — and <strong>performances per block</strong>
(default 12, so about 5 minutes each). The page shows a preview such as
"3 blocks × 12 = 36 performances" as you type, and warns if the last block
is shorter or the slots are very short.</li>
<li><strong>Most performances per student</strong> (default 5) — students can
book <em>one performance per instrument</em> (for example Guitar, Piano and
Band), so this is only an overall ceiling. You can still add extra
performances for a student yourself. Plus an optional
<strong>Book by</strong> date.</li>
<li><strong>Status</strong> — a new event is a <em>Draft</em> that only admins
can see. <strong>Open for booking</strong> when you are ready; <strong>Close
bookings</strong> later (students can still see the programme but can't book,
change or cancel); <strong>Reopen</strong> if you need to.</li>
</ul>
<p><strong>The event page</strong> shows the grid: one panel per block, one
numbered square per performance slot. Click a <strong>booked</strong> square
to see everything the student entered (instrument, teacher, piece,
accompaniment, the blocks they asked for, their comments) and to
<strong>Edit</strong>, <strong>Move…</strong> (choosing a taken slot swaps the
two performances) or <strong>Cancel this booking</strong>. Click a
<strong>free</strong> square to add a performance for a student yourself — it
lands exactly in that slot. <strong>Running order</strong> switches to a table
you can <strong>Print</strong> for the day.</p>
<p><strong>Inviting students and teachers.</strong> Under the grid title is the
booking link. <strong>Copy</strong> it, or press <strong>✉️ Send invitation…</strong>
and choose <strong>Students</strong>, <strong>Teachers</strong> or
<strong>Both</strong>. Notifications opens with a ready-written email (it greets
each person by first name and includes the link). The student email asks them to
book; the teacher email tells them their students are invited and what they will
see. With <strong>Both</strong> you review and send the student email first, then
the teacher email appears for you to review and send. Check the studio and
recipients, then send as usual. The same link also appears on each student's
dashboard once the event is open.</p>
<p><strong>What teachers see.</strong> A teacher sees only their own students'
performances and any they have been asked to accompany (those are highlighted),
plus a short summary: how many of their students are performing, who would like
them to accompany, and which backing tracks to prepare, with the piece and any
notes the student left. Each backing track also becomes a task about that
teacher, in the teacher's studio (the event's studio, or the student's if the event
is for all studios) and assigned to that studio's admin, so it shows up on the
Tasks page like any task you create about a teacher. It is due two weeks before the event — or on the day of booking if the booking is made later
than that. If a student cancels or changes their accompaniment, the task is
cancelled or updated for you. A student who chooses "someone else" as their
teacher does not create a task, because there is no teacher to give it to.</p>
<div class="callout callout-tip">
<strong>How students are placed</strong>
<p>
Each student picks up to three preferred blocks. The Portal puts them in the
<strong>first</strong> one that still has room; if all three are full they are
told and choose again. Nobody can be double-booked, even if two families press
Submit at the same moment. Other families see each other only as first name and
last initial (for example "Ava L.") with the instrument and piece — the teacher,
comments and who accompanies stay private to the family, the teacher and you.
</p>
</div>
<p>
<strong>Changing the layout later.</strong> You can edit the event any time, but
the Portal won't let you shrink the blocks or slots below where people are
already booked — move or cancel those performances first. Changing the date or
times moves everyone with the blocks, and students are not told automatically,
so send a Notification. An event with bookings can't be deleted; close it
instead.
</p>

<h3 id="vouchers">Gift Vouchers</h3>
<p>
Vouchers is where you issue a gift voucher on the spot — for example when
someone buys one at the front desk or over the phone. You create it, check what
it looks like, and the Portal emails it as a PDF. It is in the
<strong>Front desk</strong> section of the sidebar.
</p>
<p><strong>Issue a voucher</strong> with <strong>＋ New voucher</strong>:</p>
<ul>
<li><strong>Issuing studio.</strong> The email comes from this studio's address
and is blind-copied to it, so the studio keeps a copy.</li>
<li><strong>To.</strong> If the recipient is already a student, start typing
their name and pick them — their name and email fill in. To give the voucher to
someone who isn't a student yet, simply type their name and email instead (or
change the name afterwards).</li>
<li><strong>Voucher for.</strong> What the voucher is worth, for example
“5 Music Lessons at Pathfinder Music”. Tap one of the suggestions to fill it in.
This becomes the headline on the voucher and the email subject, so keep it
short. An optional dollar <strong>value</strong> can be printed as well.</li>
<li><strong>From.</strong> The purchaser's name, and their email if you'd like
them copied on the email.</li>
<li><strong>Purchase date</strong> (today unless the voucher was bought earlier).
The voucher is valid for one year from this date; the expiry is shown as you
type and printed on the voucher.</li>
<li><strong>Personal message.</strong> Anything the purchaser would like to say
to the recipient (up to 500 characters). It is printed on the voucher.</li>
</ul>
<p>
Press <strong>Preview voucher</strong> to see the finished PDF exactly as it
will be sent, along with who the email goes to (recipient), who is copied
(purchaser) and who is blind-copied (the studio). Use <strong>← Edit</strong> to
change anything, or <strong>Send voucher</strong> to email it. The email is
titled “Your Voucher for …”, has a short, friendly message, and the voucher
attached.
</p>
<p>
<strong>Afterwards.</strong> Every voucher is listed with its number, who it is
for, its status and whether the email went. Click one to <strong>view or
download the PDF</strong>, <strong>email it again</strong> (you can correct the
address first), <strong>mark it redeemed</strong> when it has been used, or
<strong>void</strong> it. A voucher shows as <em>Expired</em> automatically
after its year is up. If an email ever fails, the voucher is still saved and
shows “Not sent” — open it and press <strong>Send email</strong>.
</p>
<div class="callout callout-tip">
<strong>Corrections</strong>
<p>
Once a voucher has been issued its details can't be edited, because the PDF has
already gone out. If something was typed wrongly, void it and issue a new one.
Each voucher has its own number (like PF-K7M2-9QXA); ask for it when someone
redeems a voucher, and check it here.
</p>
</div>

<h4 id="online-vouchers">Vouchers bought on the website</h4>
<p>
Gift vouchers are also sold on the public <strong>Gift Vouchers</strong> page.
The buyer chooses a voucher (5-Lesson or 10-Lesson), enters their own name and
email (twice, to catch typing slips), the recipient's name, the recipient's email
if they would like it sent straight to them, a description (it starts as
“5-Lesson Voucher for <em>name</em>” and can be changed) and a personal message,
then pays on eWAY's secure page. As soon as eWAY confirms the payment the Portal
creates the voucher and emails it — you don't need to do anything for a normal
sale.
</p>
<ul>
<li>The <strong>buyer</strong> gets the voucher PDF by email, with both studio
mailboxes blind-copied so you see every sale. The <strong>recipient</strong>
gets their own email with the voucher and the personal message (only if the buyer
gave an address). The buyer sees a thank-you page straight after paying.</li>
<li>These vouchers show an <strong>Online</strong> label on the Vouchers page; use
the <strong>Source</strong> filter to list just them. They aren't tied to a studio
and can be used at either one. Click a voucher to see the payment (order number,
eWAY transaction, amount) and whether each email was delivered.</li>
<li><strong>Email again.</strong> Open the voucher and press <strong>Email
again</strong>. Choose the buyer, the recipient or both, and correct an address
first if it was mistyped (a corrected address is saved on the voucher).</li>
<li><strong>Needs a look.</strong> If something needs attention (a paid voucher
whose email hasn't gone, a payment eWAY approved that couldn't be turned into a
voucher, or a payment still waiting after half an hour) a panel at the top of the
page lists it. Press <strong>Check payment</strong> to ask eWAY again, or
<strong>Open</strong> to resend. The Portal also re-checks and retries by itself
every few minutes, so most of these clear without help.</li>
<li><strong>Refunds.</strong> Refund the customer in MYeWAY first, then open the
voucher and press <strong>Mark refunded…</strong>. The voucher is voided so it
can't be used. (Use <em>Void</em> only for a voucher that was <em>not</em> paid
for online.)</li>
</ul>
<div class="callout callout-tip">
<strong>Changing prices</strong>
<p>
The two prices are set in the website code, not in the Portal. Ask your developer
to change them; the Gift Vouchers page picks the new prices up automatically.
</p>
</div>

<h3 id="ticket-sales">Concert Ticket Sales</h3>
<p>
Concert tickets are sold online on the public <strong>Tickets</strong> page of
the website. A parent enters their name, email, the performer they are coming to
see and how many tickets they want, pays on eWAY's secure page, and the Portal
checks with eWAY that the payment really went through before it emails their
tickets. Each ticket is a PDF page with the event, the performer's name, a
unique ticket number and a QR code. You don't need to do anything for a normal
sale.
</p>
<p><strong>Switch sales on.</strong> Open the concert under
<strong>Events</strong>, press <strong>✏️ Edit</strong>, tick
<strong>Sell tickets online</strong> and set the price (the usual $15.00). You can
add a short note that appears on the ticket page and on every ticket (for
example “Doors open 12:30 PM”). The event must be <em>Open</em> or
<em>Closed</em>, not <em>Draft</em>. Tickets stop selling by themselves once the
event date has passed; untick the box to stop sooner. Then press
<strong>🎟️ Ticket sales</strong> on the event page.</p>
<p><strong>Orders.</strong> The Ticket sales page shows tickets sold, takings, how
many people have been admitted and anything that <em>needs attention</em>. Click
an order to see its tickets and what happened to the payment.</p>
<ul>
<li><strong>Email tickets / Email again…</strong> sends the PDF again. Use it when
the parent can't find the email — you can correct a mistyped email address or a
misspelt name first; the tickets are rebuilt with the corrected names.</li>
<li><strong>Check payment with eWAY</strong> (for orders still “Awaiting payment”
or “Failed”) asks eWAY again. If the parent did pay but closed the page before
being sent back, this issues and emails their tickets. The Portal also does this
automatically every ten minutes.</li>
<li><strong>Mark refunded…</strong> — refund the money in <strong>MYeWAY</strong>
first, then press this so the tickets are cancelled and can't be used at the
door. It doesn't move any money itself.</li>
</ul>
<p><strong>By performer</strong> shows how many tickets each student has sold, and
<strong>Export CSV</strong> downloads all orders for a spreadsheet.</p>
<p><strong>On the night — Door check-in.</strong> Open the
<strong>Door check-in</strong> tab on a phone, tablet or laptop that is signed in
to the Portal. Scan a ticket's QR code with the phone's camera (it opens the
Portal and shows the ticket), or type or scan the ticket number into the box.
The page shows the performer, the purchaser and a colour: <span style="color:#2563eb"><strong>blue</strong></span> = valid, press
<strong>Admit</strong>; <span style="color:#dc2626"><strong>red</strong></span> = already used,
void (refunded) or not found — don't admit. Tick <strong>Admit automatically</strong>
for a busy door and valid tickets are admitted the moment they are scanned.
A family arriving together can be admitted in one go with <strong>Admit the other
… in this order too</strong>. <strong>Undo</strong> reverses a mistake.
A ticket can be admitted only once, even if two devices scan it at the same
moment.</p>
<div class="callout callout-tip">
<strong>Good to know</strong>
<p>
Tickets are only issued after eWAY confirms the payment, so a screenshot of a
“thank you” page is not a ticket. Letters outside the usual Western alphabet
(for example Chinese characters) are shown as “?” on the PDF itself; the email
and this page show the name in full. Tickets can't be sold by phone through this
page — if you take a phone payment, issue those tickets yourself as you did
before.
</p>
</div>

<h3 id="posters">Posters &amp; Leaflets</h3>
<p>
Open an event under <strong>Events</strong> and choose <strong>Posters &amp; leaflets</strong>
to make an A3 poster for the studio wall or an A6 leaflet to hand out. The event's
name, date, times, venue, ticket price and booking deadline are filled in for you,
along with two QR codes: one for buying tickets and one for performers to book
their spot. The number of performance spots comes from the event's blocks and
slots (for a 12&ndash;7 PM concert with 12 performances an hour, that is 84).
</p>
<ol>
<li>Pick <strong>Poster</strong> or <strong>Leaflet</strong>, then <strong>Office printer</strong>
(exact size; leaflets come four to an A4 sheet) or <strong>Print shop</strong> (3&nbsp;mm bleed
and crop marks).</li>
<li>Switch the ticket box, the performer box and the &ldquo;limited to N spots&rdquo; line on or off.
Only keep the spots line when it is true.</li>
<li>Adjust the wording if you like. The picture updates as you type. Put things like
&ldquo;Doors open at 11:30 AM&rdquo;, &ldquo;Parking available&rdquo; in <strong>Extra details</strong>, one per line.</li>
<li>Click <strong>Print or save as PDF</strong>. In the print window choose paper size A3 (poster) or
A4 (leaflet sheet), scale 100%, margins None.</li>
</ol>
<div class="callout callout-tip">
<strong>Good to know</strong>
<p>
<strong>Remember this wording for the event</strong> keeps your invitation sentence and extra
details so the next poster for that event starts with them. The QR code buttons give you
PNG pictures for newsletters and social media, and <strong>Draft an announcement email</strong>
opens a ready-made message in Notifications for you to check and send &mdash; nothing is sent
from the poster page. Always scan a QR code with your phone before printing a lot of copies.
</p>
</div>

<h2 id="teaching">Teaching</h2>
<p>
Teaching covers the actual timetable: scheduling lessons, managing the
student roster, and maintaining the teacher directory.
</p>

<h3 id="lessons">Lessons</h3>
<p>
The lesson timetable, with Daily, Weekly and Monthly views. Use
<code>‹ Today ›</code>, the date picker, or the Studio / Status / Student
filters above the grid to find what you need — picking a specific student
automatically switches you to Monthly view.
</p>
<h4>Seeing one teacher's week</h4>
<p>
Pick a name in the <strong>All teachers</strong> filter and the Lessons page
switches to Weekly view and shows that teacher's week as a grid: the days
Monday to Sunday across the top, the time slots down the side, and each
lesson in its slot with the same details you see on the Daily grid (student
or group, instrument, online badge, notes, attendance). Use the
<code>‹ ›</code> arrows to move to earlier or later weeks, and
<strong>Today</strong> to come back to this one.
</p>
<ul>
<li>Lessons the teacher is <strong>covering</strong> for a colleague appear
in their week marked "Covering…", and their own lessons that someone else
is covering are marked "Covered by…".</li>
<li>Shaded cells are outside the teacher's availability. Click any empty
cell to add a lesson prefilled for that teacher, studio, day and time.</li>
<li>The Studio filter still applies. The teacher and student filters work
one at a time — choosing one clears the other. Choose <strong>All
teachers</strong> (or click "show all teachers") to go back.</li>
</ul>
<h4>Adding a lesson</h4>
<ul>
<li>Click <strong>+ Add Lesson</strong>, or click directly on an empty slot
on the grid to prefill the teacher, studio, day and time.</li>
<li>Choose <strong>Private</strong> (one student) or <strong>Group</strong>
(up to six) — picking the "Band" instrument switches this to Group
automatically. Tick <strong>No student</strong> instead for a
non-teaching block like supervision or admin time.</li>
<li>Pick the Teacher, Studio, Instrument, Day, Start time and Duration, then
add students.</li>
<li>Choose the pattern: a <strong>Repeating lesson</strong> (weekly or
fortnightly, running indefinitely, for a fixed number of lessons, or until
a chosen end date) or a <strong>One-off lesson</strong> (Makeup lesson,
Trial lesson, or a one-off request). Adding a trial student to the roster
locks the pattern to a one-off trial automatically.</li>
</ul>
<p>
On Save, the Portal checks — in order — that the roster fits the lesson
type, the teacher actually teaches that instrument, the teacher has an
<strong>availability window</strong> covering that studio/day/time, and that
nothing else clashes for that teacher or any of the students. All of these
are hard blocks: the lesson won't save until they're resolved.
</p>
<h4>Editing a lesson occurrence</h4>
<p>
Click any lesson on the grid to open it. From here you can:
</p>
<ul>
<li>Mark it as a <strong>makeup lesson</strong>, or record it as
<strong>covered</strong> by another staff member (which also moves it onto
their own schedule) or by someone external (name only, no login).</li>
<li>Mark <strong>attendance</strong> per student: Present, Absent — No
Credit, Absent — Notice Given, or Teacher Cancelled.</li>
<li>Add a one-lesson-only guest, or toggle <strong>Online lesson</strong>
(which offers to email students the teacher's Zoom link).</li>
<li><strong>Clone to new timeslot</strong> — creates a brand-new one-off
lesson with the same roster at a different date/time. Great for a quick
makeup slot.</li>
<li><strong>Cancel this lesson only</strong>, <strong>this + all future</strong>,
or <strong>the entire series</strong> — all of these keep past history
intact and free the slot for rebooking; only future, unmarked occurrences
are actually removed. You'll always be asked whether to email the
student(s). Anything you type in <strong>Occurrence notes</strong> when
cancelling is shown to the teacher and the student as "Note from the
studio", and the teacher can still add a lesson note (e.g. a recorded
lesson link) to a cancelled lesson.</li>
<li><strong>Edit series</strong> to change the recurring pattern itself —
this rebuilds future, unmarked occurrences only; anything already marked
or in the past is left untouched.</li>
</ul>
<div class="callout callout-tip">
<strong>Trial and makeup lessons are "one-off," not a mini-series</strong>
<p>
A trial, makeup, or one-off request lesson is stored as a single-occurrence
lesson, not a repeating one — so cloning or editing it never accidentally
turns it into a recurring series.
</p>
</div>
<p>
<strong>Agenda PDF:</strong> pick a teacher and date to preview and print a
one-page agenda for that teacher's day.
</p>

<h3 id="students">Students</h3>
<p>
The student roster — Trial, Active and Inactive students (prospective and
lapsed enquiries live on the Enquiries page instead).
</p>
<ul>
<li><strong>Add/Edit Student:</strong> click a student's name in the list
(or the Edit button) to open their details. First/last name, an email (optional —
leave it blank for a sibling sharing a family login), phone, studio,
status, and up to five instruments with a skill grade each. You need
either a student email or a parent email so the family stays reachable.</li>
<li><strong>Additional Notes:</strong> a short note (up to 50
characters) at the very bottom of the Add/Edit window — for something worth
remembering at a glance, like "Prefers Thursday lessons". A counter shows how
many characters you have left. It's for internal use only, so keep it
factual.</li>
<li><strong>View Tasks:</strong> at the bottom-left of the Edit window.
It lists every task about this student — open and closed, with open ones
first — and clicking one takes you to the Tasks page with that task open. The
number in brackets is how many tasks there are. If the student has no tasks the
button is greyed out. If you've changed anything in the window without saving,
you'll be asked before it takes you away.</li>
<li><strong>Instruments &amp; grade:</strong> add or remove an instrument
row and pick a <strong>Grade</strong> from the dropdown (Foundation /
Beginner / Intermediate / Advanced tiers) — this is the only place to
change a student's instruments or grade; there's no separate grading
screen. Saving records the change in the student's permanent grade
history, so re-saving without changing the grade never creates a
duplicate entry.</li>
<li><strong>Enrolment:</strong> a Trial student gets an "Enrol…" action to
start ongoing lessons; an Active student gets "End enrolment" instead,
which can be planned for a future date or started immediately — either way
it walks through a short checklist rather than just flipping a status.</li>
<li><strong>Reset PW</strong> sends a password-reset email (only if the
student has their own login); <strong>Add login</strong> creates one for a
student who doesn't have one yet.</li>
<li><strong>Finance Follow-up</strong> (Trial/Active students only) emails
the family about a failed payment and creates a follow-up task in one
click — see below.</li>
<li><strong>CSV Import</strong> lets you bulk-load students from a
spreadsheet (a template is provided) — up to 1000 rows at a time, matched
to existing records by email.</li>
</ul>
<div class="callout callout-tip">
<strong>Finance Follow-up replaces the Gmail-then-task two-step</strong>
<p>
Click <strong>Finance Follow-up</strong> next to a Trial or Active
student to send a fixed "Urgent: Finance Follow-up" email about a failed
payment, and automatically create a task — assigned to you, in your
currently selected studio, due the next day — with a log entry already
explaining what happened. From there it's chased like any other task:
log each contact attempt in its contact log, and once the payment goes
through, just tick it done — that's it, no second email, no follow-up
prompt. The button itself only ever sends the one email; use it again by
hand if you ever need to send another.
</p>
</div>
<div class="callout callout-tip">
<strong>There's no delete button — and that's deliberate</strong>
<p>
Removing a student would break their lesson and attendance history, so
the supported path is always <strong>End enrolment</strong> (for a real
student) or handling it on the Enquiries page (for a prospect). If you
think a record genuinely needs to be removed, talk to your superuser.
</p>
</div>
<div class="callout callout-warning">
<strong>"End enrolment" doesn't flip the status instantly</strong>
<p>
A student only becomes Inactive once their last booked lesson has passed —
until then they may show "Leaving after [date]" while their status column
still reads Active. That's expected, not a bug.
</p>
</div>
<div class="callout callout-tip">
<strong>Ending lessons tidies up their tasks</strong>
<p>
When you end a student's lessons during End enrolment, the Portal quietly
closes their other open tasks (including recurring ones) and takes them off
any recurring task they were on. Each closed task gets a note saying "Task
completed due to student stopping lessons", with the last lesson date. "Mark
student inactive" and the End enrolment checklist's own tasks are left for you.
</p>
</div>

<h3 id="teachers">Teachers</h3>
<p>
The teacher directory — profile, instruments taught, studios, and weekly
availability.
</p>
<ul>
<li><strong>Add/Edit Teacher:</strong> name, email (this creates their
login — a one-time temporary password is shown for a new teacher), phone,
Zoom link, teaching room, instruments taught, and studios.</li>
<li><strong>Availability</strong> is a list of Day / Studio / Start time /
End time rows. The Portal blocks any two rows that overlap for the same
teacher, whether at the same studio or a different one. Saving replaces
the teacher's entire availability, so review the full list before saving,
not just the row you changed.</li>
<li><strong>View</strong> opens a read-only detail page for that teacher —
their profile, availability, upcoming schedule, and current student
roster with grades. To change anything, come back to this page and use
Edit.</li>
<li><strong>Deactivate</strong>, not Delete, is how you remove a teacher from
active duty — it keeps their history intact and lets them come back later.
Deleting a teacher isn't offered in the Portal at all.</li>
</ul>
<div class="callout callout-warning">
<strong>Deactivating a teacher doesn't touch their lessons</strong>
<p>
Their existing lesson series keep running until you separately edit or
cancel them — deactivating only changes their login status.
</p>
</div>
<div class="callout callout-tip">
<strong>An untagged teacher can be booked for anything</strong>
<p>
The "must teach this instrument" check on Lessons only applies once a
teacher has at least one instrument selected here. Leaving Instruments
taught empty for a teacher means the scheduling check for them is
effectively switched off.
</p>
</div>

<h2 id="curriculum">Curriculum</h2>
<h3 id="artefact-library">Artefact Library</h3>
<p>
A catalogue of teaching materials — chord charts, songs, backing tracks and
other resources kept on the studio's Google Drive — organised by
instrument, grade and skill component (Repertoire, Technique, or Musical
Knowledge), so teachers can pick from it when writing up a lesson note.
</p>
<ul>
<li><strong>+ Add Artefact:</strong> Title, Instrument, Grade, Component, an
optional description, the Google Drive share link, and tags. The file
itself stays on Drive — the Portal only stores the link.</li>
<li><strong>Search and filter</strong> by title/description/tag, instrument,
grade or component. Tick <strong>Show retired</strong> to see items taken
out of rotation, or <strong>Teacher-added only</strong> to see what
teachers have contributed themselves.</li>
<li><strong>Retire / Reactivate</strong> toggles whether an item is offered
to teachers — nothing is ever hard-deleted, since a past lesson may still
reference it.</li>
</ul>
<p>
Teachers can add their own artefacts on the fly from their lesson-note
screen. These arrive here as <strong>Pending review</strong> (shown with a
count in the page header) — use <strong>Approve</strong> to make one
available to every teacher, or <strong>Discard</strong> if it's not worth
keeping (this doesn't delete it — a discarded item can still be restored
from under "Show retired").
</p>
<div class="callout callout-tip">
<strong>The Grade ladder is universal — the library itself is Guitar-only</strong>
<p>
The Foundation → Beginner → Intermediate → Advanced grade ladder used here
is the same one used everywhere else in the Portal, for every instrument.
The Artefact Library's actual content, however, has only ever been built
out for Guitar — the Instrument dropdown lists every instrument, but don't
expect a matching library of materials for anything other than Guitar yet.
</p>
</div>

<h2 id="reports">Reports</h2>
<h3 id="attendance">Attendance</h3>
<p>
A per-student rollup of lessons, presence, absence types and attendance
rate over a date range.
</p>
<ul>
<li><strong>Filters:</strong> Studio, Teacher, Instrument, and a From/To
date range (defaults to the last 90 days).</li>
<li><strong>Search</strong> by student name, and tick <strong>Only below
80%</strong> to focus on students whose attendance needs attention.</li>
<li>Click any column header to sort — the report opens sorted by Rate,
worst first.</li>
<li>Click a student's row to see every lesson counted in the range, with
date, teacher, instrument and status.</li>
<li><strong>⬇ Export CSV</strong> downloads the full underlying dataset for
the current filters and date range (it isn't limited by the "Only below
80%" checkbox or the search box, so the file may contain more rows than
you currently see on screen).</li>
</ul>
<div class="callout callout-tip">
<strong>How the rate is calculated</strong>
<p>
Only lessons that have actually <strong>ended</strong> are counted — a
lesson still to come, or in progress, is never counted as missed. An
<strong>unmarked</strong> lesson counts against the student, which is
deliberate: it's the incentive for marking attendance promptly.
Teacher-cancelled lessons are tracked (visible in the CSV export) but
don't count for or against the student's rate, since the lesson not
happening wasn't their doing.
</p>
</div>

<h3 id="portal-logins">Portal Logins</h3>
<p>
Shows, for every active and trial student, whether they have ever signed in
to the Student Portal and whether they have finished setting their own
password. Use it to see who still hasn't started using the Portal, and to
nudge them with one click. The cards at the top count <strong>logins</strong>,
not children: siblings who share one family login are a single row (tagged
"family login") and get a single reminder.
</p>
<ul>
<li><strong>Never signed in</strong> — the account exists but has never been used.</li>
<li><strong>Setup unfinished</strong> — they signed in (for example by clicking
the original link) but haven't changed the temporary password yet.</li>
<li><strong>Set up</strong> — signed in and chose their own password.</li>
<li><strong>No login yet</strong> — the student has no Portal account at all.
They can't be reminded from here; use <strong>Add login</strong> on the Students
page first.</li>
</ul>
<p>
The page opens on <strong>Needs a reminder</strong> (never signed in plus
setup unfinished), filtered to your studio. Tick the people you want, or
click <strong>Select all shown</strong>, then <strong>Send reminder…</strong>.
You can edit the wording before sending. The email lists what the Portal
offers (lesson notes and feedback, progress and grading, shared materials,
booking the concert) and asks them to visit the Portal sign-in page, using
<strong>Forgot password?</strong> if they don't have their password handy.
It is sent individually from each student's own studio address, parents on
file receive it too, and the studio gets the usual summary copy.
</p>
<div class="callout callout-tip">
<strong>No double-reminding</strong>
<p>
The <em>Last reminded</em> column shows when a login was last sent this
reminder. <strong>Select all shown</strong> skips anyone reminded in the last
3 days; you can still tick them by hand. <strong>Export CSV</strong>
downloads the list currently on screen.
</p>
</div>

<h3 id="distribution-lists">Distribution Lists</h3>
<p>
Distribution Lists don't send anything themselves — they generate a
ready-to-paste list of email addresses for a message you send yourself from
Gmail. Use this instead of Notifications whenever you expect a reply, need
to attach a file, or want the message to come from your own studio Gmail
address.
</p>
<ul>
<li><strong>All active students — all studios</strong> — active students
only, loads automatically.</li>
<li><strong>By studio</strong> — active and trial students at the studio you
pick.</li>
<li><strong>By teacher</strong> — active and trial students currently having
lessons with the teacher you pick.</li>
<li><strong>By instrument</strong> — active and trial students currently
enrolled to learn the instrument you pick.</li>
</ul>
<p>
Each list shows the address count, a click-to-copy button, and warnings for
any student skipped for having no email on file or an invalid-looking
address. Each student contributes exactly one address (their own login
email if they have one, otherwise their own contact email, otherwise a
parent's) — unlike Notifications, which emails every valid address it finds
for a student.
</p>
<div class="callout callout-caution">
<strong>Always paste the list into Bcc — never To or Cc</strong>
<p>
Put your own studio address in the To field and paste the copied list
into <strong>Bcc</strong>. This keeps every family's address private from
every other family and avoids a reply-all storm — it's the entire reason
to use Gmail for this instead of Notifications.
</p>
</div>
<div class="callout callout-warning">
<strong>Gmail has a recipient limit</strong>
<p>
Gmail caps a single email at roughly 500 combined recipients. The page
warns you as a list approaches or passes that number, but it won't split
the list for you — if you're over the limit, send it in two batches.
</p>
</div>

<h2 id="superuser">Super User (if you have access)</h2>
<p>
The Super User section only appears for superuser accounts. It's where the
studios themselves and the admin accounts that manage them are configured.
</p>

<h3 id="studios">Studios</h3>
<ul>
<li><strong>+ Add Studio:</strong> name, address, and the studio's own
Gmail address (used to send notifications and as the reply-to for
Portal emails).</li>
<li>Each studio card shows how many admins have access to it — an admin
with no studios explicitly ticked on their account has access to
<em>every</em> studio, not none.</li>
<li><strong>Deactivate</strong> is the safe, reversible way to take a studio
out of use.</li>
</ul>
<div class="callout callout-caution">
<strong>Delete is permanent</strong>
<p>
Deleting a studio is blocked while it still has active lessons, but once
that check passes, the delete cannot be undone. Use Deactivate unless you
are certain the studio should be permanently removed.
</p>
</div>

<h3 id="admins">Admins</h3>
<ul>
<li><strong>+ Add Admin:</strong> name, email (their login), phone, and
<strong>Studio Access</strong> — tick the studio(s) this admin should be
limited to, or leave every box unchecked for access to all studios.</li>
<li>Creating an admin shows a one-time password screen with their temporary
login details to pass on — they'll be asked to set their own password on
first login.</li>
<li><strong>Reset PW</strong> sends a password-reset email to an existing
admin.</li>
<li><strong>Deactivate</strong> is the reversible option for an admin who's
left or is on leave.</li>
</ul>
<div class="callout callout-caution">
<strong>Delete here is permanent — and unlike other parts of the Portal,
there's no history check</strong>
<p>
Deleting an admin permanently removes their account and login, with no
check for existing history referencing them. Prefer Deactivate unless
you're certain permanent removal is what you want.
</p>
</div>
<div class="callout callout-tip">
<strong>"Leave all unchecked" means all studios, not none</strong>
<p>
The same convention as Studios: an admin with no Studio Access boxes
ticked can see and manage every studio, which is easy to get backwards
when setting up someone meant to be limited to just one.
</p>
</div>

<h3 id="teacher-utilisation">Teachers Utilisation</h3>
<p>
A superuser-only report showing how much of a teacher's available time was
actually used. Choose a <strong>teacher</strong> and a <strong>From</strong> and
<strong>To</strong> date (both days are included). It opens on the last
Wednesday-to-Tuesday fortnight; <strong>Last Wed–Tue fortnight</strong> returns
to it.
</p>
<p>
There is one column for each day the teacher has availability or lessons, titled
with the weekday, date and studio, and a <strong>Total</strong> column at the
end. The rows are:
</p>
<ul>
<li><strong>Availability</strong> — the teacher's availability that day, for
example 03:00 PM-08:00 PM (5 Hrs).</li>
<li><strong>Lessons booked</strong> — how many lessons were scheduled and their
total time.</li>
<li><strong>Lessons taught</strong> — booked lessons less the no-shows
(cancelled, or every student Absent — no credit, Absent — notice given or
Teacher cancelled), with the share of lessons booked and of booked time.</li>
<li><strong>Billable lessons</strong> — lessons where a student was marked
Present, again as a share of lessons booked and of booked time.</li>
</ul>
<div class="callout callout-caution">
<strong>Lessons that haven't been marked yet</strong>
<p>
A lesson that has not been marked (including one still in the future) counts as
taught but is not billable until a student is marked Present. The note under the
grid says how many are still unmarked, so run the report after attendance is up
to date. A group lesson counts once, however many students are in it, and a
lesson covered by another teacher counts for the teacher who took it. The
availability shown is the teacher's current weekly availability, so changing it
also changes how past periods look.
</p>
</div>
<p><strong>Export CSV</strong> downloads the same figures as plain numbers for a
spreadsheet, and <strong>Print</strong> prints just the grid.</p>
