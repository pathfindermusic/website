// ============================================================
// PATHFINDER PORTAL — Supabase Client
// Replace the two values below with your own from:
// Supabase Dashboard → Project Settings → API
// ============================================================

const SUPABASE_URL  = 'YOUR_SUPABASE_PROJECT_URL';   // e.g. https://xxxxxxxxxxxx.supabase.co
const SUPABASE_ANON = 'YOUR_SUPABASE_ANON_KEY';      // starts with eyJ...

// Load Supabase via CDN (included in each HTML page's <head>)
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON);

// ============================================================
// AUTH HELPERS
// ============================================================

/** Returns the current session, or null if not logged in */
async function getSession() {
  const { data: { session } } = await db.auth.getSession();
  return session;
}

/** Returns the full profile row for the current user */
async function getProfile() {
  const session = await getSession();
  if (!session) return null;
  const { data, error } = await db
    .from('profiles')
    .select('*')
    .eq('id', session.user.id)
    .single();
  if (error) { console.error('Profile fetch error:', error); return null; }
  return data;
}

/** Redirect to login if not authenticated */
async function requireAuth(allowedRoles = []) {
  const session = await getSession();
  if (!session) {
    window.location.href = '/portal/login.html';
    return null;
  }
  const profile = await getProfile();
  if (!profile) {
    window.location.href = '/portal/login.html';
    return null;
  }
  if (allowedRoles.length > 0 && !allowedRoles.includes(profile.role)) {
    window.location.href = '/portal/login.html';
    return null;
  }
  // If must change password, redirect unless already on change-password page
  if (profile.must_change_password && !window.location.pathname.includes('change-password')) {
    window.location.href = '/portal/change-password.html';
    return null;
  }
  return profile;
}

/** Sign out and redirect to login */
async function signOut() {
  await db.auth.signOut();
  window.location.href = '/portal/login.html';
}

// ============================================================
// UI HELPERS
// ============================================================

/** Get initials from a profile */
function getInitials(profile) {
  return ((profile.first_name?.[0] ?? '') + (profile.last_name?.[0] ?? '')).toUpperCase();
}

/** Format a role string for display */
function formatRole(role) {
  const map = {
    superuser: 'Super User',
    admin:     'Admin',
    teacher:   'Teacher',
    student:   'Student',
  };
  return map[role] ?? role;
}

/** Show a toast notification */
function showToast(message, type = 'success') {
  const wrap = document.getElementById('toastWrap') ?? createToastWrap();
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  const icons = { success: '✓', error: '✕', warning: '⚠' };
  toast.innerHTML = `<span>${icons[type] ?? '•'}</span> ${message}`;
  wrap.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
}

function createToastWrap() {
  const wrap = document.createElement('div');
  wrap.id = 'toastWrap';
  wrap.className = 'toast-wrap';
  document.body.appendChild(wrap);
  return wrap;
}

/** Populate the top nav user info */
function renderTopNavUser(profile) {
  const avatarEl = document.getElementById('navAvatar');
  const nameEl   = document.getElementById('navName');
  const roleEl   = document.getElementById('navRole');
  if (avatarEl) avatarEl.textContent = getInitials(profile);
  if (nameEl)   nameEl.textContent   = `${profile.first_name} ${profile.last_name}`;
  if (roleEl)   roleEl.textContent   = formatRole(profile.role);
}

/** Show loading spinner in a container */
function showLoading(containerId) {
  const el = document.getElementById(containerId);
  if (el) el.innerHTML = `<div class="loading"><div class="spinner"></div> Loading…</div>`;
}

/** Show empty state in a container */
function showEmpty(containerId, title = 'No results', message = '') {
  const el = document.getElementById(containerId);
  if (el) el.innerHTML = `
    <div class="empty-state">
      <div class="empty-state-icon">📭</div>
      <h3>${title}</h3>
      ${message ? `<p>${message}</p>` : ''}
    </div>`;
}

// ============================================================
// DATE / SCHEDULE HELPERS
// ============================================================

/** Returns an ISO date string (YYYY-MM-DD) for a given Date */
function toISODate(date) {
  // Use local date parts to avoid UTC timezone shift in Australian timezones
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// Parse a date string as LOCAL time to avoid UTC timezone day shifts
// e.g. "2026-07-29" → Wed 29 July in AEST, not Tue 28 July
function parseLocalDate(dateStr) {
  if (!dateStr) return new Date();
  const [y, m, d] = dateStr.slice(0, 10).split('-').map(Number);
  return new Date(y, m - 1, d);
}

/** Returns the Monday of the week containing the given date */
function getWeekStart(date) {
  const d = new Date(date);
  const day = d.getDay(); // 0=Sun
  const diff = (day === 0) ? -6 : 1 - day; // shift to Monday
  d.setDate(d.getDate() + diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

/** Returns array of 6 dates Mon–Sat for a given week start */
function getWeekDays(weekStart) {
  return Array.from({ length: 6 }, (_, i) => {
    const d = new Date(weekStart);
    d.setDate(d.getDate() + i);
    return d;
  });
}

/** Format a date as "Mon 23 Jul" */
function formatShortDate(date) {
  return date.toLocaleDateString('en-AU', { weekday: 'short', day: 'numeric', month: 'short' });
}

/** Format a date as "23 July 2026" */
function formatLongDate(date) {
  return date.toLocaleDateString('en-AU', { day: 'numeric', month: 'long', year: 'numeric' });
}

/** Format a time string "HH:MM:SS" as "4:30 PM" */
function formatTime(timeStr) {
  const [h, m] = timeStr.split(':').map(Number);
  const ampm = h >= 12 ? 'PM' : 'AM';
  const hour = h % 12 || 12;
  return `${hour}:${String(m).padStart(2, '0')} ${ampm}`;
}

/** Format duration in minutes as "30 min" or "1 hr" */
function formatDuration(mins) {
  if (mins < 60) return `${mins} min`;
  if (mins === 60) return '1 hr';
  return `${mins / 60} hrs`;
}

/** Returns the attendance pill HTML for a given status */
function attendancePill(status) {
  if (!status) return `<span class="pill pill-scheduled">Not marked</span>`;
  const map = {
    present:           ['pill-present',       'Present'],
    absent_no_credit:  ['pill-absent-nc',     'Absent — No Credit'],
    absent_notice:     ['pill-absent-notice', 'Absent — Notice Given'],
    teacher_cancelled: ['pill-cancelled',     'Teacher Cancelled'],
  };
  const [cls, label] = map[status] ?? ['pill-scheduled', status];
  return `<span class="pill ${cls}">${label}</span>`;
}

/** Returns the skill level label for a given 0–8 number */
function skillLabel(level) {
  if (level <= 3) return `Beginner (${level})`;
  if (level <= 6) return `Intermediate (${level})`;
  return `Advanced (${level})`;
}
