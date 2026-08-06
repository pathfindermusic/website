// ============================================================
// Netlify Function: send-email
// Resolves recipients server-side (student emails live in
// auth.users, not profiles) and sends via Resend.
//
// Environment variables required in Netlify:
//   SUPABASE_URL          — project URL
//   SUPABASE_SERVICE_KEY  — legacy service_role key (eyJ...)
//   RESEND_API_KEY        — Resend API key (secret)
//
// Actions:
//   preview  → resolve recipients, return count + names (no send)
//   send     → resolve recipients and send
//
// Recipient modes:
//   studios       { studioIds: [] }
//   teacher       { teacherId }
//   day           { dayOfWeek, studioIds? }
//   teacher_date  { teacherId, date }
//   students      { studentIds: [] }
//   occurrence    { occurrenceId }   (used by automatic emails)
// ============================================================

const RESEND_ENDPOINT = 'https://api.resend.com/emails/batch';

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  let body;
  try { body = JSON.parse(event.body); }
  catch { return json(400, { error: 'Invalid request body' }); }

  const SUPABASE_URL         = process.env.SUPABASE_URL;
  const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
  const RESEND_API_KEY       = process.env.RESEND_API_KEY;

  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    return json(500, { error: 'Server misconfigured — Supabase env vars missing.' });
  }

  const action = body.action ?? 'preview';
  if (action === 'send' && !RESEND_API_KEY) {
    return json(500, { error: 'Server misconfigured — RESEND_API_KEY missing.' });
  }

  const sb = {
    'Content-Type':  'application/json',
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
    'apikey':        SUPABASE_SERVICE_KEY,
  };

  const rest = (path) => `${SUPABASE_URL}/rest/v1/${path}`;
  const get  = async (path) => {
    const r = await fetch(rest(path), { headers: sb });
    if (!r.ok) throw new Error(`DB error on ${path}: ${await r.text()}`);
    return r.json();
  };

  try {
    // ============================================================
    // 1. Resolve which student IDs should receive the email
    // ============================================================
    const mode = body.mode;
    let studentIds = [];
    let lessonContext = null; // for occurrence-driven emails

    if (mode === 'students') {
      studentIds = body.studentIds ?? [];

    } else if (mode === 'studios') {
      const ids = body.studioIds ?? [];
      if (ids.length === 0) return json(400, { error: 'No studios selected.' });
      const list = ids.map(i => `"${i}"`).join(',');
      const rows = await get(
        `students?studio_id=in.(${list})&status=in.(active,trial)&select=id`);
      studentIds = rows.map(r => r.id);

    } else if (mode === 'teacher') {
      if (!body.teacherId) return json(400, { error: 'No teacher selected.' });
      const lessons = await get(
        `lessons?teacher_id=eq.${body.teacherId}&status=eq.active&select=id`
      );
      studentIds = await studentsForLessons(lessons.map(l => l.id));

    } else if (mode === 'day') {
      if (body.dayOfWeek === undefined || body.dayOfWeek === null) {
        return json(400, { error: 'No day selected.' });
      }
      let q = `lessons?day_of_week=eq.${body.dayOfWeek}&status=eq.active&select=id`;
      if (body.studioIds?.length) {
        q += `&studio_id=in.(${body.studioIds.map(i => `"${i}"`).join(',')})`;
      }
      const lessons = await get(q);
      studentIds = await studentsForLessons(lessons.map(l => l.id));

    } else if (mode === 'teacher_date') {
      if (!body.teacherId || !body.date) {
        return json(400, { error: 'Teacher and date are both required.' });
      }
      const lessons = await get(
        `lessons?teacher_id=eq.${body.teacherId}&status=eq.active&select=id`
      );
      const lIds = lessons.map(l => l.id);
      if (lIds.length === 0) { studentIds = []; }
      else {
        const occs = await get(
          `lesson_occurrences?date=eq.${body.date}&status=eq.scheduled` +
          `&lesson_id=in.(${lIds.map(i => `"${i}"`).join(',')})&select=lesson_id`
        );
        studentIds = await studentsForLessons([...new Set(occs.map(o => o.lesson_id))]);
      }

    } else if (mode === 'occurrence') {
      if (!body.occurrenceId) return json(400, { error: 'occurrenceId is required.' });
      const occs = await get(
        `lesson_occurrences?id=eq.${body.occurrenceId}` +
        `&select=id,date,lesson_id,lessons(id,instrument,start_time,day_of_week,teacher_id,studio_id)`
      );
      const occ = occs?.[0];
      if (!occ) return json(404, { error: 'Lesson occurrence not found.' });
      studentIds = await studentsForLessons([occ.lesson_id]);

      // Build context for template placeholders
      const l = occ.lessons ?? {};
      const [tRows, sRows] = await Promise.all([
        l.teacher_id ? get(`teachers?id=eq.${l.teacher_id}&select=user_id`) : [],
        l.studio_id  ? get(`studios?id=eq.${l.studio_id}&select=name,email`) : [],
      ]);
      let teacherName = '';
      if (tRows?.[0]?.user_id) {
        const p = await get(`profiles?id=eq.${tRows[0].user_id}&select=first_name,last_name`);
        teacherName = `${p?.[0]?.first_name ?? ''} ${p?.[0]?.last_name ?? ''}`.trim();
      }
      lessonContext = {
        instrument:   l.instrument ?? '',
        lesson_time:  formatTime(l.start_time),
        lesson_day:   formatDateLong(occ.date),
        lesson_weekday: formatWeekday(occ.date),
        teacher_name: teacherName,
        studio:      sRows?.[0]?.name ?? '',
        studioEmail: sRows?.[0]?.email ?? null,
      };

    } else {
      return json(400, { error: `Unknown recipient mode: ${mode}` });
    }

    studentIds = [...new Set(studentIds.filter(Boolean))];
    if (studentIds.length === 0) {
      return json(200, { count: 0, recipients: [], message: 'No matching students found.' });
    }

    // ============================================================
    // 2. Resolve student names, user_ids and parent emails
    // ============================================================
    const idList = studentIds.map(i => `"${i}"`).join(',');
    // Audience modes exclude prospects — a studio-wide announcement
    // should never reach someone who has only enquired. But when the
    // caller names specific students, or a specific lesson, they have
    // chosen the recipient and the filter would wrongly block it: the
    // enquiry acknowledgement goes to exactly one prospect.
    const explicitRecipients = (mode === 'students' || mode === 'occurrence');
    const statusFilter = explicitRecipients
      ? '&status=in.(active,trial,prospective)'
      : '&status=in.(active,trial)';

    const students = await get(
      `students?id=in.(${idList})${statusFilter}` +
      `&select=id,user_id,email,parent_name,parent_email`
    );

    const userIds = students.map(s => s.user_id).filter(Boolean);
    const profiles = userIds.length
      ? await get(`profiles?id=in.(${userIds.map(i => `"${i}"`).join(',')})&select=id,first_name,last_name`)
      : [];
    const profileMap = {};
    profiles.forEach(p => { profileMap[p.id] = p; });

    // Student login emails live in auth.users — fetch via Admin API
    const authRes = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users?page=1&per_page=1000`,
      { headers: sb }
    );
    const authData  = await authRes.json();
    const emailById = {};
    (authData?.users ?? []).forEach(u => { if (u.id) emailById[u.id] = u.email; });

    // Build recipient list — student email plus parent email where present
    const recipients = [];
    const unreachable = [];
    const invalidAddresses = [];
    students.forEach(s => {
      const p         = profileMap[s.user_id] ?? {};
      const firstName = p.first_name ?? '';
      const fullName  = `${firstName} ${p.last_name ?? ''}`.trim();
      const addresses = [];
      const seen      = new Set();
      const push = (addr) => {
        if (!addr) return;
        const key = String(addr).trim().toLowerCase();
        if (!key || seen.has(key)) return;
        seen.add(key);
        addresses.push(String(addr).trim());
      };

      // Login address first, then the contact email held on the student
      // record (bulk-imported students have no auth account), then the parent.
      push(emailById[s.user_id]);
      push(s.email);
      push(s.parent_email);

      const valid = addresses.filter(isValidEmail);
      const bad   = addresses.filter(a => !isValidEmail(a));
      const label = `${firstName} ${p.last_name ?? ''}`.trim() || '(unnamed)';

      if (bad.length) invalidAddresses.push(`${label} (${bad.join(', ')})`);
      if (valid.length === 0) { unreachable.push(label); return; }
      addresses.length = 0;
      valid.forEach(a => addresses.push(a));
      recipients.push({
        studentId: s.id,
        name:      fullName || '(unnamed)',
        firstName: firstName || fullName,
        addresses,
      });
    });

    // ============================================================
    // 3. Resolve the BCC address
    // ============================================================
    let bcc = body.bcc ?? null;
    if (!bcc && lessonContext?.studioEmail) bcc = lessonContext.studioEmail;
    if (!bcc && body.bccStudioId) {
      const st = await get(`studios?id=eq.${body.bccStudioId}&select=email`);
      bcc = st?.[0]?.email ?? null;
    }

    // ============================================================
    // 4. Preview stops here
    // ============================================================
    if (action === 'preview') {
      const SAMPLE = 8;
      return json(200, {
        count:       recipients.length,
        recipients:  recipients.slice(0, SAMPLE)
                               .map(r => ({ name: r.name, addresses: r.addresses })),
        truncated:   Math.max(0, recipients.length - SAMPLE),
        unreachable: unreachable.length,
        unreachableNames: unreachable.slice(0, SAMPLE),
        invalid: invalidAddresses.length,
        invalidNames: invalidAddresses.slice(0, SAMPLE),
        bcc,
      });
    }

    // ============================================================
    // 5. Send via Resend (batch endpoint, chunks of 100)
    // ============================================================
    const fromEmail = body.from;
    const fromName  = body.fromName ?? 'Pathfinder Music Lessons';
    const subject   = body.subject;
    const bodyText  = body.bodyText;

    if (!fromEmail) return json(400, { error: 'Sender studio email is required.' });
    if (!subject || !bodyText) return json(400, { error: 'Subject and message are both required.' });

    const messages = recipients.map(r => {
      const vars = {
        student_name: r.name,
        first_name:   r.firstName,
        instrument:   lessonContext?.instrument   ?? '',
        teacher_name: lessonContext?.teacher_name ?? '',
        lesson_time:  lessonContext?.lesson_time  ?? '',
        lesson_day:     lessonContext?.lesson_day     ?? '',
        lesson_weekday: lessonContext?.lesson_weekday ?? '',
        studio:       lessonContext?.studio       ?? '',
      };
      const filledSubject = fill(subject,  vars);
      const filledBody    = fill(bodyText, vars);
      const msg = {
        from:     `${fromName} <${fromEmail}>`,
        to:       r.addresses,
        reply_to: fromEmail,
        subject:  filledSubject,
        html:     emailTemplate(filledBody, fromEmail),
      };
      // BCC the studio only on single-recipient sends. For bulk sends
      // one summary email is sent instead — 500 BCC copies would bury
      // the studio inbox and nobody would read them.
      if (bcc && recipients.length === 1) msg.bcc = [bcc];
      return msg;
    });

    let sent = 0;
    const failures = [];
    for (let i = 0; i < messages.length; i += 100) {
      const chunk = messages.slice(i, i + 100);
      const r = await fetch(RESEND_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${RESEND_API_KEY}`,
        },
        body: JSON.stringify(chunk),
      });
      if (r.ok) {
        sent += chunk.length;
        try {
          const okBody = await r.json();
          (okBody?.data ?? []).forEach((item, idx) => {
            const rec = recipients[i + idx];
            if (rec && item?.id) rec.resendId = item.id;
          });
        } catch (_) { /* IDs are a nice-to-have, never fail the send */ }
      } else {
        const body = await r.text();
        console.error('[send-email] Resend rejected a batch:', r.status, body);
        failures.push(`${r.status}: ${body}`);
      }
    }

    // ============================================================
    // 5b. Bulk send: one summary to the studio instead of N BCCs
    // ============================================================
    let summarySent = false;
    if (bcc && recipients.length > 1 && sent > 0) {
      try {
        const sr = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Content-Type':  'application/json',
            'Authorization': `Bearer ${RESEND_API_KEY}`,
          },
          body: JSON.stringify({
            from:     `${fromName} <${fromEmail}>`,
            to:       [bcc],
            reply_to: fromEmail,
            subject:  `Sent to ${sent} student${sent !== 1 ? 's' : ''}: ${subject}`,
            html:     summaryTemplate({
              subject, bodyText, fromEmail,
              recipients, sent,
              unreachable, invalidAddresses,
              mode, spec: body,
            }),
          }),
        });
        summarySent = sr.ok;
        if (!sr.ok) {
          console.error('[send-email] Summary email failed:', sr.status, await sr.text());
        }
      } catch (err) {
        console.error('[send-email] Summary email error:', err.message);
      }
    }

    // ============================================================
    // 6. Log the send (best effort — never blocks the response)
    // ============================================================
    try {
      await fetch(rest('email_log'), {
        method: 'POST',
        headers: { ...sb, Prefer: 'return=minimal' },
        body: JSON.stringify({
          sent_by:         body.sentBy ?? null,
          subject,
          body:            bodyText,
          recipient_mode:  mode,
          recipient_count: sent,
          recipients:      recipients.map(r => ({
                             name:      r.name,
                             addresses: r.addresses,
                             resend_id: r.resendId ?? null,
                           })),
          bcc,
          status:          failures.length ? 'partial' : 'sent',
          error:           failures.length ? failures.join(' | ').slice(0, 2000) : null,
        }),
      });
    } catch (_) { /* logging must never break the send */ }

    if (failures.length && sent === 0) {
      return json(502, {
        error: 'Resend rejected the send: ' + String(failures[0]).slice(0, 300),
        detail: failures[0],
      });
    }

    return json(200, {
      sent,
      total:       recipients.length,
      unreachable: unreachable.length,
      summarySent,
      bcc,
      partial:     failures.length > 0,
      detail:      failures.length ? failures[0] : undefined,
    });

    // ---- helpers that need `get` in scope ----
    async function studentsForLessons(lessonIds) {
      if (!lessonIds || lessonIds.length === 0) return [];
      const list = lessonIds.map(i => `"${i}"`).join(',');
      const rows = await get(`lesson_students?lesson_id=in.(${list})&select=student_id`);
      return rows.map(r => r.student_id);
    }

  } catch (err) {
    return json(500, { error: err.message });
  }
};

// ============================================================
// HELPERS
// ============================================================
function json(statusCode, obj) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(obj),
  };
}

// Replace {{placeholder}} tokens
function fill(text, vars) {
  return String(text).replace(/\{\{\s*(\w+)\s*\}\}/g, (m, key) =>
    vars[key] !== undefined && vars[key] !== '' ? vars[key] : m
  );
}

// Conservative check — enough to catch the malformed addresses that
// would cause Resend to reject an entire batch.
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
// highlighted callout block; **bold** works inline elsewhere.
function emailTemplate(bodyText, studioEmail) {
  const inlineBold = (s) => s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

  const para = (p) => {
    const t = p.trim();
    // A paragraph of only dashes is a section break
    if (/^-{3,}$/.test(t)) {
      return '<div style="border-top:1px solid #e5e5e5;margin:22px 0 18px;"></div>';
    }
    // A short ALL-CAPS line is a heading
    if (/^[A-Z][A-Z0-9 &'’,.\-]{2,40}$/.test(t) && !t.includes('\n')) {
      return `<p style="margin:0 0 10px;font-size:12px;font-weight:bold;letter-spacing:0.08em;
              text-transform:uppercase;color:#E8491E;">${t}</p>`;
    }
    return `<p style="margin:0 0 14px;">${inlineBold(t.replace(/\n/g, '<br>'))}</p>`;
  };

  const callout = (inner) =>
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 16px;">
      <tr>
        <td style="width:4px;background:#E8491E;border-radius:2px 0 0 2px;">&nbsp;</td>
        <td style="background:#f5f5f7;padding:14px 16px;border-radius:0 2px 2px 0;font-size:15px;line-height:1.6;color:#1c1c1e;">
          ${inner.split(/\n\s*\n/).map(b =>
            `<div style="margin:0 0 10px;">${inlineBold(b.trim().replace(/\n/g, '<br>'))}</div>`
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
          20 Collins Place, Kilsyth VIC 3137 &nbsp;·&nbsp; G3 / 93a Heatherdale Rd, Ringwood VIC 3134<br>
          <a href="https://www.pathfindermusiclessons.com.au" style="color:#999999;">pathfindermusiclessons.com.au</a>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

function formatTime(timeStr) {
  if (!timeStr) return '';
  const [h, m] = timeStr.split(':').map(Number);
  const ampm = h >= 12 ? 'PM' : 'AM';
  return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${ampm}`;
}

// Weekday name only, e.g. "Thursday" — used for recurring wording
function formatWeekday(dateStr) {
  if (!dateStr) return '';
  const [y, m, d] = dateStr.slice(0, 10).split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-AU', { weekday: 'long' });
}

function formatDateLong(dateStr) {
  if (!dateStr) return '';
  const [y, m, d] = dateStr.slice(0, 10).split('-').map(Number);
  const dt = new Date(y, m - 1, d);
  return dt.toLocaleDateString('en-AU', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
  });
}
