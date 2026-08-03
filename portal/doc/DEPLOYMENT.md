# Pathfinder Music Lessons — Deployment & Development Guide

**Version:** 1.0
**Date:** 31 July 2026
**Companion documents:** `Requirements_Specification_v0_4.md`,
`TECHNICAL_SPECIFICATION.md`

Two audiences: **Part A** is for setting the stack up from scratch or
understanding how it was configured. **Part B** is the day-to-day workflow.

---

# Part A — Setting up the stack

## A1. Repository layout

```
/                              repo root
├── index.html, teachers.html, pricing.html …    marketing site
├── README.md
├── netlify.toml
├── .gitignore                 must exist before .env is created
├── .env.example               documents required variables
├── .env                       real values — NEVER committed
│
├── netlify/functions/
│   ├── create-user.js
│   └── send-email.js
│
├── supabase/                  migrations, in order
│   ├── zoho-migration.sql
│   ├── phase3-email.sql
│   ├── teacher-rls-fix.sql
│   ├── teacher-skill-insert-policy.sql
│   ├── student-schedule-view.sql
│   ├── per-student-attendance.sql
│   └── student-contact-email.sql
│
└── portal/
    ├── *.html
    ├── css/portal.css
    └── js/supabase-client.js
```

`netlify.toml`:

```toml
[build]
  functions = "netlify/functions"

[[redirects]]
  from = "/portal"
  to   = "/portal/login.html"
  status = 200
```

No build command and no `package.json` in the functions directory — the Functions
use the built-in `fetch` and have no dependencies. An earlier version required
`@supabase/supabase-js`; removing it made deploys faster and simpler.

---

## A2. Supabase

### Create the project
Note the project reference from the URL — `https://<ref>.supabase.co`.

### The two keys

**Project Settings → API Keys → "Legacy anon, service_role API keys"** — use the
*legacy* tab. The newer `sb_publishable_...` and `sb_secret_...` formats are **not
compatible** with the Supabase JS v2 client or the Admin REST API used by the
Functions. This costs an hour if you discover it the hard way.

| Key | Starts | Goes in | Visible to |
|---|---|---|---|
| **anon** | `eyJ...` | `portal/js/supabase-client.js` | Everyone — it ships to the browser |
| **service_role** | `eyJ...` | Environment variables only | Server only |

Both are JWTs beginning `eyJ`, which makes them easy to confuse. To check which
you hold, decode the payload and read the `role` claim.

> **The anon key being public is correct** — RLS decides what it can reach.
> **The service_role key bypasses RLS entirely.** If it ever appeared in a file
> under `portal/`, every visitor would have unrestricted read and write access to
> every student record.

### Run the migrations
SQL Editor, in the order listed in A1. Each is re-runnable. Several end with a
verification query — read the output rather than assuming success.

### URL configuration
**Authentication → URL Configuration:**

- Site URL: `https://www.pathfindermusiclessons.com.au`
- Redirect URLs:
  - `https://www.pathfindermusiclessons.com.au/portal/change-password.html`
  - `http://localhost:8888/portal/change-password.html` — for local testing

Without the localhost entry, reset links tested locally bounce to production.

### Create the Super User
1. **Authentication → Users → Add user** — email and password
2. Copy the UUID
3. Insert the profile:

```sql
INSERT INTO profiles (id, first_name, last_name, role, status, must_change_password)
VALUES ('<uuid>', 'First', 'Last', 'superuser', 'active', false);
```

Every other account is created through the portal.

---

## A3. Resend

1. Sign up and **verify the domain** — the root domain, so `From` can be any
   address on it. No per-address setup; a new studio only needs its email set on
   the Studios page.
2. Add the DNS records Resend provides (see A4).
3. **API Keys → Create** — this key is used in two places: the Netlify environment
   variable, and Supabase's SMTP password.

**Free tier is 100 emails/day.** A studio-wide announcement to 500 students
exceeds it in one send. Budget for the paid tier before first bulk use.

### Route Supabase auth emails through Resend

**Supabase → Project Settings → Authentication → SMTP Settings:**

| Field | Value |
|---|---|
| Host | `smtp.resend.com` |
| Port | `465` (try `587` if it fails) |
| Username | `resend` — literally that word |
| Password | Your Resend API key |
| Sender email | `info@pathfindermusiclessons.com.au` |
| Sender name | `Pathfinder Music Lessons` |

Then **Authentication → Rate Limits** — confirm email sending is around 30/hour
rather than the built-in 2/hour.

Finally **Authentication → Email Templates → Reset Password** — replace the
default to remove the Supabase branding.

> **Trade-off:** password resets now depend on Resend. During an outage, the
> fallback is setting a password directly in Supabase → Authentication → Users.

---

## A4. DNS

Hosted on Netlify DNS. Resend and Google Workspace coexist because their records
are on different hostnames.

| Type | Name | Purpose |
|---|---|---|
| MX | apex | Google — receives all mail |
| TXT | apex | Google SPF — **leave untouched** |
| TXT | `google._domainkey` | Google DKIM |
| TXT | `resend._domainkey` | Resend DKIM |
| MX | `send` | Resend bounces |
| TXT | `send` | Resend SPF — **subdomain only** |
| TXT | `_dmarc` | `v=DMARC1; p=none;` |

> **Never add a second SPF record to the same hostname.** Two on one host break
> authentication for both systems. Two on different hosts, as here, is correct.

Netlify's Name field appends the domain automatically — enter `send`, not
`send.pathfindermusiclessons.com.au`. Don't wrap values in quotes; Netlify adds
them. Copy DKIM values in full — they're several hundred characters and a
truncated paste fails verification with no useful error.

**Google DKIM needs enabling separately.** Admin → Apps → Google Workspace →
Gmail → Authenticate email → **Start authentication**. The DNS record alone
doesn't switch it on.

---

## A5. Netlify

Connect the GitHub repository. No build command; publish directory is the root.

**Site configuration → Environment variables:**

| Variable | Secret? | Value |
|---|---|---|
| `SUPABASE_URL` | **No** | `https://<ref>.supabase.co` — no trailing slash |
| `SUPABASE_SERVICE_KEY` | **Yes** | The legacy service_role key |
| `RESEND_API_KEY` | **Yes** | Your Resend key |

> **Do not mark `SUPABASE_URL` as secret.** Netlify's secret scanner will find it
> in your JavaScript — where it legitimately belongs — and **fail the build**.
>
> **Secret variables cannot be read back**, by you or the CLI. Local development
> therefore needs its own `.env` copied from the original sources.
>
> Variables cannot be edited once marked secret — delete and recreate.

Finally, put the anon key and project URL into `portal/js/supabase-client.js`.

---

# Part B — Development and deployment

## B1. Why local development matters

**Netlify charges roughly 15 credits per production deploy, flat.** One session
spent 1,005 of 1,015 credits across 67 deploys — nearly all single-file changes.
Bandwidth, functions and compute together came to under 10.

Deploying to test is the single most expensive habit available. Local development
removes it entirely.

## B2. One-time setup

Requires **Node.js** and **Git**.

```bash
git clone https://github.com/<org>/<repo>.git pathfinder
cd pathfinder
npm install -g netlify-cli
netlify login
netlify link --name <your-netlify-site-name>
```

> If `netlify link` reports "no project specified in non-interactive mode", pass
> the name explicitly as above. Linking is a convenience — `netlify dev` works
> unlinked, since the secret variables can't be pulled from Netlify anyway.

### `.gitignore` — create and commit this *before* `.env`

```
.env
.env.local
.netlify/
node_modules/
.vscode/
.DS_Store
Thumbs.db
```

```bash
git add .gitignore && git commit -m "Add gitignore" && git push
```

### `.env`

```
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_SERVICE_KEY=eyJ...
RESEND_API_KEY=re_...
```

> **No quotes.** Netlify's parser doesn't strip them, so the key arrives malformed
> and Supabase rejects it with "Invalid API key".
>
> **The service_role key, not the anon key.** Using the anon key produces
> `not_admin: User not allowed`.
>
> **Watch for `.env.txt`.** Notepad appends `.txt` silently and Explorer hides
> known extensions. Check with `dir .env*`.

Verify with `git status` — `.env` must **not** appear.

## B3. Daily workflow

```bash
netlify dev
```

Open **http://localhost:8888/portal/login.html**

Serves the static files and runs `/.netlify/functions/*` locally against the
**real** Supabase and **real** Resend.

| Changed | Action |
|---|---|
| Anything in `portal/` | Browser refresh — `Ctrl+Shift+R` if it looks stale |
| `netlify/functions/*.js` | Nothing — hot-reloads |
| `.env` or `netlify.toml` | Restart `netlify dev` |

### Three things to keep in mind

**Emails are real.** They go to actual inboxes and count against your daily quota.
Use `yourname+alias@gmail.com` for test recipients — every variant reaches your
own inbox but counts as a distinct address. Resend rejects `example.com`.

**The database is production.** Deleting a student locally deletes them for real.

**PowerShell prints stderr in red.** Git progress, npm warnings and the Netlify
CLI's startup output all look like failures and aren't. The real signal is the
prompt returning with nothing working, or the word `error` rather than `warn`.

## B4. Deploying

Don't compare files by hand — Git already knows.

```bash
git status          # what changed
git diff            # the actual changes
```

VS Code's Source Control panel shows the same as a side-by-side diff.

```bash
git add -A
git commit -m "what changed and why"
git push
```

If auto-publish is on, Netlify deploys automatically. To batch more aggressively,
turn it off under **Site configuration → Build & deploy → Continuous deployment**
and deploy manually from **Deploys → Trigger deploy**.

> Turning off auto-publish means production lags behind `main` until you deploy.
> Keep track, or deploy at the end of each session as a habit.

### There is no separate database deploy

Local development runs against the production Supabase, so **migrations take
effect the moment you run them**, regardless of what code is deployed. Additive
changes are safe. A destructive one would break production instantly — so review
any migration that drops or renames before running it.

### After deploying

Log in to production as a teacher or student and spot-check a number you know.
That's the quickest confirmation the batch landed.

---

## B5. Troubleshooting

| Symptom | Cause |
|---|---|
| "Invalid API key" from a Function | Quotes around the value in `.env`, or `.env.txt` |
| `not_admin: User not allowed` | Anon key in `SUPABASE_SERVICE_KEY` instead of service_role |
| Build fails: "Exposed secrets detected" | `SUPABASE_URL` marked secret — unmark it |
| Login hangs | Trailing slash on `SUPABASE_URL`, or placeholder values in `supabase-client.js` |
| Reset link lands on the homepage | `redirect_to` sent in the body instead of the query string |
| Reset link says `otp_expired` | Link already used, over an hour old, or consumed by an email scanner |
| "Resend rejected the send" | Invalid address in the batch — check the terminal for Resend's message |
| A number looks wrong | **Check the URL first.** Production and localhost show identical data with different code |
| 400 from Supabase on a query | Filtering or ordering on a joined column — fetch separately and merge |

The `netlify dev` terminal is the better debugging surface for anything
server-side. Both Functions log upstream errors there in full.

---

## B6. Operational notes

**Backups.** Supabase's free tier keeps limited automatic backups. Before the
production student import, take a manual snapshot — Database → Backups.

**Monitoring.** Resend's dashboard shows per-email delivery status. `email_log`
records every send with recipient message IDs.

**Adding a studio.** Studios → Add Studio, with a real Google Workspace mailbox
for its address. Resend needs nothing — the domain is already verified. But the
mailbox must exist, or the summary emails and replies both bounce.

---

*Prepared for Pathfinder Music Lessons · pathfindermusiclessons.com.au*
