// ============================================================
// PATHFINDER PORTAL — weekly attendance marking report
//
// Sunday evening: each teacher with unmarked lessons gets a list,
// and the studios get a summary of everyone.
//
// Nothing is sent to a teacher who is up to date. An email in the
// inbox therefore always means something needs doing, which is
// what stops it becoming wallpaper.
//
// "Unmarked" means a lesson that has ENDED without every student
// marked — the same test the Unmarked count on their dashboard
// uses, so the two always agree.
//
// Scheduled from netlify.toml at 07:00 UTC on Sundays, which is
// 5 PM Melbourne in winter and 6 PM through daylight saving.
// ============================================================

const SUPABASE_URL         = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const RESEND_API_KEY       = process.env.RESEND_API_KEY;
const SITE                 = 'https://www.pathfindermusiclessons.com.au';

// Anything older than this is a backlog worth naming separately
const STALE_DAYS = 14;

exports.handler = async () => {
  const now = new Date();
  const today = fmtISO(now);

  const headers = {
    'Content-Type':  'application/json',
    'apikey':        SUPABASE_SERVICE_KEY,
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
  };
  const get = async (path) => {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers });
    if (!r.ok) throw new Error(`${path}: ${await r.text()}`);
    return r.json();
  };

  try {
    // Everything not fully marked, up to and including today. The date
    // filter is deliberately loose — whether a lesson has ENDED depends
    // on its start time and duration, which is worked out below.
    const rows = await get(
      `schedule_view?date=lte.${today}` +
      `&occurrence_status=neq.cancelled` +
      `&fully_marked=is.false` +
      `&select=occurrence_id,date,start_time,duration_mins,instrument,` +
      `teacher_id,teacher_name,studio_id,studio_name,studio_email,` +
      `student_name,student_count,attendance_marked_count,lesson_type` +
      `&order=date.asc`);

    const nowHM = melbourneHM(now);
    const outstanding = rows.filter(r => hasEnded(r, todayInMelbourne(now), nowHM));

    if (!outstanding.length) {
      console.log('[marking-report] everything is marked');
      return ok({ teachers: 0, sent: 0 });
    }

    // Group by whoever is actually teaching — schedule_view already
    // resolves a substitute, so cover lands with the person who took it.
    const byTeacher = {};
    outstanding.forEach(r => {
      if (!r.teacher_id) return;
      (byTeacher[r.teacher_id] ??= { name: r.teacher_name, rows: [] }).rows.push(r);
    });

    const teacherIds = Object.keys(byTeacher);
    const teachers = await get(
      `teachers?id=in.(${teacherIds.join(',')})&select=id,user_id`);

    const authList = await get('../auth/v1/admin/users?page=1&per_page=1000')
      .catch(() => ({ users: [] }));
    const emailById = {};
    (authList?.users ?? []).forEach(u => { emailById[u.id] = u.email; });

    const studios = await get('studios?select=id,name,email&status=eq.active');
    const studioEmail = {};
    studios.forEach(s => { if (s.email) studioEmail[s.id] = s.email; });
    const fromAddress = studios.find(s => s.email)?.email
      ?? 'info@pathfindermusiclessons.com.au';

    let sent = 0, skipped = 0;

    for (const t of teachers) {
      const entry = byTeacher[t.id];
      const to = emailById[t.user_id];
      if (!to) { skipped++; continue; }

      const html = teacherReport(entry.name, entry.rows, today);

      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${RESEND_API_KEY}`,
        },
        body: JSON.stringify({
          from:     `Pathfinder Music Lessons <${fromAddress}>`,
          to:       [to],
          reply_to: fromAddress,
          subject:  `${entry.rows.length} lesson${entry.rows.length !== 1 ? 's' : ''} still to mark`,
          html,
        }),
      });

      if (res.ok) sent++;
      else console.error('[marking-report]', await res.text());
    }

    // One summary per studio, so the front desk can chase without
    // opening the portal.
    const byStudio = {};
    outstanding.forEach(r => {
      if (!r.studio_id) return;
      (byStudio[r.studio_id] ??= { name: r.studio_name, rows: [] }).rows.push(r);
    });

    let summaries = 0;
    for (const [sid, s] of Object.entries(byStudio)) {
      const to = studioEmail[sid];
      if (!to) continue;

      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${RESEND_API_KEY}`,
        },
        body: JSON.stringify({
          from:     `Pathfinder Music Lessons <${fromAddress}>`,
          to:       [to],
          reply_to: fromAddress,
          subject:  `Attendance still to mark — ${s.name}`,
          html:     studioReport(s.name, s.rows, today),
        }),
      });
      if (res.ok) summaries++;
    }

    console.log(`[marking-report] ${sent} teachers, ${summaries} studios, ${skipped} skipped`);
    return ok({ teachers: teacherIds.length, sent, summaries, skipped });

  } catch (err) {
    console.error('[marking-report] run failed:', err.message);
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};

// ---------- helpers ----------

function ok(payload) { return { statusCode: 200, body: JSON.stringify(payload) }; }

function fmtISO(d) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Australia/Melbourne', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d);
}
const todayInMelbourne = fmtISO;

function melbourneHM(d) {
  const p = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Australia/Melbourne', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(d);
  return `${p}:00`;
}

// A lesson needs marking once it has ENDED — one still running is not
// yet late.
function hasEnded(row, todayStr, nowHM) {
  const d = row.date?.slice(0, 10);
  if (!d) return false;
  if (d < todayStr) return true;
  if (d > todayStr) return false;
  const [sh, sm] = (row.start_time ?? '00:00:00').split(':').map(Number);
  const end = sh * 60 + sm + (row.duration_mins ?? 0);
  const [nh, nm] = nowHM.split(':').map(Number);
  return end <= (nh * 60 + nm);
}

function daysAgo(dateStr, todayStr) {
  const a = new Date(`${dateStr}T12:00:00`);
  const b = new Date(`${todayStr}T12:00:00`);
  return Math.round((b - a) / 86400000);
}

function fmtDate(iso) {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  return new Date(y, m - 1, d, 12)
    .toLocaleDateString('en-AU', { weekday: 'short', day: 'numeric', month: 'short' });
}

function fmtTime(t) {
  if (!t) return '';
  const [h, m] = t.split(':').map(Number);
  return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${h >= 12 ? 'PM' : 'AM'}`;
}

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function who(r) {
  return r.lesson_type === 'group'
    ? `${r.attendance_marked_count ?? 0} of ${r.student_count} marked`
    : esc(r.student_name ?? '—');
}

function shell(inner) {
  return `<!DOCTYPE html>
<html><body style="margin:0;padding:0;background:#f5f5f7;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f7;padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:600px;background:#ffffff;border-radius:8px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;">
        <tr><td style="background:#1c1c1e;padding:18px 24px;border-bottom:3px solid #E8491E;">
          <div style="color:#E8491E;font-size:11px;letter-spacing:0.12em;text-transform:uppercase;font-weight:bold;">
            Pathfinder Music Lessons
          </div>
        </td></tr>
        ${inner}
        <tr><td style="padding:16px 24px;border-top:1px solid #eeeeee;color:#999999;font-size:12px;line-height:1.6;">
          <a href="${SITE}/portal/login.html" style="color:#E8491E;">Open the portal</a>
          &nbsp;·&nbsp; sent each Sunday while anything is outstanding
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

function rowsTable(rows, todayStr, showTeacher) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                 style="border-collapse:collapse;font-size:13px;">
    ${rows.map(r => {
      const age  = daysAgo(r.date, todayStr);
      const late = age >= STALE_DAYS;
      return `<tr>
        <td style="padding:6px 10px 6px 0;border-bottom:1px solid #eeeeee;white-space:nowrap;
                   ${late ? 'color:#dc2626;font-weight:bold;' : 'color:#1c1c1e;'}">
          ${fmtDate(r.date)}
        </td>
        <td style="padding:6px 10px 6px 0;border-bottom:1px solid #eeeeee;white-space:nowrap;color:#666666;">
          ${fmtTime(r.start_time)}
        </td>
        ${showTeacher ? `<td style="padding:6px 10px 6px 0;border-bottom:1px solid #eeeeee;color:#1c1c1e;">
          ${esc(r.teacher_name ?? '—')}</td>` : ''}
        <td style="padding:6px 10px 6px 0;border-bottom:1px solid #eeeeee;color:#1c1c1e;">
          ${who(r)}
        </td>
        <td style="padding:6px 0;border-bottom:1px solid #eeeeee;color:#666666;">
          ${esc(r.instrument ?? '')}
        </td>
      </tr>`;
    }).join('')}
  </table>`;
}

function teacherReport(name, rows, todayStr) {
  const first  = String(name ?? '').split(' ')[0] || 'there';
  const oldest = daysAgo(rows[0].date, todayStr);
  const stale  = rows.filter(r => daysAgo(r.date, todayStr) >= STALE_DAYS).length;

  return shell(`
    <tr><td style="padding:24px;color:#1c1c1e;font-size:15px;line-height:1.65;">
      <p style="margin:0 0 14px;">Hi ${esc(first)},</p>
      <p style="margin:0 0 18px;">
        ${rows.length === 1
          ? 'One lesson is still waiting to be marked.'
          : `${rows.length} lessons are still waiting to be marked.`}
        ${stale
          ? `<span style="color:#dc2626;font-weight:bold;">${stale} of them ${stale === 1 ? 'is' : 'are'} over a fortnight old.</span>`
          : ''}
      </p>

      ${rowsTable(rows, todayStr, false)}

      <p style="margin:18px 0 0;font-size:14px;color:#4a4a4a;line-height:1.6;">
        Marking takes a moment on My Schedule in the portal. It matters more than
        it looks: an unmarked lesson counts against the student's attendance rate,
        so a student who came every week can appear not to have.
      </p>
      ${oldest >= STALE_DAYS ? `
      <p style="margin:14px 0 0;font-size:14px;color:#4a4a4a;">
        If you cannot remember a lesson that far back, mark what you are confident
        about and tell your studio about the rest — they can sort it out.
      </p>` : ''}
    </td></tr>`);
}

function studioReport(studioName, rows, todayStr) {
  const byTeacher = {};
  rows.forEach(r => { (byTeacher[r.teacher_name ?? '—'] ??= []).push(r); });

  const ranked = Object.entries(byTeacher)
    .sort((a, b) => b[1].length - a[1].length);

  return shell(`
    <tr><td style="padding:24px;color:#1c1c1e;font-size:15px;line-height:1.65;">
      <p style="margin:0 0 6px;font-size:17px;font-weight:bold;">
        ${esc(studioName)} — attendance still to mark
      </p>
      <p style="margin:0 0 18px;color:#666666;font-size:14px;">
        ${rows.length} lesson${rows.length !== 1 ? 's' : ''} across
        ${ranked.length} teacher${ranked.length !== 1 ? 's' : ''}.
        Each of them has had this list too.
      </p>

      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="border-collapse:collapse;font-size:14px;margin:0 0 20px;">
        ${ranked.map(([teacher, list]) => {
          const stale = list.filter(r => daysAgo(r.date, todayStr) >= STALE_DAYS).length;
          return `<tr>
            <td style="padding:7px 10px 7px 0;border-bottom:1px solid #eeeeee;color:#1c1c1e;font-weight:bold;">
              ${esc(teacher)}
            </td>
            <td style="padding:7px 0;border-bottom:1px solid #eeeeee;color:#666666;text-align:right;white-space:nowrap;">
              ${list.length} lesson${list.length !== 1 ? 's' : ''}
              ${stale ? `<span style="color:#dc2626;font-weight:bold;"> · ${stale} over a fortnight</span>` : ''}
            </td>
          </tr>`;
        }).join('')}
      </table>

      <p style="margin:0 0 8px;font-size:12px;font-weight:bold;letter-spacing:0.08em;
                text-transform:uppercase;color:#E8491E;">Every outstanding lesson</p>
      ${rowsTable(rows, todayStr, true)}
    </td></tr>`);
}
