// ============================================================
// PATHFINDER PORTAL — Events: shared code
//
// Used by events.html (admins + teachers) and event-book.html
// (students). Three jobs:
//   1. Block / slot / time maths (pure functions — unit tested)
//   2. The performance grid renderer
//   3. The booking form (one component, so a student booking and an
//      admin "add a performance" can never drift apart)
//
// The database (supabase/events.sql) is the authority on capacity and
// on who may see what. Nothing here is trusted for either — it only
// makes the rules easy to follow.
// ============================================================
(function (root) {
  'use strict';
  const PF = {};

  // ---------- small helpers ----------
  PF.esc = s => String(s ?? '').replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  PF.ACCOMP = {
    teacher:       'My teacher',
    peer:          'A peer',
    backing_track: 'Backing track',
    none:          'No accompaniment',
  };

  // ---------- time and block maths ----------
  PF.toMins = hhmm => {
    const [h, m] = String(hhmm).split(':');
    return (parseInt(h, 10) || 0) * 60 + (parseInt(m, 10) || 0);
  };

  PF.fromMins = n => `${String(Math.floor(n / 60)).padStart(2, '0')}:${String(n % 60).padStart(2, '0')}`;

  /** 845 -> "2:05 pm" style, with the am/pm */
  PF.clock = mins => {
    const h24 = Math.floor(mins / 60) % 24, m = mins % 60;
    const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
    return `${h12}:${String(m).padStart(2, '0')} ${h24 < 12 ? 'am' : 'pm'}`;
  };

  /** Number of blocks: ceil((end - start) / block length), at least 1 */
  PF.blockCount = (start, end, blockMinutes) =>
    Math.max(1, Math.ceil((PF.toMins(end) - PF.toMins(start)) / blockMinutes));

  /** {start, end} in minutes since midnight for block b (1-based); the last block is cut at the event end */
  PF.blockRange = (ev, b) => {
    const s = PF.toMins(ev.start_time) + (b - 1) * ev.block_minutes;
    return { start: s, end: Math.min(s + ev.block_minutes, PF.toMins(ev.end_time)) };
  };

  /** "2:00 – 3:00 pm" (the am/pm is shown once when both ends share it) */
  PF.blockTimes = (ev, b) => {
    const r = PF.blockRange(ev, b);
    const a = PF.clock(r.start), z = PF.clock(r.end);
    return a.slice(-2) === z.slice(-2) ? `${a.slice(0, -3)} – ${z}` : `${a} – ${z}`;
  };

  /** Approximate start of slot p within block b, as minutes since midnight */
  PF.slotMinute = (ev, b, p) =>
    PF.blockRange(ev, b).start + Math.round((p - 1) * ev.block_minutes / ev.slots_per_block);

  PF.capacity = ev => PF.blockCount(ev.start_time, ev.end_time, ev.block_minutes) * ev.slots_per_block;

  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  /** '2026-12-12' -> Saturday 12 December 2026 (no timezone surprises: date parts only) */
  PF.fmtDate = (ds, short) => {
    if (!ds) return '';
    const [y, m, d] = String(ds).slice(0, 10).split('-').map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d));
    const wd = DAYS[dt.getUTCDay()];
    return short
      ? `${wd.slice(0, 3)} ${d} ${MONTHS[m - 1].slice(0, 3)} ${y}`
      : `${wd} ${d} ${MONTHS[m - 1]} ${y}`;
  };

  PF.timeRange = ev => `${PF.clock(PF.toMins(ev.start_time))} – ${PF.clock(PF.toMins(ev.end_time))}`;

  /**
   * Per-block occupancy: [{block, capacity, taken, free, full}] (index 0 = block 1).
   * excludeId leaves one booking out — the one being edited — so its own
   * seat counts as free to its owner.
   */
  PF.blockStats = (ev, bookings, excludeId) => {
    const n = PF.blockCount(ev.start_time, ev.end_time, ev.block_minutes);
    const out = [];
    for (let b = 1; b <= n; b++) out.push({ block: b, capacity: ev.slots_per_block, taken: 0 });
    (bookings ?? []).forEach(k => {
      if (k.id === excludeId) return;
      const s = out[k.block - 1];
      if (s) s.taken++;
    });
    out.forEach(s => { s.free = Math.max(0, s.capacity - s.taken); s.full = s.free === 0; });
    return out;
  };

  /** The link admins share. Relative to wherever the portal is hosted. */
  PF.shareUrl = (eventId, base) => {
    const u = new URL('event-book.html', base ?? (root.location ? root.location.href : 'https://example.invalid/portal/'));
    u.search = '';
    u.hash = '';
    u.searchParams.set('event', eventId);
    return u.href;
  };

  /** Database error codes -> sentences a parent can act on */
  PF.errorText = raw => {
    const code = String(raw?.message ?? raw ?? '').split(':')[0].trim();
    return ({
      none_available:   'Sorry — every block you chose has just filled up. Please choose different blocks (the list has been refreshed).',
      event_closed:     'Bookings for this event are closed. Please contact the studio.',
      deadline_passed:  'The booking deadline has passed. Please contact the studio.',
      limit_reached:    'This student already has the most performances allowed for this event. Edit or cancel an existing booking instead.',
      instrument_booked:'This student already has a performance booked for that instrument. Edit or cancel it, or choose a different instrument (for example Band).',
      bad_preferences:  'Please choose between one and three different blocks.',
      bad_input:        'Please check the form — something is missing or too long.',
      not_allowed:      "You don't have access to do that.",
      not_found:        'That booking no longer exists.',
      slot_taken:       'That slot is already taken.',
      bad_slot:         'That slot does not exist in this event.',
      layout_conflict:  'Some performances are already booked outside the new blocks or slots. Move or cancel them first, then change the layout.',
    })[code] ?? (String(raw?.message ?? raw ?? 'Something went wrong.'));
  };

  /** Call submit_event_booking with the form's values */
  PF.submitBooking = async (db, eventId, v, bookingId) => {
    const { data, error } = await db.rpc('submit_event_booking', {
      p_event: eventId,
      p_student: v.student_id,
      p_instrument: v.instrument,
      p_teacher_id: v.teacher_id || null,
      p_teacher_name: v.teacher_name || null,
      p_piece: v.piece,
      p_accompaniment: v.accompaniment,
      p_accompanist_name: v.accompanist_name || null,
      p_preferred: v.preferred_blocks,
      p_notes: v.notes || null,
      p_booking_id: bookingId || null,
    });
    if (error) { const e = new Error(error.message); e.code = String(error.message).split(':')[0].trim(); throw e; }
    return data;
  };

  /** Runs fn now and then every ms while the tab is visible; returns stop() */
  PF.poll = (fn, ms) => {
    let running = false, stopped = false;
    const tick = async () => {
      if (stopped || running || (root.document && root.document.hidden)) return;
      running = true;
      try { await fn(); } catch (e) { console.warn('[events] refresh failed', e); }
      running = false;
    };
    const timer = setInterval(tick, ms ?? 12000);
    const onVis = () => { if (!root.document.hidden) tick(); };
    if (root.document) root.document.addEventListener('visibilitychange', onVis);
    return () => {
      stopped = true; clearInterval(timer);
      if (root.document) root.document.removeEventListener('visibilitychange', onVis);
    };
  };

  // ---------- styles (injected once, so pages need no extra CSS file) ----------
  PF.injectStyles = () => {
    const d = root.document;
    if (!d || d.getElementById('ev-styles')) return;
    const st = d.createElement('style');
    st.id = 'ev-styles';
    st.textContent = `
    .ev-pill{display:inline-block;font-size:.68rem;font-weight:700;letter-spacing:.03em;text-transform:uppercase;padding:.14rem .5rem;border-radius:99px}
    .ev-pill.draft{background:#f3f4f6;color:#6b7280}.ev-pill.open{background:#dcfce7;color:#15803d}.ev-pill.closed{background:#fee2e2;color:#b91c1c}
    .ev-head{display:flex;flex-wrap:wrap;gap:.4rem 1.4rem;align-items:center;margin-bottom:.9rem;font-size:.85rem;color:var(--dark-grey)}
    .ev-head b{color:var(--charcoal)}
    .ev-head a{color:var(--orange);text-decoration:none}.ev-head a:hover{text-decoration:underline}
    .ev-legend{display:flex;flex-wrap:wrap;gap:.9rem;font-size:.74rem;color:var(--mid-grey);margin:.2rem 0 .9rem}
    .ev-legend i{display:inline-block;width:.8rem;height:.8rem;border-radius:3px;vertical-align:-1px;margin-right:.3rem;border:1.5px solid var(--light-grey);background:#fff}
    .ev-legend i.own{border-color:var(--orange);background:rgba(232,73,30,.12)}
    .ev-legend i.free{border-style:dashed}
    .ev-block{background:#fff;border:1px solid var(--border);border-radius:var(--r);margin-bottom:.9rem;box-shadow:var(--shadow);break-inside:avoid}
    .ev-block-head{display:flex;flex-wrap:wrap;align-items:center;gap:.4rem 1rem;padding:.65rem .9rem;border-bottom:1px solid var(--border);background:var(--off-white);border-radius:var(--r) var(--r) 0 0}
    .ev-block-title{font-weight:700;color:var(--charcoal);font-size:.9rem}
    .ev-block-time{font-size:.82rem;color:var(--dark-grey)}
    .ev-meter{flex:1;min-width:80px;max-width:220px;height:6px;background:var(--light-grey);border-radius:99px;overflow:hidden}
    .ev-meter>span{display:block;height:100%;background:var(--orange);border-radius:99px}
    .ev-count{font-size:.78rem;color:var(--dark-grey);font-weight:600;margin-left:auto}
    .ev-count.full{color:#b91c1c}
    .ev-slots{display:grid;grid-template-columns:repeat(auto-fill,minmax(172px,1fr));gap:.55rem;padding:.8rem .9rem}
    .ev-slot{font:inherit;text-align:left;display:flex;flex-direction:column;gap:.12rem;min-height:74px;padding:.45rem .6rem;border-radius:var(--r-sm);border:1.5px solid var(--light-grey);background:#fff;color:var(--charcoal);position:relative}
    button.ev-slot{cursor:pointer}button.ev-slot:hover{border-color:var(--orange);box-shadow:var(--shadow)}
    .ev-slot.own{border-color:var(--orange);background:rgba(232,73,30,.08)}
    .ev-slot.empty{border-style:dashed;background:transparent;color:var(--mid-grey);justify-content:center;align-items:center;font-size:.78rem}
    .ev-slot.empty .ev-slot-no{position:absolute;top:.35rem;left:.5rem}
    .ev-slot-no{font-size:.66rem;font-weight:700;color:var(--mid-grey);letter-spacing:.02em}
    .ev-slot.own .ev-slot-no{color:var(--orange-dark)}
    .ev-slot-name{font-weight:700;font-size:.84rem;line-height:1.2;padding-right:.2rem}
    .ev-slot-what{font-size:.76rem;color:var(--dark-grey);line-height:1.3;word-break:break-word}
    .ev-slot-acc{font-size:.7rem;color:var(--mid-grey)}
    .ev-slot-me{position:absolute;top:.3rem;right:.4rem;font-size:.6rem;font-weight:800;color:var(--orange-dark);text-transform:uppercase;letter-spacing:.04em}
    .ev-form .form-group{margin-bottom:.85rem}
    .ev-form fieldset{border:none;padding:0;margin:0 0 .85rem}
    .ev-form legend{font-size:.8rem;font-weight:600;color:var(--charcoal);margin-bottom:.35rem}
    .ev-radio{display:flex;align-items:center;gap:.5rem;font-size:.86rem;padding:.2rem 0;cursor:pointer}
    .ev-radio input{accent-color:var(--orange)}
    .ev-form-error{background:#fee2e2;border:1px solid #fca5a5;color:#b91c1c;border-radius:var(--r-sm);padding:.55rem .75rem;font-size:.8rem;margin-bottom:.8rem}
    .ev-form-ok{background:#dcfce7;border:1px solid #86efac;color:#166534;border-radius:var(--r-sm);padding:.65rem .8rem;font-size:.85rem;margin-bottom:.8rem}
    .ev-choice-row{display:grid;grid-template-columns:1fr;gap:.5rem}
    .ev-skel{height:90px;border-radius:var(--r);background:linear-gradient(90deg,#f3f4f6,#fafafa,#f3f4f6);margin-bottom:.8rem}
    @media (max-width:540px){.ev-slots{grid-template-columns:repeat(auto-fill,minmax(140px,1fr))}}
    @media print{
      .topnav,.sidebar,.no-print,.toast-wrap,.modal-overlay{display:none!important}
      .main{margin:0!important;padding:0!important;width:100%!important;max-width:none!important}
      .portal-shell{display:block!important}
      .ev-block{box-shadow:none;border-color:#999}
      .ev-slot{border-color:#999!important;background:#fff!important}
      button.ev-slot{cursor:default}
      body{background:#fff!important}
    }`;
    d.head.appendChild(st);
  };

  // ---------- the grid ----------
  /**
   * Draws the blocks and slots.
   *   data  = get_event_grid() result: {event, bookings, role}
   *   opts  = { onFilled(booking), onEmpty(block, position), clickEmpty (bool) }
   * Re-rendering is skipped if nothing changed, so polling never flickers
   * or steals focus.
   */
  PF.renderGrid = (container, data, opts) => {
    opts = opts || {};
    const ev = data.event;
    const sig = JSON.stringify([ev.id, ev.status, ev.block_minutes, ev.slots_per_block, ev.start_time, ev.end_time, !!opts.clickEmpty,
      (data.bookings ?? []).map(b => [b.id, b.block, b.position, b.student_name, b.instrument, b.piece, b.accompaniment, b.own, b.detail, b.accompanist_name, b.teacher_name, b.notes])]);
    if (container._evSig === sig) return false;
    container._evSig = sig;

    const stats = PF.blockStats(ev, data.bookings);
    const at = new Map();
    (data.bookings ?? []).forEach(b => at.set(b.block + ':' + b.position, b));

    let html = '';
    stats.forEach(s => {
      const pct = Math.round(100 * s.taken / s.capacity);
      let cells = '';
      for (let p = 1; p <= ev.slots_per_block; p++) {
        const b = at.get(s.block + ':' + p);
        const t = PF.clock(PF.slotMinute(ev, s.block, p));
        if (b) {
          const acc = b.accompaniment === 'peer'
            ? (b.accompanist_name ? 'with ' + PF.esc(b.accompanist_name) : 'with a peer')
            : b.accompaniment === 'teacher' ? 'with teacher'
            : b.accompaniment === 'backing_track' ? 'backing track' : '';
          const clickable = !!opts.onFilled && (!opts.canClick || opts.canClick(b));
          const tag = clickable ? 'button type="button"' : 'div';
          const end = clickable ? 'button' : 'div';
          cells += `<${tag} class="ev-slot filled ${b.own ? 'own' : ''}" data-id="${PF.esc(b.id)}">
            <span class="ev-slot-no">#${p} · ~${t}</span>
            ${b.own && !opts.hideMine ? '<span class="ev-slot-me">' + (opts.mineLabel ?? 'You') + '</span>' : ''}
            <span class="ev-slot-name">${PF.esc(b.student_name)}</span>
            <span class="ev-slot-what">${PF.esc(b.instrument)} — ${PF.esc(b.piece)}</span>
            ${acc ? `<span class="ev-slot-acc">${acc}</span>` : ''}
          </${end}>`;
        } else if (opts.clickEmpty && opts.onEmpty) {
          cells += `<button type="button" class="ev-slot empty" data-block="${s.block}" data-pos="${p}">
            <span class="ev-slot-no">#${p} · ~${t}</span>＋ Add</button>`;
        } else {
          cells += `<div class="ev-slot empty"><span class="ev-slot-no">#${p} · ~${t}</span>Free</div>`;
        }
      }
      html += `<section class="ev-block" data-block="${s.block}">
        <div class="ev-block-head">
          <span class="ev-block-title">Block ${s.block}</span>
          <span class="ev-block-time">${PF.blockTimes(ev, s.block)}</span>
          <span class="ev-meter"><span style="width:${pct}%"></span></span>
          <span class="ev-count ${s.full ? 'full' : ''}">${s.taken} of ${s.capacity} booked${s.full ? ' · full' : ''}</span>
        </div>
        <div class="ev-slots">${cells}</div>
      </section>`;
    });
    container.innerHTML = html;

    container.onclick = e => {
      const f = e.target.closest('.ev-slot.filled');
      if (f && f.tagName === 'BUTTON' && opts.onFilled) {
        const bk = (data.bookings ?? []).find(x => x.id === f.dataset.id);
        if (bk) opts.onFilled(bk);
        return;
      }
      const em = e.target.closest('.ev-slot.empty[data-block]');
      if (em && opts.onEmpty) opts.onEmpty(Number(em.dataset.block), Number(em.dataset.pos));
    };
    return true;
  };

  /** Event facts as a compact header strip */
  PF.eventHeaderHtml = ev => {
    const nb = PF.blockCount(ev.start_time, ev.end_time, ev.block_minutes);
    const venue = ev.venue_name || ev.venue_address
      ? `<span>📍 <b>${PF.esc(ev.venue_name ?? '')}</b>${ev.venue_name && ev.venue_address ? ', ' : ''}${ev.venue_address
          ? `<a href="https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(ev.venue_address)}" target="_blank" rel="noopener">${PF.esc(ev.venue_address)}</a>` : ''}</span>`
      : '';
    return `<div class="ev-head">
      <span class="ev-pill ${PF.esc(ev.status)}">${PF.esc(ev.status)}</span>
      <span>📅 <b>${PF.fmtDate(ev.event_date)}</b>, ${PF.timeRange(ev)}</span>
      ${venue}
      <span>🎼 ${nb} block${nb === 1 ? '' : 's'} of ${ev.block_minutes} min · ${ev.slots_per_block} performances per block</span>
      ${ev.booking_deadline ? `<span>⏳ Book by <b>${PF.fmtDate(ev.booking_deadline, true)}</b></span>` : ''}
    </div>
    ${ev.description ? `<p style="font-size:.86rem;color:var(--dark-grey);margin-bottom:.9rem;white-space:pre-line">${PF.esc(ev.description)}</p>` : ''}`;
  };

  // ---------- the booking form ----------
  /**
   * cfg = {
   *   mount, event, bookings, students:[{id,name}], isAdmin, existing (booking|null),
   *   loadOptions(studentId) -> get_event_form_options result,
   *   onSubmit(values) -> Promise,  onDone(result), onCancel(),
   *   submitLabel
   * }
   * returns { setBookings(bookings), destroy() }
   */
  PF.bookingForm = cfg => {
    const d = root.document;
    const ev = cfg.event;
    const ex = cfg.existing || null;
    let bookings = cfg.bookings ?? [];
    let opts = { instruments: [], teachers: [], all_teachers: [] };
    let busy = false;

    const wrap = d.createElement('div');
    wrap.className = 'ev-form';
    const single = (cfg.students ?? []).length === 1 && !cfg.isAdmin;
    const accGroup = 'acc-' + Math.random().toString(36).slice(2, 8);
    wrap.innerHTML = `
      <div class="ev-msg"></div>
      <div class="form-group" data-f="studentWrap">
        <label class="form-label">Who is performing?</label>
        ${cfg.isAdmin ? '<input class="form-input" data-f="studentFilter" placeholder="Type to search students…" autocomplete="off" style="margin-bottom:.4rem">' : ''}
        <select class="form-select" data-f="student" ${ex ? 'disabled' : ''}></select>
      </div>
      <div class="form-row">
        <div class="form-group">
          <label class="form-label">Instrument or performance type</label>
          <select class="form-select" data-f="instrument"></select>
          <input class="form-input" data-f="instrumentOther" maxlength="60" placeholder="e.g. Voice, Ukulele, Band" style="display:none;margin-top:.4rem">
        </div>
        <div class="form-group">
          <label class="form-label">Teacher</label>
          <select class="form-select" data-f="teacher"></select>
          <input class="form-input" data-f="teacherOther" maxlength="80" placeholder="Teacher's name (or leave blank if not sure)" style="display:none;margin-top:.4rem">
        </div>
      </div>
      <div class="form-group">
        <label class="form-label">Name of the piece / song</label>
        <input class="form-input" data-f="piece" maxlength="120" placeholder="e.g. Für Elise (Beethoven)">
      </div>
      <fieldset>
        <legend>Accompaniment</legend>
        ${[['teacher', 'My teacher'], ['peer', 'My peer'], ['backing_track', 'Backing track'], ['none', 'None']].map(([v, l]) =>
          `<label class="ev-radio"><input type="radio" name="${accGroup}" data-f="acc" value="${v}" ${v === 'none' ? 'checked' : ''}> ${l}</label>`).join('')}
        <input class="form-input" data-f="accName" maxlength="80" placeholder="Your peer's name" style="display:none;margin-top:.4rem">
      </fieldset>
      <div class="form-group">
        <label class="form-label">Preferred time blocks</label>
        <div class="form-hint" style="margin-bottom:.4rem">Choose up to three. You'll be placed in the first one that still has room.</div>
        <div class="ev-choice-row">
          <select class="form-select" data-f="c1"></select>
          <select class="form-select" data-f="c2"></select>
          <select class="form-select" data-f="c3"></select>
        </div>
      </div>
      <div class="form-group">
        <label class="form-label">Anything else we should know? <span style="font-weight:400;color:var(--mid-grey)">(optional)</span></label>
        <textarea class="form-textarea" data-f="notes" maxlength="500" style="min-height:70px" placeholder="e.g. needs a music stand, nervous first performance, can't arrive before 3pm"></textarea>
      </div>
      <div style="display:flex;gap:.6rem;justify-content:flex-end;flex-wrap:wrap">
        ${ex && cfg.onCancelBooking ? '<button type="button" class="btn btn-danger" data-f="cancelBooking" style="margin-right:auto">Cancel this booking</button>' : ''}
        ${cfg.onCancel ? `<button type="button" class="btn btn-ghost" data-f="cancel">${ex ? 'Close without saving' : 'Never mind'}</button>` : ''}
        <button type="button" class="btn btn-primary" data-f="submit">${PF.esc(cfg.submitLabel ?? (ex ? 'Save changes' : 'Book my performance'))}</button>
      </div>`;
    cfg.mount.innerHTML = '';
    cfg.mount.appendChild(wrap);

    const $ = f => wrap.querySelector(`[data-f="${f}"]`);
    const accRadios = [...wrap.querySelectorAll('[data-f="acc"]')];
    const accVal = () => (accRadios.find(r => r.checked) || {}).value || 'none';
    const msg = (html, kind) => { wrap.querySelector('.ev-msg').innerHTML = html ? `<div class="${kind === 'ok' ? 'ev-form-ok' : 'ev-form-error'}">${html}</div>` : ''; };

    // -- students
    let studentChoices = (cfg.students ?? []).slice();
    const fillStudents = (filter) => {
      const sel = $('student');
      const cur = sel.value;
      const f = (filter ?? '').trim().toLowerCase();
      const list = studentChoices.filter(s => !f || s.name.toLowerCase().includes(f));
      sel.innerHTML = (cfg.isAdmin ? '<option value="">— Select a student —</option>' : '') +
        list.map(s => `<option value="${PF.esc(s.id)}">${PF.esc(s.name)}</option>`).join('');
      if (cur && list.some(s => s.id === cur)) sel.value = cur;
      else if (!cfg.isAdmin && list.length) sel.value = (ex ? ex.student_id : (cfg.defaultStudentId ?? list[0].id));
    };
    fillStudents();
    if (ex) { $('student').innerHTML = `<option value="${PF.esc(ex.student_id)}">${PF.esc((studentChoices.find(s => s.id === ex.student_id) || {}).name ?? '')}</option>`; }
    if (single) { $('studentWrap').querySelector('label').textContent = 'Performer'; }
    if ($('studentFilter')) $('studentFilter').addEventListener('input', e => { fillStudents(e.target.value); });

    // -- instrument / teacher
    // A student may perform once per instrument / performance type (e.g.
    // Piano AND Band), so instruments they already have booked are greyed out.
    const norm = x => String(x ?? '').trim().toLowerCase();
    const takenInstruments = () => {
      const sid = $('student').value;
      return new Set(bookings.filter(b => b.student_id === sid && (!ex || b.id !== ex.id)).map(b => norm(b.instrument)));
    };
    const withBand = list => list.some(i => norm(i) === 'band') ? list : list.concat(['Band']);
    const markTaken = () => {
      const taken = takenInstruments();
      [...$('instrument').options].forEach(o => {
        if (!o.value || o.value === '__other') return;
        const base = o.dataset.name || o.textContent;
        o.dataset.name = base;
        const t = !cfg.isAdmin && taken.has(norm(base));   // admins may double-book
        o.disabled = t;
        o.textContent = t ? `${base} — already booked` : base;
      });
    };
    const fillInstruments = (keep) => {
      const sel = $('instrument');
      const list = withBand(opts.instruments ?? []);
      sel.innerHTML = '<option value="">— Select —</option>' +
        list.map(i => `<option value="${PF.esc(i)}" data-name="${PF.esc(i)}">${PF.esc(i)}</option>`).join('') +
        '<option value="__other">Other (type it in)…</option>';
      markTaken();
      const want = keep ?? '';
      if (want && list.includes(want)) sel.value = want;
      else if (want) { sel.value = '__other'; $('instrumentOther').value = want; }
      else {
        const free = list.filter(i => !takenInstruments().has(norm(i)));
        if ((opts.instruments ?? []).length === 1 && free.includes(opts.instruments[0])) sel.value = opts.instruments[0];
      }
      $('instrumentOther').style.display = sel.value === '__other' ? '' : 'none';
    };
    const instrumentValue = () => $('instrument').value === '__other' ? $('instrumentOther').value.trim() : $('instrument').value;

    const fillTeachers = (keepId, keepName) => {
      const sel = $('teacher');
      const instr = instrumentValue().toLowerCase();
      const mine = [];
      const seen = new Set();
      (opts.teachers ?? []).forEach(t => { if (!seen.has(t.id)) { seen.add(t.id); mine.push(t); } });
      const matching = [];
      const seenM = new Set();
      (opts.teachers ?? []).filter(t => instr && String(t.instrument).toLowerCase() === instr)
        .forEach(t => { if (!seenM.has(t.id)) { seenM.add(t.id); matching.push(t); } });
      const primary = matching.length ? matching : mine;
      let html = '<option value="">— Select —</option>' +
        primary.map(t => `<option value="${PF.esc(t.id)}">${PF.esc(t.name)}</option>`).join('');
      if (cfg.isAdmin) {
        const rest = (opts.all_teachers ?? []).filter(t => !primary.some(p => p.id === t.id));
        if (rest.length) html += '<optgroup label="All teachers">' + rest.map(t => `<option value="${PF.esc(t.id)}">${PF.esc(t.name)}</option>`).join('') + '</optgroup>';
      }
      html += '<option value="__other">Someone else / not sure…</option>';
      sel.innerHTML = html;
      if (keepId && [...sel.options].some(o => o.value === keepId)) sel.value = keepId;
      else if (keepName) { sel.value = '__other'; $('teacherOther').value = keepName; }
      else if (primary.length === 1) sel.value = primary[0].id;
      $('teacherOther').style.display = sel.value === '__other' ? '' : 'none';
    };

    // -- blocks
    const fillChoices = (keep) => {
      const stats = PF.blockStats(ev, bookings, ex ? ex.id : null);
      const cur = keep ?? [$('c1').value, $('c2').value, $('c3').value].map(v => v ? Number(v) : null);
      const chosen = new Set(cur.filter(Boolean));
      ['c1', 'c2', 'c3'].forEach((id, idx) => {
        const sel = $(id);
        const label = ['1st choice', '2nd choice (optional)', '3rd choice (optional)'][idx];
        sel.innerHTML = `<option value="">— ${label} —</option>` + stats.map(s => {
          const mineBlock = cur[idx] === s.block;
          const taken = chosen.has(s.block) && !mineBlock;
          const disabled = (s.full && !mineBlock) || taken;
          const note = s.full ? 'full' : `${s.free} place${s.free === 1 ? '' : 's'} left`;
          return `<option value="${s.block}" ${disabled ? 'disabled' : ''}>Block ${s.block} · ${PF.blockTimes(ev, s.block)} — ${note}</option>`;
        }).join('');
        if (cur[idx]) sel.value = String(cur[idx]);
      });
    };

    const loadFor = async (studentId, keep) => {
      if (!studentId) { opts = { instruments: [], teachers: [], all_teachers: [] }; fillInstruments(); fillTeachers(); return; }
      try { opts = await cfg.loadOptions(studentId); }
      catch (e) { msg(PF.esc(PF.errorText(e))); opts = { instruments: [], teachers: [], all_teachers: [] }; }
      fillInstruments(keep?.instrument);
      fillTeachers(keep?.teacher_id, keep?.teacher_name);
    };

    // -- wire up
    $('student').addEventListener('change', () => loadFor($('student').value));
    $('instrument').addEventListener('change', () => {
      $('instrumentOther').style.display = $('instrument').value === '__other' ? '' : 'none';
      fillTeachers();
    });
    $('instrumentOther').addEventListener('input', () => fillTeachers($('teacher').value));
    $('teacher').addEventListener('change', () => {
      const other = $('teacher').value === '__other';
      $('teacherOther').style.display = other ? '' : 'none';
      if (other) $('teacherOther').focus();
    });
    accRadios.forEach(r => r.addEventListener('change', () => { $('accName').style.display = accVal() === 'peer' ? '' : 'none'; }));
    ['c1', 'c2', 'c3'].forEach(id => $(id).addEventListener('change', () => fillChoices()));
    if ($('cancel')) $('cancel').addEventListener('click', () => cfg.onCancel());
    if ($('cancelBooking')) $('cancelBooking').addEventListener('click', () => cfg.onCancelBooking(ex));

    $('submit').addEventListener('click', async () => {
      if (busy) return;
      msg('');
      const v = {
        student_id: $('student').value,
        instrument: instrumentValue(),
        teacher_id: ($('teacher').value && $('teacher').value !== '__other') ? $('teacher').value : null,
        teacher_name: $('teacher').value === '__other' ? ($('teacherOther').value.trim() || 'Not sure') : null,
        piece: $('piece').value.trim(),
        accompaniment: accVal(),
        accompanist_name: accVal() === 'peer' ? $('accName').value.trim() : null,
        preferred_blocks: [$('c1').value, $('c2').value, $('c3').value].filter(Boolean).map(Number),
        notes: $('notes').value.trim() || null,
      };
      const problems = [];
      if (!v.student_id) problems.push('choose who is performing');
      if (!v.instrument) problems.push('choose or type the instrument');
      else if (!cfg.isAdmin && takenInstruments().has(norm(v.instrument))) problems.push(`choose a different instrument — ${v.instrument} is already booked for this student (edit or cancel that booking, or choose e.g. Band)`);
      if (!v.teacher_id && !v.teacher_name) problems.push('choose a teacher (or "Someone else / not sure")');
      if (!v.piece) problems.push('enter the name of the piece');
      if (v.accompaniment === 'peer' && !v.accompanist_name) problems.push("enter your peer's name");
      if (!$('c1').value) problems.push('choose at least a 1st-choice block');
      else if (!v.preferred_blocks.length) problems.push('choose a block');
      if ($('c1').value === '' && ($('c2').value || $('c3').value)) problems.push('fill in your 1st choice before the others');
      if (problems.length) { msg('Please ' + problems.join(', ') + '.'); wrap.scrollIntoView?.({ block: 'nearest' }); return; }

      busy = true; $('submit').disabled = true; const label = $('submit').textContent; $('submit').textContent = 'Saving…';
      try {
        const res = await cfg.onSubmit(v);
        busy = false; $('submit').disabled = false; $('submit').textContent = label;
        if (cfg.onDone) cfg.onDone(res, v);
      } catch (e) {
        busy = false; $('submit').disabled = false; $('submit').textContent = label;
        msg(PF.esc(PF.errorText(e)));
        if (e.code === 'none_available' && cfg.onStale) { await cfg.onStale(); }
      }
    });

    // -- initial values
    (async () => {
      if (ex) {
        $('piece').value = ex.piece ?? '';
        $('notes').value = ex.notes ?? '';
        accRadios.forEach(r => { r.checked = r.value === ex.accompaniment; });
        $('accName').value = ex.accompanist_name ?? '';
        $('accName').style.display = ex.accompaniment === 'peer' ? '' : 'none';
        await loadFor(ex.student_id, ex);
        fillChoices(((ex.preferred_blocks ?? []).concat([null, null, null])).slice(0, 3));
      } else {
        await loadFor($('student').value);
        fillChoices([cfg.prefillBlock || null, null, null]);
      }
    })();

    return {
      setBookings(b) { bookings = b ?? []; fillChoices(); markTaken(); },
      destroy() { wrap.remove(); },
      el: wrap,
      showMessage: msg,
    };
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = PF;
  root.PFEvents = PF;
})(typeof window !== 'undefined' ? window : globalThis);
