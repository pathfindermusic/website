// ============================================================
// Teachers' billability — the sums behind teacher-billability.html.
// Pure functions (no page, no database), so they can be tested alone.
// Self-contained (its own small date helpers, exposed as PFBill.U).
//
// A teacher's billable hours for a day depend on their employment type:
//
//   full_time / part_time  The hours they are AVAILABLE that weekday, as set
//                          on their profile (all studios added together).
//   casual                 From the first billable lesson's start to the last
//                          billable lesson's end, gaps between included.
//                          A lesson is billable unless it is cancelled or
//                          EVERY student on it is marked Absent (no credit),
//                          Absent (notice given) or Teacher cancelled — so a
//                          lesson marked Present, or not marked yet, counts.
//                          A lesson taken over by a substitute counts for the
//                          substitute, not the usual teacher. And while a
//                          teacher's lesson is being covered by someone else
//                          they are away: that lesson splits the day into
//                          separate stretches, each billed first start to
//                          last end, so the time they were away is not billed.
//   not set                0 until an employment type is chosen.
//
// Hours are rounded to 2 decimal places.
// ============================================================
(function (root) {
  const pad = n => String(n).padStart(2, '0');
  const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const U = {
    esc: s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    // 'YYYY-MM-DD' → Date at local midnight (never via UTC, which shifts the day)
    parseISO: ds => { const [y, m, d] = ds.split('-').map(Number); return new Date(y, m - 1, d); },
    toISO: d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    fmtDMY: ds => { const [y, m, d] = ds.split('-'); return `${d}/${m}/${y}`; },
    toMins: t => { const [h, m] = String(t).split(':').map(Number); return h * 60 + (m || 0); },
  };
  U.dowOf = ds => DOW[U.parseISO(ds).getDay()];
  U.daysBetween = (a, b) => Math.round((U.parseISO(b) - U.parseISO(a)) / 86400000);
  const NO_SHOW = ['absent_no_credit', 'absent_notice', 'teacher_cancelled'];
  const B = { U };

  B.TYPES = {
    full_time: { label: 'Full-time', bg: '#dbeafe', fg: '#1d4ed8' },
    part_time: { label: 'Part-time', bg: '#dcfce7', fg: '#15803d' },
    casual:    { label: 'Casual',    bg: '#ffedd5', fg: '#c2410c' },
  };
  B.NOT_SET = { label: 'Not set', bg: '#f3f4f6', fg: '#6b7280' };
  B.typeInfo = t => B.TYPES[t] || B.NOT_SET;

  const r2 = x => Math.round(x * 100) / 100;
  B.hoursFromMins = mins => r2(mins / 60);

  // The fortnight that starts on the Wednesday of the current Monday–Sunday
  // week and ends on the Tuesday 13 days later (both inclusive).
  B.defaultPeriod = (today) => {
    const d = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const sinceMon = (d.getDay() + 6) % 7;            // Mon=0 … Sun=6
    d.setDate(d.getDate() - sinceMon + 2);            // that week's Wednesday
    const end = new Date(d); end.setDate(end.getDate() + 13);
    return { from: U.toISO(d), to: U.toISO(end) };
  };

  // every date from..to as 'YYYY-MM-DD'
  B.datesBetween = (from, to) => {
    const out = [], n = U.daysBetween(from, to);
    for (let i = 0; i <= n; i++) { const d = U.parseISO(from); d.setDate(d.getDate() + i); out.push(U.toISO(d)); }
    return out;
  };

  // Which lessons count for a casual teacher: not cancelled, not all-absent.
  B.countsForCasual = (occ, markCounts) => {
    if (occ.occurrence_status === 'cancelled') return false;
    const roster = Number(occ.student_count) || 0;
    const noShow = markCounts ? markCounts.noShow : 0;
    return !(roster > 0 && noShow >= roster);
  };

  // minutes between the first start and last end of the lessons given
  B.spanMins = lessons => {
    if (!lessons.length) return 0;
    const starts = lessons.map(l => U.toMins(l.start_time));
    const ends   = lessons.map(l => U.toMins(l.start_time) + (Number(l.duration_mins) || 0));
    return Math.max(0, Math.max(...ends) - Math.min(...starts));
  };

  // A casual teacher's minutes for a day: their own billable lessons, in
  // stretches. A lesson of theirs that someone else covered ("away") starts a
  // new stretch, so the time between the lesson before it and the lesson
  // after it is not billed. Each stretch counts first start to last end.
  B.splitSpanMins = (own, away = []) => {
    if (!own.length) return 0;
    const sorted = own.slice().sort((a, b) => U.toMins(a.start_time) - U.toMins(b.start_time));
    const cuts = away.map(a => U.toMins(a.start_time));
    let total = 0, group = [sorted[0]];
    for (let i = 1; i < sorted.length; i++) {
      const ps = U.toMins(sorted[i - 1].start_time), cs = U.toMins(sorted[i].start_time);
      if (cuts.some(c => c > ps && c < cs)) { total += B.spanMins(group); group = [sorted[i]]; }
      else group.push(sorted[i]);
    }
    return total + B.spanMins(group);
  };

  // minutes a teacher is available on a weekday (sum of their windows)
  B.availMins = (avail, dow) => avail
    .filter(a => a.day_of_week === dow)
    .reduce((s, a) => s + Math.max(0, U.toMins(a.end_time) - U.toMins(a.start_time)), 0);

  // teachers: [{id}]; types: { teacherId: 'full_time'|'part_time'|'casual'|null }
  // avail:   [{teacher_id, day_of_week, start_time, end_time}]
  // occs:    [{occurrence_id, teacher_id (who taught it), original_teacher_id (who it was
  //           booked with), date, occurrence_status, start_time, duration_mins, student_count}]
  // marks:   [{lesson_occurrence_id, status}]
  // → { cells: { teacherId: { date: hours } } }
  B.calculate = ({ from, to, teachers, types = {}, avail = [], occs = [], marks = [] }) => {
    const dates = B.datesBetween(from, to);
    const markBy = new Map();
    marks.forEach(m => {
      if (!m.status) return;
      const r = markBy.get(m.lesson_occurrence_id) ?? { noShow: 0 };
      if (NO_SHOW.includes(m.status)) r.noShow++;
      markBy.set(m.lesson_occurrence_id, r);
    });
    const availBy = new Map(), occBy = new Map(), awayBy = new Map();
    avail.forEach(a => { (availBy.get(a.teacher_id) ?? availBy.set(a.teacher_id, []).get(a.teacher_id)).push(a); });
    occs.forEach(o => {
      if (!B.countsForCasual(o, markBy.get(o.occurrence_id))) return;
      const k = o.teacher_id + '|' + o.date;
      (occBy.get(k) ?? occBy.set(k, []).get(k)).push(o);
      // taught by someone else: the usual teacher is away for it
      if (o.original_teacher_id && o.original_teacher_id !== o.teacher_id) {
        const k2 = o.original_teacher_id + '|' + o.date;
        (awayBy.get(k2) ?? awayBy.set(k2, []).get(k2)).push(o);
      }
    });

    const cells = {};
    teachers.forEach(t => {
      const type = types[t.id] || null;
      const row = (cells[t.id] = {});
      dates.forEach(date => {
        let mins = 0;
        if (type === 'full_time' || type === 'part_time') {
          mins = B.availMins(availBy.get(t.id) ?? [], U.parseISO(date).getDay());
        } else if (type === 'casual') {
          const key = t.id + '|' + date;
          mins = B.splitSpanMins(occBy.get(key) ?? [], awayBy.get(key) ?? []);
        }
        row[date] = B.hoursFromMins(mins);
      });
    });
    return { cells };
  };

  // Hours text: 4, 4.5, 3.75 (never "4.00")
  B.fmt = h => (h === null || h === undefined || h === '' || Number.isNaN(+h)) ? '' : String(+(+h).toFixed(2));

  // totals for a grid { teacherId: { date: hours } }
  B.totals = (cells, teacherIds, dates) => {
    const perTeacher = {}, perDate = {};
    let grand = 0;
    dates.forEach(d => { perDate[d] = 0; });
    teacherIds.forEach(id => {
      let s = 0;
      dates.forEach(d => { const v = +(cells[id]?.[d]) || 0; s += v; perDate[d] += v; });
      perTeacher[id] = r2(s); grand += s;
    });
    dates.forEach(d => { perDate[d] = r2(perDate[d]); });
    return { perTeacher, perDate, grand: r2(grand) };
  };

  B.toCSV = ({ from, to, rows, dates, cells, totals, notes }) => {
    const q = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const head = ['Teacher', 'Employment', ...dates.map(d => `${U.dowOf(d)} ${U.fmtDMY(d)}`), 'Total hours'];
    const lines = [
      ['Billable hours', `${U.fmtDMY(from)} to ${U.fmtDMY(to)} (inclusive)`],
      [],
      head,
      ...rows.map(r => [r.name, B.typeInfo(r.type).label, ...dates.map(d => B.fmt(cells[r.id]?.[d])), B.fmt(totals.perTeacher[r.id])]),
      ['Total', '', ...dates.map(d => B.fmt(totals.perDate[d])), B.fmt(totals.grand)],
    ];
    if (notes && notes.trim()) lines.push([], ['Notes', notes.trim()]);
    return lines.map(l => l.map(q).join(',')).join('\r\n');
  };

  root.PFBill = B;
  if (typeof module !== 'undefined' && module.exports) module.exports = B;
})(typeof window !== 'undefined' ? window : globalThis);
