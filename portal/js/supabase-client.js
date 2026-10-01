// ============================================================
// PATHFINDER PORTAL — Supabase Client
// Replace the two values below with your own from:
// Supabase Dashboard → Project Settings → API
// ============================================================

const SUPABASE_URL  = 'https://oxuyzcjgxmohpqyijpip.supabase.co';   // e.g. https://xxxxxxxxxxxx.supabase.co
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im94dXl6Y2pneG1vaHBxeWlqcGlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MTQ3NzMsImV4cCI6MjEwMDQ5MDc3M30.3BiBBOqQFMwpb7mZC7xLISDp2EJCXfML-7_wq-Imwws';      // starts with eyJ...

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
// Blocks an account that has been deactivated since it last signed in.
// A session persists, so checking only at login would let someone
// deactivated this morning carry on until their token expired.
async function isAccountBlocked(profile) {
  if (!profile) return true;
  if (profile.status === 'inactive') return true;
  if (profile.role !== 'student') return false;

  const { data: stu } = await db.from('students')
    .select('status').eq('user_id', profile.id).maybeSingle();
  return !!stu && ['inactive','lapsed','prospective'].includes(stu.status);
}

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
  // A student login can be shared by several siblings (phase 10, Oct
  // 2026) — showing one child's first name here would always privilege
  // whichever of them first registered, so a student login shows the
  // family instead of an individual.
  const isStudent = profile.role === 'student';
  if (avatarEl) avatarEl.textContent = isStudent
    ? (profile.last_name?.[0] ?? '').toUpperCase()
    : getInitials(profile);
  if (nameEl)   nameEl.textContent   = isStudent
    ? `${profile.last_name ?? ''} family`.trim()
    : `${profile.first_name} ${profile.last_name}`;
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
  if (!(date instanceof Date)) date = new Date(date);
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
  d.setHours(12, 0, 0, 0); // use noon not midnight to avoid UTC day boundary issues
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

/** Same Beginner/Intermediate/Advanced banding as skillLabel(), as a colour
 *  — matches the dots used on the student's own progress view. */
function skillBandColour(level) {
  if (level <= 3) return '#2563eb';
  if (level <= 6) return '#d97706';
  return '#16a34a';
}

// ============================================================
// BOK GRADE ANIMAL NAMES
// ============================================================
// A fun, per-instrument nickname for each of the 9 shared grade levels
// (Pre-Grade 1 through Grade 8) — sitting ALONGSIDE the official
// "Tier — Grade N" label, never replacing it (admins voted to keep
// both, Sep 2026). Keyed by the exact instrument string used in
// INSTRUMENTS, then indexed by bok_grade_levels.sort_order (0-8).
//
// Only the instruments the admins actually asked for get a theme.
// Music Theory, Band and Other are deliberately left out — they're
// catch-alls rather than one real instrument, so gradeAnimalName()
// just returns '' for them and every caller falls back to the plain
// label. The same happens for any instrument added later that hasn't
// been given a theme yet.
const BOK_GRADE_ANIMAL_NAMES = {
  'Guitar': [
    'Tadpole Strummer', 'Cricket Chords', 'Sparrow Picker', 'Robin Riffer',
    'Falcon Fretwork', 'Hawk Harmonics', 'Eagle Soloist', 'Phoenix Fingers',
    'Dragon Shredder',
  ],
  'Bass': [
    'Guppy', 'Tadfish', 'Catfish', 'Eel',
    'Barracuda', 'Ray', 'Tuna Titan', 'Orca',
    'Kraken',
  ],
  'Drums': [
    'Bunny Beats', 'Woodpecker', 'Joey Thumper', 'Gorilla Groove',
    'Rhino Rhythm', 'Elephant Stomp', 'Buffalo Boom', 'Thunderbird',
    'Rex Rhythm',
  ],
  'Piano / Keyboard': [
    'Kitten Keys', 'Fox Trot', 'Fawn Fingers', 'Swan Song',
    'Peacock Player', 'Panther Player', 'Stallion Sonata', 'Griffin',
    'Unicorn Virtuoso',
  ],
  'Violin': [
    'Caterpillar', 'Ladybird', 'Dragonfly', 'Butterfly Bow',
    'Hummingbird', 'Firefly Fiddler', 'Swallow Soloist', 'Phoenix Fiddler',
    'Griffin Virtuoso',
  ],
  'Voice / Singing': [
    'Chick', 'Sparrow', 'Robin', 'Canary',
    'Lark', 'Nightingale', 'Songbird Star', 'Swan Soprano',
    'Phoenix Voice',
  ],
  'Ukulele': [
    'Sand Crab', 'Hermit Crab', 'Sea Turtle Hatchling', 'Clownfish',
    'Dolphin', 'Flamingo', 'Toucan', 'Sea Turtle Elder',
    'Island Phoenix',
  ],
  'Saxophone': [
    'Kitten', 'Alley Cat', 'Bobcat', 'Cougar',
    'Panther', 'Jaguar', 'Lion', 'Tiger',
    'Sabertooth',
  ],
};

/** The animal nickname for an instrument + bok_grade_levels.sort_order
 *  (0-8), or '' when that instrument has no theme yet. */
function gradeAnimalName(instrument, sortOrder) {
  const names = BOK_GRADE_ANIMAL_NAMES[instrument];
  return (names && names[sortOrder]) || '';
}

/** The standard "Tier — Grade N" label for a bok_grade_levels row,
 *  with the instrument's animal nickname appended when it has one —
 *  e.g. "Intermediate — Grade 5 (Hawk Harmonics)". `gradeLevel` needs
 *  at least {tier, label, sort_order}; a query that only selects
 *  tier/label (not sort_order) will just never show an animal name,
 *  rather than error. Falls back to '' when there's no grade at all,
 *  so callers can write `g ? gradeLabel(g, inst) : 'Not yet graded'`. */
function gradeLabel(gradeLevel, instrument) {
  if (!gradeLevel) return '';
  const base   = `${gradeLevel.tier} — ${gradeLevel.label}`;
  const animal = gradeAnimalName(instrument, gradeLevel.sort_order);
  return animal ? `${base} (${animal})` : base;
}

/** Builds <option> HTML for a "Grade" select from the full
 *  bok_grade_levels list, labelling each with gradeLabel() for the
 *  given instrument. Centralised so every grade dropdown in the
 *  Portal — student edit, teacher's "record grade", the BoK library —
 *  shows the same animal names instead of each page inlining its own
 *  "${g.tier} — ${g.label}" and drifting out of sync. */
function gradeOptionsHtml(gradeLevels, instrument, selectedId = '') {
  return (gradeLevels ?? []).map(g =>
    `<option value="${g.id}" ${g.id === selectedId ? 'selected' : ''}>${gradeLabel(g, instrument)}</option>`
  ).join('');
}

// ------------------------------------------------------------
// Default a studio filter to the admin's own studio.
//
// Admins can see and work on every studio — restricting that in the
// database caused more problems than it solved — but their day starts
// with their own. Only applied where they cover exactly one; a super
// user, or an admin covering several, sees everything by default.
// ------------------------------------------------------------
function applyDefaultStudio(selectId, myStudioIds, onChange) {
  const sel = document.getElementById(selectId);
  if (!sel) { console.warn(`[studio default] no #${selectId} on this page`); return; }
 
  if (!Array.isArray(myStudioIds) || myStudioIds.length !== 1) {
    // Covering several studios, or none resolved — either way there is no
    // single studio to default to. Worth saying: a query that forgets to
    // select studio_ids lands here silently and the default never applies.
    console.info('[studio default] not applied — covers',
      Array.isArray(myStudioIds) ? myStudioIds.length : 'unknown', 'studios');
    return;
  }
 
  const wanted = myStudioIds[0];
  if (![...sel.options].some(o => o.value === wanted)) {
    console.warn('[studio default] options not populated yet — call this after filling the select');
    return;
  }
 
  sel.value = wanted;
  if (typeof onChange === 'function') onChange();
}
 