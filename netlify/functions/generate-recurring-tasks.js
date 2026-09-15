// ============================================================
// PATHFINDER PORTAL — recurring task generation
//
// Runs each morning and turns any recurring-task rule that is due
// today into an actual task, the same way an admin would create one
// by hand — a rule doesn't sit on the calendar in advance, it just
// appears the morning it's due.
//
// Scheduled from netlify.toml. Melbourne "today" is computed the
// same way send-lesson-reminders.js does it, for the same reason:
// Netlify cron only understands UTC, and the server's own date is
// already wrong by the time this fires in the evening UTC.
//
// A rule with no attached students/teachers generates one generic
// task. A rule with one or more attached subjects generates one
// task PER subject (the admin's chosen design — a shared task
// listing five students reads worse than five separate ones).
//
// Idempotent: recurring_task_runs is checked before every insert,
// so a rule already generated for today (this function fired twice,
// or was re-run by hand) is never duplicated.
//
// INTERNAL ONLY. Nobody is emailed by this function — it only
// creates rows in `tasks`, which show up in the portal like any
// other task.
// ============================================================

const SUPABASE_URL         = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

const NIL_SUBJECT = '00000000-0000-0000-0000-000000000000';

// ------------------------------------------------------------
// ruleFiresOn(rule, dateObj) — pure function, no I/O.
//
// A COPY of this function lives in portal/tasks.html, for the
// rule-editor's "next occurrence" preview — there is no shared
// module mechanism between the static portal and Netlify Functions
// in this codebase. Keep the two in sync; a change here needs the
// same change there.
//
// dateObj is a plain local-midnight Date (as parseLocalDate/
// toISODate already produce elsewhere in this codebase) — never a
// UTC-parsed one, or the weekday/day-of-month math drifts by a day
// near midnight.
// ------------------------------------------------------------
function ruleFiresOn(rule, dateObj) {
  const d   = dateObj.getDate();
  const dow = dateObj.getDay();               // 0=Sunday .. 6=Saturday
  const lastDayOfMonth =
    new Date(dateObj.getFullYear(), dateObj.getMonth() + 1, 0).getDate();

  switch (rule.recurrence_type) {
    case 'daily':
      return true;

    case 'weekly':
      return dow === rule.weekday;

    case 'monthly_day':
      if (rule.day_of_month === -1) return d === lastDayOfMonth;
      // A day beyond this month's length (e.g. 31 in February) falls
      // back to the month's last day, so the rule still fires once.
      return d === rule.day_of_month || (rule.day_of_month > lastDayOfMonth && d === lastDayOfMonth);

    case 'monthly_weekday': {
      if (dow !== rule.weekday) return false;
      const nth = Math.ceil(d / 7);            // which occurrence of this weekday
      if (rule.week_of_month === -1) return d + 7 > lastDayOfMonth; // the last one this month
      return nth === rule.week_of_month;
    }

    default:
      return false;
  }
}

exports.handler = async () => {
  // What is today in Melbourne? Built the same way parseLocalDate
  // elsewhere in the portal would — a local-midnight Date, not one
  // parsed as UTC — so ruleFiresOn's day-of-week/day-of-month math
  // matches what an admin sees on screen.
  const todayISO = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Australia/Melbourne',
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date());
  const [ty, tm, td] = todayISO.split('-').map(Number);
  const today = new Date(ty, tm - 1, td);

  console.log(`[recurring-tasks] ${todayISO} in Melbourne`);

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
  const post = async (path, body, extraHeaders = {}) => {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
      method: 'POST',
      headers: { ...headers, ...extraHeaders },
      body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(`${path}: ${await r.text()}`);
    return extraHeaders.Prefer?.includes('return=representation') ? r.json() : null;
  };

  try {
    const rules = await get('recurring_tasks?is_active=is.true&select=*');
    const due   = rules.filter(r => ruleFiresOn(r, today));

    if (!due.length) {
      console.log('[recurring-tasks] no rules due today');
      return ok({ date: todayISO, rules: rules.length, due: 0, created: 0 });
    }

    const ruleIds = due.map(r => r.id);

    // Every subject attached to a due rule, in one round trip
    const subjects = await get(
      `recurring_task_subjects?recurring_task_id=in.(${ruleIds.join(',')})` +
      `&select=recurring_task_id,subject_type,subject_id`);

    // Filter out subjects who are no longer active — a rule outlives
    // the people it was set up for, and a lapsed student shouldn't
    // keep generating tasks.
    const studentIds = [...new Set(subjects.filter(s => s.subject_type === 'student').map(s => s.subject_id))];
    const teacherIds = [...new Set(subjects.filter(s => s.subject_type === 'teacher').map(s => s.subject_id))];

    const activeStudentIds = new Set();
    if (studentIds.length) {
      const rows = await get(`students?id=in.(${studentIds.join(',')})&select=id,status`);
      rows.filter(s => ['active', 'trial'].includes(s.status)).forEach(s => activeStudentIds.add(s.id));
    }

    const activeTeacherIds = new Set();
    if (teacherIds.length) {
      const rows = await get(`teachers?id=in.(${teacherIds.join(',')})&select=id,user_id`);
      const userIds = rows.map(t => t.user_id).filter(Boolean);
      const profiles = userIds.length
        ? await get(`profiles?id=in.(${userIds.join(',')})&select=id,status`)
        : [];
      const statusByUser = {};
      profiles.forEach(p => { statusByUser[p.id] = p.status; });
      rows.filter(t => statusByUser[t.user_id] !== 'inactive').forEach(t => activeTeacherIds.add(t.id));
    }

    const isActiveSubject = s =>
      s.subject_type === 'student' ? activeStudentIds.has(s.subject_id) : activeTeacherIds.has(s.subject_id);

    // Already generated today? Checked once, up front, rather than
    // per-insert — cheaper, and avoids a race between the check and
    // the write if this ever runs concurrently with itself.
    const already = await get(
      `recurring_task_runs?recurring_task_id=in.(${ruleIds.join(',')})&run_date=eq.${todayISO}` +
      `&select=recurring_task_id,subject_type,subject_id`);
    const ranKey = new Set(already.map(r => `${r.recurring_task_id}:${r.subject_type}:${r.subject_id}`));

    const subjectsByRule = {};
    subjects.forEach(s => {
      (subjectsByRule[s.recurring_task_id] ??= []).push(s);
    });

    let created = 0, skippedInactive = 0, skippedAlready = 0, failed = 0;

    for (const rule of due) {
      const ruleSubjects = subjectsByRule[rule.id] ?? [];

      // No subjects attached — one generic task, keyed by the sentinel
      // 'none'/nil-uuid pair (NULLs are never equal in a UNIQUE
      // constraint, so a real NULL pair here would never block a
      // duplicate on the next run).
      const fanOut = ruleSubjects.length
        ? ruleSubjects
        : [{ subject_type: 'none', subject_id: NIL_SUBJECT }];

      for (const subj of fanOut) {
        const isGeneric = subj.subject_type === 'none';

        if (!isGeneric && !isActiveSubject(subj)) { skippedInactive++; continue; }

        const key = `${rule.id}:${subj.subject_type}:${subj.subject_id}`;
        if (ranKey.has(key)) { skippedAlready++; continue; }

        try {
          const [insertedTask] = await post('tasks', {
            title:             rule.title,
            subject_type:      isGeneric ? null : subj.subject_type,
            subject_id:        isGeneric ? null : subj.subject_id,
            studio_id:         rule.studio_id,
            assigned_to:       rule.assigned_to,
            due_date:          todayISO,
            source:            'recurring',
            recurring_task_id: rule.id,
          }, { Prefer: 'return=representation' });

          await post('recurring_task_runs', {
            recurring_task_id: rule.id,
            run_date:           todayISO,
            subject_type:       subj.subject_type,
            subject_id:         subj.subject_id,
            task_id:            insertedTask?.id ?? null,
          }, { Prefer: 'return=minimal' });

          created++;
        } catch (err) {
          failed++;
          console.error(`[recurring-tasks] rule ${rule.id} (${rule.title}):`, err.message);
        }
      }
    }

    console.log(`[recurring-tasks] ${due.length} rule(s) due, ${created} created, ` +
      `${skippedAlready} already run, ${skippedInactive} inactive subjects skipped, ${failed} failed`);
    return ok({ date: todayISO, rules: rules.length, due: due.length, created, skippedAlready, skippedInactive, failed });

  } catch (err) {
    console.error('[recurring-tasks] run failed:', err.message);
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};

function ok(payload) {
  return { statusCode: 200, body: JSON.stringify(payload) };
}
