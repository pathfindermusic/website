// ============================================================
// PATHFINDER PORTAL — stop lesson reminders
//
// The link in every reminder email. Followed from an email client
// with no session, so it authenticates on a random per-student
// token rather than a login.
//
// Turns reminders off for the whole family — a parent with three
// children means one decision, not three.
//
// GET only: it returns a page, and it is the safest thing to be
// prefetched by an email scanner. Turning reminders off by
// accident is recoverable; the page offers to turn them back on.
// ============================================================

const SUPABASE_URL         = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const SITE                 = 'https://www.pathfindermusiclessons.com.au';

exports.handler = async (event) => {
  const token = event.queryStringParameters?.t;
  const undo  = event.queryStringParameters?.undo === '1';

  if (!token || !/^[0-9a-f-]{36}$/i.test(token)) {
    return page('That link does not look right',
      'Please use the link from a recent reminder email, or contact your studio.');
  }

  const headers = {
    'Content-Type':  'application/json',
    'apikey':        SUPABASE_SERVICE_KEY,
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
  };

  try {
    const findRes = await fetch(
      `${SUPABASE_URL}/rest/v1/students?reminder_token=eq.${token}` +
      `&select=id,user_id,parent_email,email`, { headers });
    const found = await findRes.json();

    if (!Array.isArray(found) || !found.length) {
      return page('Link not recognised',
        'This link may have expired. Contact your studio and they can change it for you.');
    }

    const me = found[0];

    // Everyone in the family. Siblings may share a login, or simply
    // share a parent's address — either identifies a household.
    const conditions = [`id.eq.${me.id}`];
    if (me.user_id)      conditions.push(`user_id.eq.${me.user_id}`);
    if (me.parent_email) conditions.push(`parent_email.eq.${encodeURIComponent(me.parent_email)}`);

    const famRes = await fetch(
      `${SUPABASE_URL}/rest/v1/students?or=(${conditions.join(',')})&select=id`, { headers });
    const family = await famRes.json();
    const ids = (Array.isArray(family) ? family : [me]).map(s => s.id);

    await fetch(
      `${SUPABASE_URL}/rest/v1/students?id=in.(${ids.join(',')})`, {
        method: 'PATCH',
        headers: { ...headers, Prefer: 'return=minimal' },
        body: JSON.stringify({ lesson_reminders: undo }),
      });

    console.log(`[optout] reminders ${undo ? 'on' : 'off'} for ${ids.length} student(s)`);

    return undo
      ? page('Reminders turned back on',
          `You will get a courtesy email on the morning of each lesson${
            ids.length > 1 ? ', for everyone in your family' : ''}.`)
      : page('Reminders turned off',
          `You will not receive any more lesson reminders${
            ids.length > 1 ? ' for anyone in your family' : ''}. ` +
          `Your lessons are unaffected, and you can still see them in the portal.`,
          `${SITE}/.netlify/functions/reminder-optout?t=${token}&undo=1`);

  } catch (err) {
    console.error('[optout] failed:', err.message);
    return page('Something went wrong',
      'We could not update your preference. Please contact your studio and they will sort it out.');
  }
};

function page(title, message, undoUrl) {
  return {
    statusCode: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
    body: `<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title} — Pathfinder Music Lessons</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
</head>
<body style="margin:0;background:#f5f5f7;font-family:'Inter',Arial,sans-serif;">
  <div style="max-width:520px;margin:64px auto;padding:0 16px;">
    <div style="background:#ffffff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.08);">
      <div style="background:#1c1c1e;padding:18px 28px;border-bottom:3px solid #E8491E;">
        <div style="color:#E8491E;font-size:11px;letter-spacing:0.12em;text-transform:uppercase;font-weight:700;">
          Pathfinder Music Lessons
        </div>
      </div>
      <div style="padding:32px 28px;color:#1c1c1e;">
        <h1 style="margin:0 0 12px;font-size:22px;font-weight:800;">${title}</h1>
        <p style="margin:0 0 20px;font-size:15px;line-height:1.65;color:#4a4a4a;">${message}</p>
        ${undoUrl ? `<a href="${undoUrl}"
             style="display:inline-block;background:#E8491E;color:#ffffff;text-decoration:none;
                    padding:10px 18px;border-radius:4px;font-size:14px;font-weight:600;">
             Actually, keep sending them</a>` : ''}
        <p style="margin:24px 0 0;font-size:13px;">
          <a href="${SITE}" style="color:#E8491E;text-decoration:none;">pathfindermusiclessons.com.au</a>
        </p>
      </div>
    </div>
  </div>
</body></html>`,
  };
}
