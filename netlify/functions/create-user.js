// ============================================================
// Netlify Function: create-user
// Supports multiple actions via the 'action' parameter:
//   - create: create a new auth user
//   - get-email: get a user's email by their profile ID
// ============================================================

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: JSON.stringify({ error: 'Method not allowed' }) };
  }

  let body;
  try { body = JSON.parse(event.body); }
  catch { return { statusCode: 400, body: JSON.stringify({ error: 'Invalid request body' }) }; }

  const SUPABASE_URL         = process.env.SUPABASE_URL;
  const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    return { statusCode: 500, body: JSON.stringify({ error: 'Server configuration error' }) };
  }

  const headers = {
    'Content-Type':  'application/json',
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
    'apikey':        SUPABASE_SERVICE_KEY,
  };

  const action = body.action ?? 'create';

  // ---- GET EMAIL by user ID ----
  if (action === 'get-email') {
    const { userId } = body;
    if (!userId) return { statusCode: 400, body: JSON.stringify({ error: 'userId is required' }) };

    try {
      const res  = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, { headers });
      const data = await res.json();
      if (!res.ok) return { statusCode: 400, body: JSON.stringify({ error: data?.message ?? 'User not found' }) };
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: data.email }),
      };
    } catch (err) {
      return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
    }
  }

  // ---- DELETE USER ----
  if (action === 'delete-user') {
    const { userId } = body;
    if (!userId) return { statusCode: 400, body: JSON.stringify({ error: 'userId is required' }) };
    try {
      const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
        method: 'DELETE', headers,
      });
      if (!res.ok) {
        const data = await res.json();
        return { statusCode: 400, headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ error: data?.message ?? 'Could not delete user' }) };
      }
      return { statusCode: 200, headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ success: true }) };
    } catch (err) {
      return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
    }
  }

  // ---- RESET PASSWORD ----
  if (action === 'reset-password') {
    const { email } = body;
    if (!email) return { statusCode: 400, body: JSON.stringify({ error: 'Email is required' }) };

    try {
      // Use /recover endpoint which actually sends the email
      // (generate_link only creates a link, doesn't send email)
      // redirect_to must be a QUERY parameter — /recover ignores it in
      // the body and silently falls back to the project's Site URL.
      const redirectTo = encodeURIComponent(
        'https://www.pathfindermusiclessons.com.au/portal/change-password.html'
      );
      const res = await fetch(`${SUPABASE_URL}/auth/v1/recover?redirect_to=${redirectTo}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_SERVICE_KEY,
        },
        body: JSON.stringify({
          email,
          gotrue_meta_security: {},
        }),
      });

      // /recover returns 200 with empty body on success
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        return {
          statusCode: 400,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ error: data?.message ?? 'Could not send reset email' }),
        };
      }

      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ success: true }),
      };
    } catch (err) {
      return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
    }
  }

  // ---- CREATE new auth user ----
  const { email, role } = body;
  if (!email || !role) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Email and role are required' }) };
  }

  try {
    // Check if user already exists
    const listRes  = await fetch(`${SUPABASE_URL}/auth/v1/admin/users?page=1&per_page=1000`, { headers });
    const listData = await listRes.json();
    if (!listRes.ok) {
      console.error('[create-user] Could not list users:',
        listRes.status, JSON.stringify(listData));
      return {
        statusCode: 502,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          error: 'Could not check existing accounts: ' +
                 (listData?.msg ?? listData?.message ?? listRes.status),
        }),
      };
    }
    const existing = (listData?.users ?? []).find(
      u => u.email?.toLowerCase() === email.toLowerCase()
    );

    if (existing) {
      const profileRes  = await fetch(
        `${SUPABASE_URL}/rest/v1/profiles?id=eq.${existing.id}&select=role`,
        { headers }
      );
      const profileData = await profileRes.json();
      const existingRole = profileData?.[0]?.role ?? 'user';
      const roleLabel    = existingRole.charAt(0).toUpperCase() + existingRole.slice(1);
      return {
        statusCode: 409,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          error: `This email is already registered as a ${roleLabel}. Please use a different email.`,
          existed: true,
        }),
      };
    }

    // Generate temporary password
    const num          = Math.floor(1000 + Math.random() * 9000);
    const tempPassword = `Welcome-${num}!`;

    // Create auth user
    const createRes  = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ email, password: tempPassword, email_confirm: true }),
    });
    const createData = await createRes.json();

    if (!createRes.ok) {
      console.error('[create-user] Supabase rejected createUser:',
        createRes.status, JSON.stringify(createData));
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          error: createData?.msg
              ?? createData?.message
              ?? createData?.error_description
              ?? `Could not create user account (${createRes.status}).`,
          detail: createData,
        }),
      };
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id: createData.id, email: createData.email, tempPassword, existed: false,
      }),
    };

  } catch (err) {
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};
