// ============================================================
// PATHFINDER PORTAL — receive a website enquiry
//
// Creates a prospective student and a follow-up task from the
// website contact form.
//
// PARALLEL RUN: the form still posts to Zoho, which remains
// authoritative and still sends both the acknowledgement to the
// enquirer and the notification to the studio. This function
// therefore sends NOTHING — otherwise every enquirer would get
// two identical emails. See SEND_ACKNOWLEDGEMENT below for the
// cutover.
//
// The browser fires this with keepalive so it survives the page
// navigating to Zoho's thank-you URL. A failure here must never
// affect the Zoho submission — the old system stays intact.
// ============================================================

const SUPABASE_URL         = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

// Flip to true at cutover, once Zoho stops sending it
const SEND_ACKNOWLEDGEMENT = false;

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
    let studioId = null;
    if (studio) {
      const sRes = await api(`studios?name=ilike.${encodeURIComponent(studio)}&select=id,email,name`);
      const rows = await sRes.json();
      if (Array.isArray(rows) && rows[0]) studioId = rows[0].id;
    }

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

    // Silent during the parallel run — Zoho is still sending both the
    // acknowledgement and the studio notification.
    if (SEND_ACKNOWLEDGEMENT) {
      console.log('[receive-enquiry] acknowledgement would be sent here');
    }

    console.log('[receive-enquiry] created enquiry for', email);
    return json(200, { ok: true, student_id: student.id }, cors);

  } catch (err) {
    // Never surface a failure to the browser in a way that could
    // disturb the Zoho submission. Log it and return 200.
    console.error('[receive-enquiry] failed:', err.message);
    return json(200, { ok: false, error: 'logged' }, cors);
  }
};

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
