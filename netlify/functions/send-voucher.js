// ============================================================
// Netlify Function: send-voucher
//
// Emails an issued gift voucher (PDF attached) to its recipient, copying
// the purchaser and BCC'ing the issuing studio. send-email.js cannot do
// this: it uses Resend's batch endpoint, which does not support
// attachments. This sends through the single-message endpoint instead.
//
// The PDF is drawn in the admin's browser (js/voucher-pdf.js), so what
// they previewed is exactly what is attached. This function checks it is
// really a PDF of sensible size, and checks the CALLER is a signed-in
// admin — unlike the bulk sender, it verifies the Supabase session.
//
// Environment variables (same as send-email):
//   SUPABASE_URL, SUPABASE_SERVICE_KEY, RESEND_API_KEY
//
// POST { voucherId, pdfBase64, to?, ccPurchaser? }
//   Authorization: Bearer <the admin's Supabase access token>
//   to          optional override of the recipient address (a resend to a
//               corrected address); the stored address is updated to match
//   ccPurchaser default true; the purchaser is copied only if an address
//               was recorded for them
// ============================================================

const RESEND_ENDPOINT = 'https://api.resend.com/emails';
const MAX_PDF_BYTES   = 3 * 1024 * 1024;

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { error: 'Method not allowed' });

  let body;
  try { body = JSON.parse(event.body); }
  catch { return json(400, { error: 'Invalid request body' }); }

  const SUPABASE_URL         = process.env.SUPABASE_URL;
  const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
  const RESEND_API_KEY       = process.env.RESEND_API_KEY;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY || !RESEND_API_KEY) {
    return json(500, { error: 'Server misconfigured — Supabase or Resend environment variables missing.' });
  }

  const sb = {
    'Content-Type':  'application/json',
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
    'apikey':        SUPABASE_SERVICE_KEY,
  };
  const rest = (path) => `${SUPABASE_URL}/rest/v1/${path}`;
  const get = async (path) => {
    const r = await fetch(rest(path), { headers: sb });
    if (!r.ok) throw new Error(`DB error on ${path}: ${await r.text()}`);
    return r.json();
  };

  try {
    // ---- 1. who is calling? must be a signed-in admin ----
    const token = (event.headers?.authorization || event.headers?.Authorization || '').replace(/^Bearer\s+/i, '');
    if (!token) return json(401, { error: 'Not signed in.' });

    const ur = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${token}` },
    });
    if (!ur.ok) return json(401, { error: 'Your session has expired — please sign in again.' });
    const user = await ur.json();
    const prof = (await get(`profiles?id=eq.${encodeURIComponent(user.id)}&select=role,status`))[0];
    if (!prof || prof.status === 'inactive' || !['admin', 'superuser'].includes(prof.role)) {
      return json(403, { error: 'Only admins can send vouchers.' });
    }

    // ---- 2. the voucher ----
    const voucherId = String(body.voucherId ?? '');
    if (!/^[0-9a-f-]{36}$/i.test(voucherId)) return json(400, { error: 'voucherId is required.' });
    const v = (await get(`gift_vouchers?id=eq.${voucherId}&select=*`))[0];
    if (!v) return json(404, { error: 'Voucher not found.' });
    if (v.source === 'online') {
      // bought on the website: sent by the voucher-admin function from the website's
      // mailbox (the Vouchers page does this for you with “Email again”)
      return json(409, { error: 'This voucher was bought online — use “Email again” on the Vouchers page.', code: 'online' });
    }
    if (v.status !== 'issued') {
      return json(409, { error: `This voucher is ${v.status} — it can't be emailed.`, code: 'not_issued' });
    }
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Australia/Melbourne' });
    if (v.expires_on < today) {
      return json(409, { error: `This voucher expired on ${formatDateLong(v.expires_on)}.`, code: 'expired' });
    }

    // ---- 3. the PDF ----
    const b64 = String(body.pdfBase64 ?? '').replace(/^data:application\/pdf;base64,/, '');
    const pdf = Buffer.from(b64, 'base64');
    if (pdf.length < 1000 || pdf.length > MAX_PDF_BYTES || pdf.subarray(0, 5).toString('latin1') !== '%PDF-') {
      return json(400, { error: 'The voucher PDF is missing or invalid.' });
    }

    // ---- 4. addresses ----
    const studio = v.studio_id
      ? (await get(`studios?id=eq.${v.studio_id}&select=name,email,address`))[0]
      : null;
    const fromEmail = studio?.email;
    if (!isValidEmail(fromEmail)) {
      return json(400, { error: 'The issuing studio has no email address on file (Studios page).', code: 'no-studio-email' });
    }
    const to = String(body.to ?? v.recipient_email ?? '').trim();
    if (!isValidEmail(to)) return json(400, { error: 'The recipient email address is not valid.' });
    const cc = [];
    if (body.ccPurchaser !== false && isValidEmail(v.purchaser_email) &&
        v.purchaser_email.toLowerCase() !== to.toLowerCase()) {
      cc.push(v.purchaser_email);
    }
    const bcc = [fromEmail];

    // ---- 5. the email ----
    const subject = `Your Voucher for ${v.subject}`;
    const first   = String(v.recipient_name).trim().split(/\s+/)[0] || 'there';
    const text    = bodyText({ first, v, studioEmail: fromEmail });
    const html    = emailTemplate(text, fromEmail, studio?.address);

    const payload = {
      from:     `Pathfinder Music Lessons <${fromEmail}>`,
      to:       [to],
      reply_to: fromEmail,
      subject,
      html,
      text:     plain(text),
      attachments: [{ filename: `Pathfinder-Voucher-${v.voucher_no}.pdf`, content: pdf.toString('base64') }],
    };
    if (cc.length)  payload.cc  = cc;
    if (bcc.length) payload.bcc = bcc;

    const r = await fetch(RESEND_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        // a double-click or a retried request must never mail the voucher twice
        'Idempotency-Key': idempotencyKey(v, to, cc, pdf),
      },
      body: JSON.stringify(payload),
    });
    const rj = await r.json().catch(() => ({}));

    if (!r.ok) {
      const msg = rj?.message || rj?.error || `Resend returned ${r.status}`;
      await patchVoucher(rest, sb, v.id, { email_error: String(msg).slice(0, 500) });
      await logSend(rest, sb, { user, subject, text, to, cc, bcc, status: 'failed', error: msg });
      return json(502, { error: 'The email service rejected the send: ' + String(msg).slice(0, 300) });
    }

    // ---- 6. record it ----
    await patchVoucher(rest, sb, v.id, {
      emailed_at: new Date().toISOString(),
      emailed_to: to,
      email_error: null,
      send_count: (v.send_count ?? 0) + 1,
      recipient_email: to,
    });
    await logSend(rest, sb, { user, subject, text, to, cc, bcc, status: 'sent', resendId: rj?.id });

    return json(200, { sent: true, to, cc, bcc, resendId: rj?.id ?? null });
  } catch (err) {
    return json(500, { error: err.message });
  }
};

// ============================================================
// Email copy — short and upbeat. Same plain-text → branded HTML
// conventions as every other Portal email (**block** = callout).
// ============================================================
function bodyText({ first, v, studioEmail }) {   // (reassigned below)
  // admin-typed text goes through the markdown-ish email template, so
  // neutralise its two special characters (** and [ ])
  const safe = (t) => String(t).replace(/\*+/g, '').replace(/\[/g, '(').replace(/\]/g, ')');
  v = { ...v, subject: safe(v.subject), purchaser_name: safe(v.purchaser_name) };
  first = safe(first);
  const lines = [];
  lines.push(`Hi ${first},`);
  lines.push('');
  lines.push(`Great news — ${v.purchaser_name} has given you a gift: ${v.subject}!`);
  lines.push('');
  lines.push(`Your voucher is attached to this email as a PDF${v.message ? `, with a personal message from ${v.purchaser_name} on it` : ''}. Print it out, wrap it up, or just keep it handy on your phone.`);
  lines.push('');
  lines.push(`**Voucher: ${v.subject}\nVoucher number: ${v.voucher_no}\nValid until: ${formatDateLong(v.expires_on)}**`);
  lines.push('');
  lines.push(`Ready to get started? Just reply to this email or write to ${studioEmail}, quote your voucher number, and we'll find the perfect lesson time for you.`);
  lines.push('');
  lines.push(`We can't wait to make some music with you!`);
  lines.push('');
  lines.push('The team at Pathfinder Music Lessons');
  return lines.join('\n');
}

function idempotencyKey(v, to, cc, pdf) {
  const h = require('crypto').createHash('sha1')
    .update([to, cc.join(','), pdf.length].join('|')).digest('hex').slice(0, 12);
  return `voucher-${v.id}-${(v.send_count ?? 0) + 1}-${h}`;
}

function plain(text) {
  return text.replace(/\*\*/g, '');
}

async function patchVoucher(rest, sb, id, fields) {
  try {
    await fetch(rest(`gift_vouchers?id=eq.${id}`), {
      method: 'PATCH', headers: { ...sb, Prefer: 'return=minimal' }, body: JSON.stringify(fields),
    });
  } catch (_) { /* tracking must never break the send */ }
}

async function logSend(rest, sb, { user, subject, text, to, cc, bcc, status, error, resendId }) {
  try {
    await fetch(rest('email_log'), {
      method: 'POST',
      headers: { ...sb, Prefer: 'return=minimal' },
      body: JSON.stringify({
        sent_by: user?.id ?? null,
        subject,
        body: plain(text),
        recipient_mode: 'voucher',
        recipient_count: status === 'sent' ? 1 : 0,
        recipients: [{ name: to, addresses: [to, ...cc], resend_id: resendId ?? null }],
        bcc: bcc.join(', '),
        status,
        error: error ? String(error).slice(0, 2000) : null,
      }),
    });
  } catch (_) { /* logging must never break the send */ }
}

// ============================================================
// HELPERS (the email shell is copied verbatim from send-email.js so a
// voucher email looks exactly like every other Pathfinder email)
// ============================================================
function json(statusCode, obj) {
  return { statusCode, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(obj) };
}

function formatDateLong(dateStr) {
  if (!dateStr) return '';
  const [y, m, d] = dateStr.slice(0, 10).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-AU', {
    day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC',
  });
}

// Conservative check — catches malformed addresses before Resend rejects them.
function isValidEmail(addr) {
  const s = String(addr ?? '').trim();
  if (!s || s.length > 254 || /\s/.test(s)) return false;
  return /^[^@]+@[^@.]+(\.[^@.]+)+$/.test(s);
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// Plain text → branded HTML email.
// A paragraph wrapped entirely in **double asterisks** becomes a
// highlighted callout block; **bold** works inline elsewhere; a
// [label](url) works inline anywhere, same syntax as markdown links; a
// paragraph where every line starts with "- " becomes a real bullet list
// (each line may itself contain a [label](url)).
//
// `studioAddress` is the sending studio's own postal address, resolved
// by the caller from the `studios` table — the same field admins edit on
// the Studios page. It used to be a hardcoded line naming both studios'
// addresses regardless of which one actually sent the email. When no
// address is on file for this studio, the line is left out rather than
// printed blank.
function emailTemplate(bodyText, studioEmail, studioAddress) {
  const inlineBold = (s) => s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  const inlineLink = (s) => s.replace(/\[([^\]]+)\]\(([^)]+)\)/g,
    '<a href="$2" style="color:#E8491E;text-decoration:none;">$1</a>');
  const formatInline = (s) => inlineBold(inlineLink(s));

  const isBulletBlock = (t) => {
    const lines = t.split('\n').map(l => l.trim()).filter(Boolean);
    return lines.length > 0 && lines.every(l => l.startsWith('- '));
  };

  const para = (p) => {
    const t = p.trim();
    // A paragraph of only dashes is a section break
    if (/^-{3,}$/.test(t)) {
      return '<div style="border-top:1px solid #e5e5e5;margin:22px 0 18px;"></div>';
    }
    // A paragraph where every line is "- something" is a bullet list
    if (isBulletBlock(t)) {
      const items = t.split('\n').map(l => l.trim()).filter(Boolean);
      return `<ul style="margin:0 0 14px;padding-left:20px;">` +
        items.map(l => `<li style="margin:0 0 6px;line-height:1.5;">${formatInline(l.slice(2))}</li>`).join('') +
        `</ul>`;
    }
    // A short ALL-CAPS line is a heading
    if (/^[A-Z][A-Z0-9 &'’,.\-\/]{2,40}$/.test(t) && !t.includes('\n')) {
      return `<p style="margin:0 0 10px;font-size:12px;font-weight:bold;letter-spacing:0.08em;
              text-transform:uppercase;color:#E8491E;">${t}</p>`;
    }
    return `<p style="margin:0 0 14px;">${formatInline(t.replace(/\n/g, '<br>'))}</p>`;
  };

  const callout = (inner) =>
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 16px;">
      <tr>
        <td style="width:4px;background:#E8491E;border-radius:2px 0 0 2px;">&nbsp;</td>
        <td style="background:#f5f5f7;padding:14px 16px;border-radius:0 2px 2px 0;font-size:15px;line-height:1.6;color:#1c1c1e;">
          ${inner.split(/\n\s*\n/).map(b =>
            `<div style="margin:0 0 10px;">${formatInline(b.trim().replace(/\n/g, '<br>'))}</div>`
          ).join('')}
        </td>
      </tr>
    </table>`;

  // A callout may span blank lines, so it is extracted from the whole
  // body before paragraphs are split. Matching per paragraph meant a
  // multi-paragraph block never matched and its asterisks showed
  // through literally.
  const src = escapeHtml(bodyText);
  let html = '';
  let last = 0;
  const re = /\*\*([\s\S]+?)\*\*(?=\s*(?:\n\s*\n|$))/g;
  let m;

  while ((m = re.exec(src)) !== null) {
    // Only treat it as a block when it starts its own paragraph —
    // otherwise **bold** mid-sentence would be swallowed.
    const before = src.slice(last, m.index);
    const startsBlock = /(^|\n\s*\n)\s*$/.test(before);
    if (!startsBlock) continue;

    before.split(/\n\s*\n/).filter(p => p.trim()).forEach(p => { html += para(p); });
    html += callout(m[1]);
    last = m.index + m[0].length;
  }

  src.slice(last).split(/\n\s*\n/).filter(p => p.trim()).forEach(p => { html += para(p); });

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
          ${html}
        </td></tr>
        <tr><td style="padding:16px 24px;border-top:1px solid #eeeeee;color:#999999;font-size:12px;line-height:1.6;">
          Pathfinder Music Lessons · <a href="mailto:${studioEmail}" style="color:#E8491E;text-decoration:none;">${studioEmail}</a><br>
          ${studioAddress ? `${escapeHtml(studioAddress)}<br>` : ''}
          <a href="https://www.pathfindermusiclessons.com.au" style="color:#999999;">pathfindermusiclessons.com.au</a>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

