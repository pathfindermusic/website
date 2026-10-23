// ============================================================
// person-match.js — "do we already know this person?" and student flags.
//
// Shared by Enquiries, Tasks and Students.
//
//   findPossibleMatches(enq) / matchBanner(matches)
//       Previous relationship (same email, phone or exact name). Used to
//       live inside tasks.html only, so the Enquiries page — which also
//       calls it — hit a ReferenceError and never showed the box.
//
//   Flags (student-flags.sql): admins mark a student 'watch' or 'block'
//   (do not re-enrol). flagCheckContact() / flagCheckStudents() ask the
//   database which flagged people match some contact details, across every
//   studio. They NEVER throw: if student-flags.sql has not been run yet, or
//   a call fails, the page simply shows no flag warnings.
// ============================================================

// Does this enquiry look like someone we already know? Returning people
// send a fresh enquiry rather than reviving an old one, and it is often a
// past student rather than a lapsed enquiry. Matching on email, phone or
// exact name catches most of it — the admin judges the rest.
async function findPossibleMatches(enq) {
  const out    = new Map();
  const digits = s => String(s ?? '').replace(/\D/g, '');
  const myPhone = digits(enq.phone);

  const add = (row, why) => {
    if (!row || row.id === enq.id) return;
    if (out.has(row.id)) { out.get(row.id).why.add(why); return; }
    out.set(row.id, { ...row, why: new Set([why]) });
  };

  // Same email address
  if (enq.email) {
    const { data } = await db.from('students')
      .select('id,user_id,status,studio_id,email')
      .ilike('email', enq.email.trim());
    for (const r of (data ?? [])) add(r, 'same email');
  }

  // Same name, or same phone number
  const { data: profs } = await db.from('profiles')
    .select('id,first_name,last_name,phone')
    .ilike('first_name', (enq.first_name ?? '').trim())
    .ilike('last_name',  (enq.last_name  ?? '').trim());

  const { data: byPhone } = myPhone
    ? await db.from('profiles').select('id,first_name,last_name,phone')
    : { data: [] };

  const candidateIds = [
    ...(profs ?? []).map(p => p.id),
    ...(byPhone ?? []).filter(p => digits(p.phone) && digits(p.phone) === myPhone).map(p => p.id),
  ];

  if (candidateIds.length) {
    const { data } = await db.from('students')
      .select('id,user_id,status,studio_id,email,first_name,last_name')
      .in('user_id', [...new Set(candidateIds)]);
    for (const r of (data ?? [])) {
      const nameHit  = (profs   ?? []).some(p => p.id === r.user_id);
      const phoneHit = (byPhone ?? []).some(p => p.id === r.user_id && digits(p.phone) === myPhone);
      if (nameHit)  add(r, 'same name');
      if (phoneHit) add(r, 'same phone');
    }
  }

  const matches = [...out.values()];
  if (!matches.length) return [];

  // Names for display
  const { data: mp } = await db.from('profiles')
    .select('id,first_name,last_name')
    .in('id', matches.map(m => m.user_id).filter(Boolean));
  const nameOf = {};
  (mp ?? []).forEach(p => { nameOf[p.id] = `${p.first_name ?? ''} ${p.last_name ?? ''}`.trim(); });

  // A student's own name (students.first_name/last_name) is the source of
  // truth — siblings sharing a login would otherwise all show whichever
  // name is on the shared profiles row (phase 10, Oct 2026).
  return matches.map(m => ({
    ...m,
    name: (`${m.first_name ?? ''} ${m.last_name ?? ''}`.trim()) || nameOf[m.user_id] || '(unnamed)',
    why:  [...m.why].join(', '),
  }));
}

function matchBanner(matches) {
  if (!matches.length) return '';
  const LABEL = {
    active:'Currently enrolled', trial:'On a trial', inactive:'Past student',
    lapsed:'Lapsed enquiry', prospective:'Another open enquiry',
  };
  return `<div style="background:#fef3c7;border:1px solid #fcd34d;border-radius:var(--r-sm);
              padding:0.7rem 0.85rem;margin-bottom:1rem;font-size:0.82rem;color:#92400e;line-height:1.6;">
      <strong>We may already know this person.</strong>
      ${matches.map(m =>
        `<div style="margin-top:0.3rem;">${m.name} — ${LABEL[m.status] ?? m.status}
         <span style="opacity:0.75;">(${m.why})</span></div>`).join('')}
    </div>`;
}


// ------------------------------------------------------------
// Flags
// ------------------------------------------------------------
const FLAG_LEVEL_LABEL = { watch: 'Watch', block: 'Do not re-enrol' };

function pmEsc(v) {
  return String(v ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// Flagged people matching these contact details. `exclude` leaves out one
// student (the record being looked at). Resolves to [] on any failure.
async function flagCheckContact({ email, phone, first, last, exclude } = {}) {
  try {
    const { data, error } = await db.rpc('flag_check', {
      p_email: email || null, p_phone: phone || null,
      p_first: first || null, p_last: last || null, p_exclude: exclude || null,
    });
    if (error) throw error;
    return data ?? [];
  } catch (err) {
    console.warn('flag check unavailable:', err?.message ?? err);
    return [];
  }
}

// For list pages: { studentId: [ {level, reason, why, student_name, …} ] },
// where why === 'this record' is the student's own flag. {} on any failure.
async function flagCheckStudents(ids) {
  const out = {};
  const list = [...new Set((ids ?? []).filter(Boolean))];
  if (!list.length) return out;
  try {
    const { data, error } = await db.rpc('flag_check_students', { p_ids: list });
    if (error) throw error;
    (data ?? []).forEach(r => { (out[r.for_student_id] ??= []).push(r); });
  } catch (err) {
    console.warn('flag check unavailable:', err?.message ?? err);
  }
  return out;
}

// Small pill for a list row. `rows` is that student's entry from
// flagCheckStudents(): their own flag shows its level; a link to a flagged
// family member (same email/phone/name) shows "possible match".
function flagPill(rows) {
  if (!rows?.length) return '';
  const own = rows.find(r => r.why === 'this record');
  if (own) {
    const block = own.level === 'block';
    return `<span title="${pmEsc(FLAG_LEVEL_LABEL[own.level])}: ${pmEsc(own.reason)}"
      style="display:inline-block;margin-left:0.4rem;padding:0.05rem 0.45rem;border-radius:999px;font-size:0.68rem;font-weight:700;
             vertical-align:middle;background:${block ? '#fee2e2' : '#fef3c7'};color:${block ? '#b91c1c' : '#92400e'};
             border:1px solid ${block ? '#fca5a5' : '#fcd34d'};">🚩 ${pmEsc(FLAG_LEVEL_LABEL[own.level])}</span>`;
  }
  const worst = rows.some(r => r.level === 'block') ? 'block' : 'watch';
  const tip = rows.map(r => `${r.student_name}: ${FLAG_LEVEL_LABEL[r.level]} — ${r.reason} (${r.why})`).join('\n');
  return `<span title="${pmEsc(tip)}"
    style="display:inline-block;margin-left:0.4rem;padding:0.05rem 0.45rem;border-radius:999px;font-size:0.68rem;font-weight:700;
           vertical-align:middle;background:#fff;color:${worst === 'block' ? '#b91c1c' : '#92400e'};
           border:1px dashed ${worst === 'block' ? '#fca5a5' : '#fcd34d'};">🚩 Possible match</span>`;
}

// Red box for a lookup result (flag_check rows). `lead` is the first line.
function flagBanner(rows, lead) {
  if (!rows?.length) return '';
  const STATUS = { active: 'currently enrolled', trial: 'on a trial', inactive: 'past student',
                   lapsed: 'lapsed enquiry', prospective: 'enquiry' };
  const fmt = d => { try { return new Date(d).toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' }); } catch (_) { return ''; } };
  return `<div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:var(--r-sm);
              padding:0.7rem 0.85rem;margin-bottom:1rem;font-size:0.82rem;color:#991b1b;line-height:1.6;">
      <strong>🚩 ${pmEsc(lead ?? 'This person matches a flagged student.')}</strong>
      ${rows.map(r => `<div style="margin-top:0.35rem;">
        <strong>${pmEsc(r.student_name || '(unnamed)')}</strong>
        <span style="opacity:0.8;">(${pmEsc(r.studio_name ?? 'no studio')}, ${pmEsc(STATUS[r.student_status] ?? r.student_status)}
          — ${pmEsc(r.why)})</span><br>
        <strong>${pmEsc(FLAG_LEVEL_LABEL[r.level] ?? r.level)}</strong> · ${pmEsc(r.reason)}
        <span style="opacity:0.7;">· flagged ${pmEsc(fmt(r.flagged_at))}</span>
      </div>`).join('')}
    </div>`;
}
