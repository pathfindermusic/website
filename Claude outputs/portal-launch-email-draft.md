# Portal launch email — ready to paste into Notifications

**Where to send it from:** Notifications → audience **"All active students — every studio"** (new option) → pick a Send-from studio (any studio address works, since this goes to students across all studios) → paste the Subject and Message below exactly as-is, including the `{{first_name}}` and `{{portal_link}}` placeholders — the system fills in a real name and a personal one-time sign-in link for every student when you hit Send.

**Test status:** confirmed working — a test student received the email via Notifications with a live `{{portal_link}}`.

---

## Subject

```
Introducing the New Pathfinder Music Portal — Your Login Inside
```

## Message

```
Hi {{first_name}},

We're excited to introduce the new Pathfinder Music Portal — a place where you can check your lesson schedule, read your teacher's practice notes, track your grading progress, and access any music sheets, recordings or other materials your teacher shares with you.

**The Portal will eventually replace our current student portal. We haven't set the cutover date yet, but we recommend switching over now so you're already comfortable with it when we do.**

YOUR PORTAL LOGIN

Click below to sign in and set your own password. This link is personal to you and only works once, so please don't forward it to anyone else:

[Sign in to the Portal]({{portal_link}})

Once you've set your password, you can always get back in at pathfindermusiclessons.com.au/portal.

GETTING STARTED

Our Student How-to Guide walks you through everything above, step by step:
[Student How-to Guide](https://www.pathfindermusiclessons.com.au/portal/manuals/student-guide.html)

Please note: the guide is only viewable once you've signed in above and set your password — so do that first, then come back to this link.

If you have any questions after reading it, just reply to this email or get in touch with your studio directly.

ONE THING TO KNOW

Unlike our current system, the new Portal does not yet send automatic lesson reminders. If you'd like reminders turned on for your lessons, just let us know and we'll set it up for you.

Kind regards,
Pathfinder Music Lessons
```

---

## What each part does when it's actually sent

- `{{first_name}}` — the student's own first name.
- `{{portal_link}}` — a fresh, one-time "sign in and set your password" link, generated per student at the moment you click Send. It only works for a student who already has a Portal login. Anyone who doesn't gets skipped for this send (not mailed a broken link) and is listed by name in the studio's summary copy, so you can use **Add login** on the Students page for them and message them individually afterward.
- The bold paragraph about replacing the current portal renders as a highlighted callout box, the same style used elsewhere in Portal emails.
- ALL-CAPS short lines (`YOUR PORTAL LOGIN`, `GETTING STARTED`, `ONE THING TO KNOW`) become small section headings automatically.
- The Student Guide page requires being logged in — a student who clicks it before setting their password just gets bounced to the login screen, not shown a useful error. That's why the message tells them to log in first, and why the login section comes before the guide section in the email. Worth keeping that order if you edit the wording.

## Notes

- "Active" here means the student's own status is Active — a trial student is not included, matching what you asked for.
- Every student gets their own individually addressed email (and, where a family shares a login, only one email per login — not one per child).
- A single summary copy of the whole send goes to the sending studio's inbox afterward, listing who received it and who was skipped and why.
