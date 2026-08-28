// ============================================================
// PATHFINDER PORTAL — lesson reminders
//
// Runs each morning and emails a courtesy reminder to students
// who have opted in and have a lesson today.
//
// Scheduled from netlify.toml at 20:00 UTC — 6 AM in Melbourne
// through winter, 7 AM through daylight saving. Both comfortably
// before anyone is up, which is all the admins asked for. Netlify
// cron only understands UTC, so a fixed local hour would drift by
// an hour twice a year; an early-morning window avoids caring.
//
// OPT-IN. Nobody is emailed unless someone asked for it.
// ============================================================

const SUPABASE_URL         = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const RESEND_API_KEY       = process.env.RESEND_API_KEY;
const SITE                 = 'https://www.pathfindermusiclessons.com.au';

const DAY_NAMES = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];

exports.handler = async () => {
  // What is today in Melbourne? At 20:00 UTC it is already tomorrow
  // there, so the server's own date would be a day behind.
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Australia/Melbourne',
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date());

  const melbourneHour = Number(new Intl.DateTimeFormat('en-AU', {
    timeZone: 'Australia/Melbourne', hour: 'numeric', hour12: false,
  }).format(new Date()));

  console.log(`[reminders] ${today} in Melbourne, local hour ${melbourneHour}`);

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
    // Today's lessons, with everything the email needs
    const rows = await get(
      `student_schedule_view?date=eq.${today}` +
      `&occurrence_status=eq.scheduled` +
      `&select=student_id,occurrence_id,start_time,duration_mins,instrument,` +
      `lesson_type,teacher_name,studio_name,studio_email,teaching_room,` +
      `virtual_room_link,is_online`);

    if (!rows.length) {
      console.log('[reminders] no lessons today');
      return ok({ date: today, lessons: 0, sent: 0 });
    }

    // Only those who asked for reminders
    const ids = [...new Set(rows.map(r => r.student_id))];
    const students = await get(
      `students?id=in.(${ids.join(',')})&lesson_reminders=is.true` +
      `&select=id,user_id,email,parent_email,parent_name,reminder_token,status`);

    const wanted = students.filter(s => ['active','trial'].includes(s.status));
    if (!wanted.length) {
      console.log('[reminders] nobody opted in for today');
      return ok({ date: today, lessons: rows.length, sent: 0 });
    }

    // Login addresses live in auth.users, not profiles
    const authList = await get('../auth/v1/admin/users?page=1&per_page=1000')
      .catch(() => ({ users: [] }));
    const emailById = {};
    (authList?.users ?? []).forEach(u => { emailById[u.id] = u.email; });

    const profiles = await get(
      `profiles?id=in.(${wanted.map(s => s.user_id).filter(Boolean).join(',')})` +
      `&select=id,first_name,last_name`);
    const nameById = {};
    profiles.forEach(p => { nameById[p.id] = p; });

    // Already sent? The schedule could fire twice, and a duplicate
    // reminder is worse than none.
    const already = await get(
      `reminder_log?occurrence_id=in.(${[...new Set(rows.map(r => r.occurrence_id))].join(',')})` +
      `&select=student_id,occurrence_id`);
    const sentKey = new Set(already.map(r => `${r.student_id}:${r.occurrence_id}`));

    const byStudent = {};
    wanted.forEach(s => { byStudent[s.id] = s; });

    let sent = 0, skipped = 0, failed = 0;

    for (const r of rows) {
      const s = byStudent[r.student_id];
      if (!s) { skipped++; continue; }
      if (sentKey.has(`${r.student_id}:${r.occurrence_id}`)) { skipped++; continue; }

      const to = [emailById[s.user_id], s.email, s.parent_email]
        .filter(Boolean)
        .filter((v, i, a) => a.indexOf(v) === i);
      if (!to.length) { skipped++; continue; }

      const p     = nameById[s.user_id] ?? {};
      const first = s.parent_name?.split(' ')[0] || p.first_name || 'there';
      const who   = `${p.first_name ?? ''} ${p.last_name ?? ''}`.trim();

      const html = reminderEmail({
        greeting: first,
        student:  who,
        date:     formatLong(today),
        time:     formatTime(r.start_time),
        duration: `${r.duration_mins} minutes`,
        type:     r.lesson_type === 'group' ? 'Group Lesson' : 'Private Lesson',
        room:     r.is_online
                    ? (r.virtual_room_link || 'Online — your teacher will send a link')
                    : (r.teaching_room || `${r.studio_name} studio`),
        isOnline: !!r.is_online,
        teacher:  r.teacher_name,
        studio:   r.studio_name,
        from:     r.studio_email,
        optOut:   `${SITE}/.netlify/functions/reminder-optout?t=${s.reminder_token}`,
      });

      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Content-Type':  'application/json',
            'Authorization': `Bearer ${RESEND_API_KEY}`,
          },
          body: JSON.stringify({
            from:     `Pathfinder Music Lessons <${r.studio_email}>`,
            to,
            reply_to: r.studio_email,
            subject:  `Reminder: ${r.instrument} lesson today at ${formatTime(r.start_time)}`,
            html,
          }),
        });

        if (!res.ok) { failed++; console.error('[reminders]', await res.text()); continue; }

        await fetch(`${SUPABASE_URL}/rest/v1/reminder_log`, {
          method: 'POST',
          headers: { ...headers, Prefer: 'return=minimal' },
          body: JSON.stringify({
            student_id: s.id, occurrence_id: r.occurrence_id, sent_to: to.join(', '),
          }),
        });
        sent++;
      } catch (err) {
        failed++;
        console.error('[reminders] send failed:', err.message);
      }
    }

    console.log(`[reminders] ${sent} sent, ${skipped} skipped, ${failed} failed`);
    return ok({ date: today, lessons: rows.length, sent, skipped, failed });

  } catch (err) {
    console.error('[reminders] run failed:', err.message);
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};

function ok(payload) {
  return { statusCode: 200, body: JSON.stringify(payload) };
}

function formatTime(t) {
  if (!t) return '';
  const [h, m] = t.split(':').map(Number);
  const ampm = h >= 12 ? 'PM' : 'AM';
  const hr   = h % 12 || 12;
  return `${hr}:${String(m).padStart(2, '0')} ${ampm}`;
}

function formatLong(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(y, m - 1, d, 12);
  return `${DAY_NAMES[dt.getDay()]}, ${d} ${dt.toLocaleDateString('en-AU', { month: 'long' })} ${y}`;
}

function esc(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function reminderEmail(d) {
  const roomLabel = d.isOnline ? 'Lesson link' : 'Room';
  const roomValue = d.isOnline && /^https?:\/\//.test(d.room)
    ? `<a href="${esc(d.room)}" style="color:#E8491E;">${esc(d.room)}</a>`
    : esc(d.room);

  const row = (label, value) =>
    `<tr>
       <td style="padding:3px 14px 3px 0;color:#666666;font-size:13px;white-space:nowrap;">${label}</td>
       <td style="padding:3px 0;font-size:14px;color:#1c1c1e;font-weight:bold;">${value}</td>
     </tr>`;

  return `<!DOCTYPE html>
<html><body style="margin:0;padding:0;background:#f5f5f7;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f7;padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:520px;background:#ffffff;border-radius:8px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;">

        <tr><td style="background:#1c1c1e;padding:18px 24px;border-bottom:3px solid #E8491E;">
          <div style="color:#E8491E;font-size:11px;letter-spacing:0.12em;text-transform:uppercase;font-weight:bold;">
            Pathfinder Music Lessons
          </div>
        </td></tr>

        <tr><td style="padding:24px;color:#1c1c1e;font-size:15px;line-height:1.65;">
          <p style="margin:0 0 14px;">Hi ${esc(d.greeting)},</p>
          <p style="margin:0 0 18px;">
            Just a courtesy reminder about ${esc(d.student)}'s ${esc(d.type).toLowerCase()} today.
          </p>

          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                 style="margin:0 0 18px;background:#f5f5f7;border-left:4px solid #E8491E;
                        border-radius:0 4px 4px 0;">
            <tr><td style="padding:14px 16px;">
              <table role="presentation" cellpadding="0" cellspacing="0">
                ${row('Date',       esc(d.date))}
                ${row('Start time', `${esc(d.time)} <span style="font-weight:normal;color:#666666;">(${esc(d.duration)})</span>`)}
                ${row('Teacher',    esc(d.teacher))}
                ${row(roomLabel,    roomValue)}
              </table>
            </td></tr>
          </table>

          <p style="margin:0 0 14px;">
            Please let us know as soon as possible if you are unable to attend.
          </p>
          <p style="margin:0;">Thanks,<br>${esc(d.studio)} Studio<br>Pathfinder Music Lessons</p>
        </td></tr>

        <tr><td style="padding:16px 24px;border-top:1px solid #eeeeee;color:#999999;font-size:12px;line-height:1.6;">
          <a href="${esc(d.optOut)}" style="color:#999999;">Stop these reminders</a>
          &nbsp;·&nbsp;
          <a href="mailto:${esc(d.from)}" style="color:#999999;">${esc(d.from)}</a><br>
          <a href="${SITE}" style="color:#999999;">pathfindermusiclessons.com.au</a>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body></html>`;
}
