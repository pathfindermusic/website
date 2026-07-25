// ============================================================
// Netlify Function: create-user
// Creates a Supabase auth user server-side using the service
// role key — which must never be exposed in the browser.
//
// Called by the portal when an admin adds a new student,
// teacher or admin user.
//
// Environment variables required in Netlify dashboard:
//   SUPABASE_URL          — your project URL
//   SUPABASE_SERVICE_KEY  — your service role key (secret!)
// ============================================================

const { createClient } = require('@supabase/supabase-js');

exports.handler = async (event) => {

  // Only allow POST
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: JSON.stringify({ error: 'Method not allowed' }) };
  }

  // Parse request body
  let body;
  try {
    body = JSON.parse(event.body);
  } catch {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid request body' }) };
  }

  const { email, role } = body;

  if (!email || !role) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Email and role are required' }) };
  }

  // Validate role
  const allowedRoles = ['student', 'teacher', 'admin', 'superuser'];
  if (!allowedRoles.includes(role)) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid role' }) };
  }

  // Validate email format
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid email address' }) };
  }

  // Create Supabase admin client using service role key
  const supabaseAdmin = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  try {
    // Check if user already exists
    const { data: existingUsers } = await supabaseAdmin.auth.admin.listUsers();
    const existing = existingUsers?.users?.find(u => u.email === email);

    if (existing) {
      // User already exists — return their ID so the portal can link them
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id:      existing.id,
          email:   existing.email,
          existed: true,
        }),
      };
    }

    // Generate a secure temporary password
    // Admin can send a password reset email to the user afterwards
    const tempPassword = generateTempPassword();

    // Create the auth user
    const { data, error } = await supabaseAdmin.auth.admin.createUser({
      email,
      password:      tempPassword,
      email_confirm: true, // auto-confirm so they can log in straight away
    });

    if (error) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: error.message }),
      };
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id:           data.user.id,
        email:        data.user.email,
        tempPassword, // returned so admin can share with the new user
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

// Generate a readable temporary password: e.g. Welcome-4729!
function generateTempPassword() {
  const num = Math.floor(1000 + Math.random() * 9000);
  return `Welcome-${num}!`;
}
