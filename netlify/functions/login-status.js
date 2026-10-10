// ============================================================
// Netlify Function: login-status
//
// Read-only. Returns, for the auth users an admin asks about, the two
// facts the Portal Logins report needs and the browser cannot read for
// itself (auth.users is not exposed to the client):
//   email, last_sign_in_at (+ created_at)
//
// Admin-only: the caller's Portal session token is checked against
// Supabase and their role read from profiles — same check send-email.js
// applies to its 'teachers' mode. (create-user.js's older actions don't
// do this; this one deliberately does, because it returns email
// addresses and sign-in times.)
//
// Request:  POST { userIds: ['uuid', ...] }   + Authorization: Bearer <session>
// Response: { users: [{ id, email, last_sign_in_at, created_at }] }
//
// Environment variables (already set for the other functions):
//   SUPABASE_URL, SUPABASE_SERVICE_KEY
// ============================================================

const json = (statusCode, obj) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(obj),
});

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { error: 'Method not allowed' });

  let body;
  try { body = JSON.parse(event.body ?? '{}'); }
  catch { return json(400, { error: 'Invalid request body' }); }

  const SUPABASE_URL         = process.env.SUPABASE_URL;
  const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    return json(500, { error: 'Server misconfigured — Supabase env vars missing.' });
  }
  const sb = { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` };

  try {
    // ---- Who is asking? Must be a signed-in, active admin/superuser ----
    const token = (event.headers?.authorization ?? event.headers?.Authorization ?? '').replace(/^Bearer\s+/i, '');
    let role = null;
    if (token) {
      const ur = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
        headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${token}` },
      });
      const u = ur.ok ? await ur.json() : null;
      if (u?.id) {
        const pr = await fetch(`${SUPABASE_URL}/rest/v1/profiles?id=eq.${u.id}&status=eq.active&select=role`, { headers: sb });
        const rows = pr.ok ? await pr.json() : [];
        role = rows?.[0]?.role ?? null;
      }
    }
    if (role !== 'admin' && role !== 'superuser') {
      return json(403, { error: 'Only a signed-in admin can view login activity.' });
    }

    const wanted = new Set((Array.isArray(body.userIds) ? body.userIds : []).map(String));
    if (wanted.size === 0) return json(200, { users: [] });

    // ---- Page through the auth users (1000 per page), keep only those asked for ----
    const users = [];
    for (let page = 1; page <= 20; page++) {
      const res  = await fetch(`${SUPABASE_URL}/auth/v1/admin/users?page=${page}&per_page=1000`, { headers: sb });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) return json(502, { error: data?.message ?? 'Could not list users.' });
      const batch = data?.users ?? [];
      batch.forEach(u => {
        if (wanted.has(u.id)) {
          users.push({
            id: u.id,
            email: u.email ?? null,
            last_sign_in_at: u.last_sign_in_at ?? null,
            created_at: u.created_at ?? null,
          });
        }
      });
      if (batch.length < 1000) break;
    }
    return json(200, { users });
  } catch (err) {
    return json(500, { error: err.message });
  }
};
