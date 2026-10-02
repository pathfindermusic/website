// ============================================================
// PATHFINDER PORTAL — receive a website enquiry
//
// Creates a prospective student and a follow-up task from the
// website contact form, verifies the visitor with reCAPTCHA, and
// sends the two emails Zoho used to send: an acknowledgement to
// the enquirer and a notification to the studio.
//
// CUTOVER (Oct 2026): the website form no longer posts to Zoho at
// all — this function is now the only destination for a new
// enquiry, and the only thing sending those two emails. (The old
// parallel-run comment used to live here; Zoho is fully out of
// this path now.)
//
// Environment variables required in Netlify:
//   SUPABASE_URL          — project URL
//   SUPABASE_SERVICE_KEY  — legacy service_role key (eyJ...)
//   RESEND_API_KEY        — Resend API key (secret). Without it, the
//                            enquiry still gets created — it just skips
//                            sending the two emails below (logged).
//   RECAPTCHA_SECRET_KEY  — Google reCAPTCHA secret for the sitekey
//                            already on the form. Without it, the
//                            server-side check is skipped (logged) and
//                            only the honeypot + duplicate-email check
//                            guard the form.
// ============================================================

const SUPABASE_URL         = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const RESEND_API_KEY       = process.env.RESEND_API_KEY;
const RECAPTCHA_SECRET_KEY = process.env.RECAPTCHA_SECRET_KEY;

const ALLOWED_ORIGINS = [
  'https://www.pathfindermusiclessons.com.au',
  'https://pathfindermusiclessons.com.au',
  'http://localhost:8888',
];

// The form and the portal disagree about two instruments. These
// values are compared as exact strings everywhere in the portal,
// so a mismatch fails silently rather than erroring.
const INSTRUMENT_MAP = {
  'Voice':            'Voice / Singing',
  'Singing':          'Voice / Singing',
  'Piano':            'Piano / Keyboard',
  'Keyboard':         'Piano / Keyboard',
  'Piano / Keyboard': 'Piano / Keyboard',
};

const CANONICAL = [
  'Guitar','Bass','Drums','Piano / Keyboard','Voice / Singing',
  'Violin','Ukulele','Music Theory','Saxophone','Band','Other',
];

// Used only when a submission's studio can't be resolved (shouldn't
// happen — the form requires a studio — but an enquiry must never be
// silently dropped if it does).
const FALLBACK_EMAIL = 'admin@pathfindermusiclessons.com.au';

exports.handler = async (event) => {
  const cors = {
    'Access-Control-Allow-Origin':  originFor(event),
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers: cors, body: '' };
  if (event.httpMethod !== 'POST')    return json(405, { error: 'Method not allowed' }, cors);

  // Only from our own site. Not a strong control on its own — a
  // determined script can forge it — but it stops casual abuse, and
  // the blast radius is a prospective student record with no login,
  // which an admin can discard in two clicks.
  const origin = event.headers.origin || event.headers.referer || '';
  if (!ALLOWED_ORIGINS.some(o => origin.startsWith(o))) {
    console.warn('[receive-enquiry] rejected origin:', origin);
    return json(403, { error: 'Forbidden' }, cors);
  }

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return json(400, { error: 'Invalid request' }, cors); }

  // Honeypot: a hidden field no person can see. Anything that fills
  // it is automated. Return 200 so the bot learns nothing.
  if (String(body.website || '').trim() !== '') {
    console.warn('[receive-enquiry] honeypot triggered');
    return json(200, { ok: true }, cors);
  }

  // reCAPTCHA is the only thing standing between this form and the
  // open internet now that Zoho (and whatever spam defences it had
  // behind the scenes) is out of the loop.
  const recaptchaToken = String(body.recaptcha_token || '').trim();
  const captchaOk = await verifyRecaptcha(recaptchaToken, clientIp(event));
  if (!captchaOk) {
    console.warn('[receive-enquiry] reCAPTCHA verification failed');
    return json(400, { error: 'Please complete the verification and try again.' }, cors);
  }

  const firstName = clean(body.first_name, 40);
  const lastName  = clean(body.last_name, 80);
  const email     = clean(body.email, 120).toLowerCase();
  const phone     = clean(body.phone, 30);
  const studio    = clean(body.studio, 60);
  const notes     = clean(body.description, 4000);
  const parent    = clean(body.parent_name, 120);

  let instrument = clean(body.instrument, 60);
  instrument = INSTRUMENT_MAP[instrument] ?? instrument;
  if (!CANONICAL.includes(instrument)) instrument = 'Other';

  if (!firstName || !lastName || !email || !isValidEmail(email)) {
    return json(400, { error: 'Missing or invalid required fields' }, cors);
  }

  const headers = {
    'Content-Type':  'application/json',
    'apikey':        SUPABASE_SERVICE_KEY,
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
  };
  const api = (path, opts = {}) =>
    fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers, ...opts });

  try {
    // A double submit, or a browser retry, should not create two
    // enquiries. Same address within the hour is treated as one.
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const dupRes = await api(
      `students?email=eq.${encodeURIComponent(email)}` +
      `&status=eq.prospective&select=id,created_at`);
    const dups = await dupRes.json();
    if (Array.isArray(dups) && dups.some(d => !d.created_at || d.created_at > since)) {
      console.log('[receive-enquiry] duplicate within the hour, ignored:', email);
      return json(200, { ok: true, duplicate: true }, cors);
    }

    // Which studio? Fall back to leaving it unset rather than guessing.
    let studioRecord = null;
    if (studio) {
      const sRes = await api(`studios?name=ilike.${encodeURIComponent(studio)}&select=id,email,name,address`);
      const rows = await sRes.json();
      if (Array.isArray(rows) && rows[0]) studioRecord = rows[0];
    }
    const studioId = studioRecord?.id ?? null;

    // An enquiry has no login account — profiles.id has no foreign
    // key to auth.users, which is what allows this.
    const userId = crypto.randomUUID();

    const pRes = await api('profiles', {
      method: 'POST',
      headers: { ...headers, Prefer: 'return=minimal' },
      body: JSON.stringify({
        id: userId, first_name: firstName, last_name: lastName,
        phone: phone || null, role: 'student', status: 'active',
      }),
    });
    if (!pRes.ok) throw new Error('profiles: ' + await pRes.text());

    const stuRes = await api('students', {
      method: 'POST',
      headers: { ...headers, Prefer: 'return=representation' },
      body: JSON.stringify({
        user_id: userId, status: 'prospective', studio_id: studioId,
        email, parent_name: parent || null,
        first_name: firstName, last_name: lastName,
        enquiry_notes: notes || null,
        enquiry_date: new Date().toISOString().slice(0, 10),
        enquiry_source: 'website',
      }),
    });
    if (!stuRes.ok) throw new Error('students: ' + await stuRes.text());
    const student = (await stuRes.json())[0];

    if (instrument) {
      await api('student_instruments', {
        method: 'POST',
        headers: { ...headers, Prefer: 'return=minimal' },
        body: JSON.stringify({
          student_id: student.id, instrument, skill_level: 0,
        }),
      });
    }

    // Every enquiry gets a follow-up task, due today. Left unassigned
    // so it lands in the studio's queue rather than being pushed at
    // one admin who may not be working.
    await api('tasks', {
      method: 'POST',
      headers: { ...headers, Prefer: 'return=minimal' },
      body: JSON.stringify({
        title:        `Follow up enquiry — ${firstName} ${lastName}`,
        subject_type: 'student', subject_id: student.id,
        studio_id:    studioId,
        due_date:     new Date().toISOString().slice(0, 10),
        source:       'system',
      }),
    });

    // Best-effort — a failed send should never make the browser think
    // the enquiry itself was lost. The prospective student and the
    // follow-up task above are already safely recorded regardless.
    try {
      await sendEnquiryEmails({
        firstName, lastName, email, phone, parent, notes, instrument,
        studioRecord,
      });
    } catch (err) {
      console.error('[receive-enquiry] enquiry emails failed:', err.message);
    }

    console.log('[receive-enquiry] created enquiry for', email);
    return json(200, { ok: true, student_id: student.id }, cors);

  } catch (err) {
    // Never surface a failure to the browser in a way that could lose
    // the enquiry without the visitor knowing. The form shows them an
    // error and lets them retry or call the studio directly.
    console.error('[receive-enquiry] failed:', err.message);
    return json(200, { ok: false, error: 'logged' }, cors);
  }
};

// ============================================================
// reCAPTCHA
// ============================================================

async function verifyRecaptcha(token, remoteIp) {
  if (!RECAPTCHA_SECRET_KEY) {
    // Fail safe rather than fail closed: an unconfigured secret must
    // never take the enquiry form down for every real visitor. It does
    // mean verification is a no-op until the key is set — logged loudly
    // so that's noticed, not silently accepted forever.
    console.error('[receive-enquiry] RECAPTCHA_SECRET_KEY not set — skipping verification');
    return true;
  }
  if (!token) return false;
  try {
    const params = new URLSearchParams({ secret: RECAPTCHA_SECRET_KEY, response: token });
    if (remoteIp) params.set('remoteip', remoteIp);
    const r = await fetch('https://www.google.com/recaptcha/api/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });
    const data = await r.json();
    return !!data.success;
  } catch (err) {
    console.error('[receive-enquiry] reCAPTCHA check failed:', err.message);
    // A Google outage shouldn't block real enquiries from reaching the
    // studio — fail open, same spirit as the rest of this function.
    return true;
  }
}

function clientIp(event) {
  const h = event.headers || {};
  const xff = h['x-nf-client-connection-ip'] || h['client-ip'] || h['x-forwarded-for'];
  if (!xff) return null;
  return String(xff).split(',')[0].trim() || null;
}

// ============================================================
// Emails (Resend) — replaces the acknowledgement + studio
// notification Zoho used to send.
// ============================================================

async function sendEnquiryEmails({ firstName, lastName, email, phone, parent, notes, instrument, studioRecord }) {
  if (!RESEND_API_KEY) {
    console.warn('[receive-enquiry] RESEND_API_KEY not set — enquiry emails skipped');
    return;
  }

  const fromAddr   = studioRecord?.email || FALLBACK_EMAIL;
  const studioName = studioRecord?.name || null;
  const studioAddr = studioRecord?.address || null;

  await sendEmail({
    from:     fromAddr,
    fromName: 'Pathfinder Music Lessons',
    to:       email,
    subject:  `Thanks for your enquiry, ${firstName}!`,
    html:     brandedEmail(
      acknowledgementHtml({ firstName, instrument, studioName }),
      fromAddr, studioAddr,
    ),
  });

  const notifyTo = studioRecord?.email || FALLBACK_EMAIL;
  await sendEmail({
    from:     fromAddr,
    fromName: 'Pathfinder Music Lessons — Website',
    to:       notifyTo,
    replyTo:  email,
    subject:  `New enquiry — ${firstName} ${lastName} (${instrument})`,
    html:     brandedEmail(
      studioNotificationHtml({ firstName, lastName, instrument, studioName, parent, phone, email, notes }),
      fromAddr, studioAddr,
    ),
  });
}

async function sendEmail({ from, fromName, to, replyTo, subject, html }) {
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from:     `${fromName} <${from}>`,
      to:       [to],
      reply_to: replyTo || from,
      subject,
      html,
    }),
  });
  if (!r.ok) throw new Error(`Resend ${r.status}: ${await r.text()}`);
}

// These two emails carry text an enquirer typed into the public
// website form — unlike the Portal's own broadcast emails (see
// send-email.js's emailTemplate), that text is NOT run through any
// **bold**/[link](url) markdown-lite parsing here. Every value below
// goes through escapeHtml only, so a crafted "message" can't turn
// itself into a clickable link or a styled callout in the studio's
// inbox.

function acknowledgementHtml({ firstName, instrument, studioName }) {
  const fn    = escapeHtml(firstName);
  const instr = escapeHtml(instrument);
  const st    = escapeHtml(studioName || 'our studio');
  return `
    <p style="margin:0 0 14px;">Hi ${fn},</p>
    <p style="margin:0 0 14px;">Thanks for reaching out to Pathfinder Music Lessons! We've received your enquiry about <strong>${instr}</strong> lessons at our <strong>${st}</strong> studio.</p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 16px;">
      <tr>
        <td style="width:4px;background:#E8491E;border-radius:2px 0 0 2px;">&nbsp;</td>
        <td style="background:#f5f5f7;padding:14px 16px;border-radius:0 2px 2px 0;font-size:15px;line-height:1.6;color:#1c1c1e;">
          One of our team will be in touch within 1–2 business days to arrange your first lesson.
        </td>
      </tr>
    </table>
    <p style="margin:0 0 14px;">In the meantime, if you have any questions, just reply to this email or give us a call.</p>
    <p style="margin:0;">Talk soon,<br>The Pathfinder Music Lessons team</p>
  `;
}

function studioNotificationHtml({ firstName, lastName, instrument, studioName, parent, phone, email, notes }) {
  const row = (label, value) => `
    <tr>
      <td style="padding:4px 10px 4px 0;color:#666666;font-size:13px;white-space:nowrap;vertical-align:top;">${escapeHtml(label)}</td>
      <td style="padding:4px 0;font-size:14px;color:#1c1c1e;">${escapeHtml(value || '—')}</td>
    </tr>`;
  return `
    <p style="margin:0 0 4px;font-size:12px;font-weight:bold;letter-spacing:0.08em;text-transform:uppercase;color:#E8491E;">New website enquiry</p>
    <p style="margin:0 0 16px;font-size:17px;font-weight:bold;">${escapeHtml(firstName)} ${escapeHtml(lastName)} — ${escapeHtml(instrument)} at ${escapeHtml(studioName || 'studio not set')}</p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 16px;">
      ${row('Parent/guardian', parent)}
      ${row('Phone', phone)}
      ${row('Email', email)}
    </table>
    <p style="margin:0 0 6px;color:#666666;font-size:13px;">Message</p>
    <p style="margin:0 0 16px;white-space:pre-wrap;">${escapeHtml(notes || '(no message provided)')}</p>
    <p style="margin:0;"><a href="https://pathfindermusiclessons.com.au/portal/enquiries.html" style="color:#E8491E;text-decoration:none;">Open in the Portal →</a></p>
  `;
}

function brandedEmail(innerHtml, studioEmail, studioAddress) {
  return `<!DOCTYPE html>
<html><body style="margin:0;padding:0;background:#f5f5f7;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f7;padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:560px;background:#ffffff;border-radius:8px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;">
        <tr><td style="background:#1c1c1e;padding:18px 24px;border-bottom:3px solid #E8491E;">
          <div style="color:#E8491E;font-size:11px;letter-spacing:0.12em;text-transform:uppercase;font-weight:bold;">
            Pathfinder Music Lessons
          </div>
        </td></tr>
        <tr><td style="padding:24px;color:#1c1c1e;font-size:15px;line-height:1.65;">
          ${innerHtml}
        </td></tr>
        <tr><td style="padding:16px 24px;border-top:1px solid #eeeeee;color:#999999;font-size:12px;line-height:1.6;">
          Pathfinder Music Lessons · <a href="mailto:${escapeHtml(studioEmail)}" style="color:#E8491E;text-decoration:none;">${escapeHtml(studioEmail)}</a><br>
          ${studioAddress ? `${escapeHtml(studioAddress)}<br>` : ''}
          <a href="https://www.pathfindermusiclessons.com.au" style="color:#999999;">pathfindermusiclessons.com.au</a>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

function escapeHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function originFor(event) {
  const o = event.headers?.origin || '';
  return ALLOWED_ORIGINS.includes(o) ? o : ALLOWED_ORIGINS[0];
}

function clean(v, max) {
  return String(v ?? '').trim().slice(0, max);
}

function isValidEmail(s) {
  return /^[^@\s]+@[^@.\s]+(\.[^@.\s]+)+$/.test(s) && s.length <= 254;
}

function json(statusCode, payload, cors = {}) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json', ...cors },
    body: JSON.stringify(payload),
  };
}
