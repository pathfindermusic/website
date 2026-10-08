// ============================================================
// Teachers utilisation — the sums behind teacher-utilisation.html.
// Pure functions (no page, no database), so they can be tested alone.
//
// Counting rules (agreed with the superuser):
//   * One lesson = one scheduled occurrence. A group lesson counts once,
//     with its length, however many students are in it.
//   * Booked   : every occurrence, including ones later cancelled.
//   * No-show  : the occurrence is cancelled, OR every student on its
//                roster is marked absent_no_credit / absent_notice /
//                teacher_cancelled.
//   * Taught   : booked less no-shows. A lesson not marked yet counts as
//                taught.
//   * Billable : at least one student marked present.
// ============================================================
(function (root) {
  const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const NO_SHOW = ['absent_no_credit', 'absent_notice', 'teacher_cancelled'];
  const pad = n => String(n).padStart(2, '0');
  const U = {};

  U.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // 'YYYY-MM-DD' → Date at local midnight (never via UTC, which shifts the day)
  U.parseISO = ds => { const [y, m, d] = ds.split('-').map(Number); return new Date(y, m - 1, d); };
  U.toISO = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  U.fmtDMY = ds => { const [y, m, d] = ds.split('-'); return `${d}/${m}/${y}`; };
  U.dowOf = ds => DOW[U.parseISO(ds).getDay()];
  U.daysBetween = (a, b) => Math.round((U.parseISO(b) - U.parseISO(a)) / 86400000);

  // The last complete Wednesday-to-Tuesday fortnight: it ends on the most
  // recent Tuesday BEFORE today and starts 13 days earlier (a Wednesday).
  U.defaultPeriod = (today) => {
    const d = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    d.setDate(d.getDate() - 1);
    while (d.getDay() !== 2) d.setDate(d.getDate() - 1);
    const end = new Date(d);
    const start = new Date(d); start.setDate(start.getDate() - 13);
    return { from: U.toISO(start), to: U.toISO(end) };
  };

  // 'HH:MM[:SS]' → minutes; and → '09:00 AM'
  U.toMins = t => { const [h, m] = String(t).split(':').map(Number); return h * 60 + (m || 0); };
  U.fmtClock = t => {
    const mins = U.toMins(t), h24 = Math.floor(mins / 60), m = mins % 60;
    return `${pad(h24 % 12 === 0 ? 12 : h24 % 12)}:${pad(m)} ${h24 < 12 ? 'AM' : 'PM'}`;
  };
  U.hrs = mins => `${+(mins / 60).toFixed(2)} Hrs`;
  U.pct = (n, d) => d > 0 ? `${Math.round((n / d) * 100)}%` : null;

  const blank = () => ({ availRanges: [], availMins: 0, bookedN: 0, bookedMin: 0, taughtN: 0, taughtMin: 0, billN: 0, billMin: 0 });

  U.buildModel = ({ from, to, avail = [], occs = [], marks = [] }) => {
    const cols = new Map();
    const col = (date, studioId, studioName) => {
      const key = `${date}|${studioId}`;
      if (!cols.has(key)) cols.set(key, { key, date, dow: U.dowOf(date), studioId, studioName: studioName || '(studio)', ...blank() });
      else if (studioName && cols.get(key).studioName === '(studio)') cols.get(key).studioName = studioName;
      return cols.get(key);
    };

    // availability: every date in the period whose weekday matches
    const n = U.daysBetween(from, to);
    for (let i = 0; i <= n; i++) {
      const d = U.parseISO(from); d.setDate(d.getDate() + i);
      const ds = U.toISO(d), dw = d.getDay();
      avail.filter(a => a.day_of_week === dw).forEach(a => {
        const c = col(ds, a.studio_id, a.studios?.name);
        const mins = Math.max(0, U.toMins(a.end_time) - U.toMins(a.start_time));
        c.availRanges.push({ start: a.start_time, end: a.end_time, mins });
        c.availMins += mins;
      });
    }
    cols.forEach(c => c.availRanges.sort((x, y) => U.toMins(x.start) - U.toMins(y.start)));

    // attendance marks per occurrence
    const byOcc = new Map();
    marks.forEach(m => {
      if (!m.status) return;                       // a row with no status is "not marked"
      const r = byOcc.get(m.lesson_occurrence_id) ?? { present: 0, noShow: 0, marked: 0 };
      r.marked++;
      if (m.status === 'present') r.present++;
      else if (NO_SHOW.includes(m.status)) r.noShow++;
      byOcc.set(m.lesson_occurrence_id, r);
    });

    let unmarked = 0;
    occs.forEach(o => {
      const c = col(o.date, o.studio_id, o.studio_name);
      const mins = Number(o.duration_mins) || 0;
      const roster = Number(o.student_count) || 0;
      const r = byOcc.get(o.occurrence_id) ?? { present: 0, noShow: 0, marked: 0 };
      const cancelled = o.occurrence_status === 'cancelled';
      const noShow = cancelled || (roster > 0 && r.noShow >= roster);
      const billable = !cancelled && r.present >= 1;
      c.bookedN++; c.bookedMin += mins;
      if (!noShow) { c.taughtN++; c.taughtMin += mins; }
      if (billable) { c.billN++; c.billMin += mins; }
      if (!cancelled && r.marked < Math.max(roster, 1)) unmarked++;
    });

    const columns = [...cols.values()].sort((a, b) =>
      a.date.localeCompare(b.date) || a.studioName.localeCompare(b.studioName));
    const total = { ...blank(), isTotal: true };
    columns.forEach(c => ['availMins', 'bookedN', 'bookedMin', 'taughtN', 'taughtMin', 'billN', 'billMin']
      .forEach(k => { total[k] += c[k]; }));
    return { from, to, columns, total, unmarked };
  };

  // ---- cell text (HTML) ----
  const NIL = '<span class="nil">—</span>';
  U.cellAvail = c => {
    if (c.isTotal) return c.availMins ? U.hrs(c.availMins) : NIL;
    if (!c.availRanges.length) return NIL;
    return c.availRanges.map(r => `${U.fmtClock(r.start)}-${U.fmtClock(r.end)} (${U.hrs(r.mins)})`).join('<br>');
  };
  U.cellBooked = c => c.bookedN ? `${c.bookedN} (${U.hrs(c.bookedMin)})` : '0';
  U.cellShare = (c, kind) => {
    if (!c.bookedN) return NIL;
    const n = kind === 'taught' ? c.taughtN : c.billN;
    const m = kind === 'taught' ? c.taughtMin : c.billMin;
    return `${n} (${U.pct(n, c.bookedN)})<div class="l2">${U.hrs(m)} (${U.pct(m, c.bookedMin) ?? '0%'})</div>`;
  };

  // ---- CSV: plain numbers, one metric per row, so it sorts/sums in a spreadsheet ----
  U.toCSV = (m, teacherName) => {
    const colTitle = c => `${c.dow} ${U.fmtDMY(c.date)} (${c.studioName})`;
    const h = x => +(x / 60).toFixed(2);
    const p = (n, d) => d > 0 ? Math.round((n / d) * 100) : '';
    const all = [...m.columns, m.total];
    const row = (label, fn) => [label, ...all.map(fn)];
    const rows = [
      ['Teacher', teacherName],
      ['Period (inclusive)', `${U.fmtDMY(m.from)} to ${U.fmtDMY(m.to)}`],
      [],
      ['', ...m.columns.map(colTitle), 'Total'],
      row('Availability', c => c.isTotal ? '' : c.availRanges.map(r => `${U.fmtClock(r.start)}-${U.fmtClock(r.end)}`).join('; ')),
      row('Availability (Hrs)', c => h(c.availMins)),
      row('Lessons booked', c => c.bookedN),
      row('Lessons booked (Hrs)', c => h(c.bookedMin)),
      row('Lessons taught', c => c.taughtN),
      row('Lessons taught (% of booked)', c => p(c.taughtN, c.bookedN)),
      row('Taught time (Hrs)', c => h(c.taughtMin)),
      row('Taught time (% of booked time)', c => p(c.taughtMin, c.bookedMin)),
      row('Billable lessons', c => c.billN),
      row('Billable lessons (% of booked)', c => p(c.billN, c.bookedN)),
      row('Billable time (Hrs)', c => h(c.billMin)),
      row('Billable time (% of booked time)', c => p(c.billMin, c.bookedMin)),
    ];
    return rows.map(r => r.map(v => `"${String(v ?? '').replace(/"/g, '""')}"`).join(',')).join('\r\n');
  };

  root.PFUtil = U;
  if (typeof module !== 'undefined' && module.exports) module.exports = U;
})(typeof window !== 'undefined' ? window : globalThis);
