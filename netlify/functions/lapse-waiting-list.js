// ============================================================
// PATHFINDER PORTAL — waiting list auto-lapse
//
// Runs nightly. A waiting-list entry (tasks.kind = 'waitlist',
// status = 'open') whose waitlisted_at is 3+ months old is treated
// the same way an admin choosing "Not proceeding" treats any other
// enquiry that didn't pan out: the student goes to status='lapsed'
// with an automatic lapsed_reason, the task closes, and a log entry
// records why — nothing about this is a silent change, it's the
// existing "Not proceeding" outcome, just reached automatically
// because nobody expects a family to still be waiting that long.
//
// Guarded on the student still being 'prospective' at the moment
// this runs — if an admin already moved them on (booked a trial,
// enrolled, or manually marked them lapsed) since they joined the
// waiting list, there is nothing left for this sweep to do, and it
// must not overwrite whatever that admin decided.
//
// INTERNAL ONLY. Nobody is emailed by this function.
// ============================================================

const SUPABASE_URL         = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

const LAPSE_AFTER_DAYS = 90; // "3 months" — see README for why a day count, not a calendar interval

exports.handler = async () => {
  const headers = {
    'Content-Type':  'application/json',
    'apikey':        SUPABASE_SERVICE_KEY,
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
  };
  const api = (path, opts = {}) =>
    fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers, ...opts });

  const cutoff = new Date(Date.now() - LAPSE_AFTER_DAYS * 24 * 60 * 60 * 1000).toISOString();

  try {
    const dueRes = await api(
      `tasks?kind=eq.waitlist&status=eq.open` +
      `&waitlisted_at=not.is.null&waitlisted_at=lte.${encodeURIComponent(cutoff)}` +
      `&subject_type=eq.student` +
      `&select=id,subject_id,waitlisted_at`);
    if (!dueRes.ok) throw new Error('fetch due entries: ' + await dueRes.text());
    const due = await dueRes.json();

    if (!due.length) {
      console.log('[lapse-waiting-list] nothing due');
      return ok({ due: 0, lapsed: 0, skipped: 0, failed: 0 });
    }

    const studentIds = [...new Set(due.map(t => t.subject_id))];
    const studRes = await api(`students?id=in.(${studentIds.join(',')})&select=id,status`);
    if (!studRes.ok) throw new Error('fetch students: ' + await studRes.text());
    const statusById = {};
    (await studRes.json()).forEach(s => { statusById[s.id] = s.status; });

    let lapsed = 0, skipped = 0, failed = 0;

    for (const t of due) {
      // Someone already moved this student on — leave their decision alone.
      if (statusById[t.subject_id] !== 'prospective') { skipped++; continue; }

      try {
        const sRes = await api(`students?id=eq.${t.subject_id}`, {
          method: 'PATCH',
          headers: { ...headers, Prefer: 'return=minimal' },
          body: JSON.stringify({
            status: 'lapsed',
            lapsed_reason: 'Waiting list entry expired after 3 months with no suitable availability found.',
          }),
        });
        if (!sRes.ok) throw new Error('students: ' + await sRes.text());

        const tRes = await api(`tasks?id=eq.${t.id}`, {
          method: 'PATCH',
          headers: { ...headers, Prefer: 'return=minimal' },
          body: JSON.stringify({
            status: 'done',
            completed_at: new Date().toISOString(),
            completed_by: null, // system, not an admin
          }),
        });
        if (!tRes.ok) throw new Error('tasks: ' + await tRes.text());

        const nRes = await api('task_notes', {
          method: 'POST',
          headers: { ...headers, Prefer: 'return=minimal' },
          body: JSON.stringify({
            task_id: t.id,
            note_text: 'Waiting list entry lapsed automatically after 3 months — no suitable availability found.',
          }),
        });
        if (!nRes.ok) throw new Error('task_notes: ' + await nRes.text());

        lapsed++;
      } catch (err) {
        failed++;
        console.error(`[lapse-waiting-list] task ${t.id}:`, err.message);
      }
    }

    console.log(`[lapse-waiting-list] ${due.length} due, ${lapsed} lapsed, ${skipped} already moved on, ${failed} failed`);
    return ok({ due: due.length, lapsed, skipped, failed });

  } catch (err) {
    console.error('[lapse-waiting-list] run failed:', err.message);
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};

function ok(payload) {
  return { statusCode: 200, body: JSON.stringify(payload) };
}
