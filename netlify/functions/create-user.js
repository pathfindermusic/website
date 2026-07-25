// ============================================================
// Netlify Function: create-user (no npm dependencies)
// Uses Supabase Admin REST API directly via fetch
// Handles duplicate email detection server-side
// ============================================================

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: JSON.stringify({ error: 'Method not allowed' }) };
  }

  let body;
  try { body = JSON.parse(event.body); }
  catch { return { statusCode: 400, body: JSON.stringify({ error: 'Invalid request body' }) }; }

  const { email, role } = body;
  if (!email || !role) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Email and role are required' }) };
  }

  const SUPABASE_URL         = process.env.SUPABASE_URL;
  const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    return { statusCode: 500, body: JSON.stringify({ error: 'Server configuration error — missing environment variables' }) };
  }

  const headers = {
    'Content-Type':  'application/json',
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
    'apikey':        SUPABASE_SERVICE_KEY,
  };

  try {
    // Check if user already exists in auth.users
    const listRes = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users?page=1&per_page=1000`,
      { headers }
    );
    const listData = await listRes.json();
    const existing = (listData?.users ?? []).find(
      u => u.email?.toLowerCase() === email.toLowerCase()
    );

    if (existing) {
      // Check their role in profiles table
      const profileRes = await fetch(
        `${SUPABASE_URL}/rest/v1/profiles?id=eq.${existing.id}&select=role`,
        { headers }
      );
      const profileData = await profileRes.json();
      const existingRole = profileData?.[0]?.role ?? 'user';
      const roleLabel = existingRole.charAt(0).toUpperCase() + existingRole.slice(1);

      return {
        statusCode: 409, // Conflict
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          error: `This email is already registered as a ${roleLabel}. Please use a different email.`,
          existed: true,
        }),
      };
    }

    // Generate a readable temporary password
    const num          = Math.floor(1000 + Math.random() * 9000);
    const tempPassword = `Welcome-${num}!`;

    // Create new auth user
    const createRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
      method:  'POST',
      headers,
      body: JSON.stringify({
        email,
        password:      tempPassword,
        email_confirm: true,
      }),
    });

    const createData = await createRes.json();

    if (!createRes.ok) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: createData?.message ?? 'Could not create user account.' }),
      };
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id:           createData.id,
        email:        createData.email,
        tempPassword,
        existed:      false,
      }),
    };

  } catch (err) {
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: err.message }),
    };
  }
};
