/* ============================================================
 * PFPromo — poster (A3) and leaflet (A6) generator for events.
 *
 * Pure functions: give it an event row (plus a few optional extras)
 * and it returns complete, self-contained HTML documents sized for
 * printing. The same module runs in the portal (event-promo.html) and
 * in Node (tests, and to produce the PDFs from the command line).
 *
 *   const s = PFPromo.fromEvent(eventRow, { origin, studioName, assets });
 *   const html = PFPromo.html('poster', s, 'print');   // 'poster' | 'leaflet' | 'sheet'
 *   const size = PFPromo.pageSize('poster', 'print');  // { w, h } in mm
 *
 * Modes:  'office' = exactly the trim size (prints on any printer)
 *         'print'  = 3 mm bleed + crop marks, for a print shop
 *         (the 'sheet' kind is four A6 leaflets on one A4 page, office only)
 *
 * Nothing here reads the DOM or the database.
 * ============================================================ */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.PFPromo = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  const P = {};

  const ORANGE = '#E8491E', CHAR = '#1C1C1E';
  const BLEED = 3, SLUG = 7;

  /** Both studios; shown in the header and footer unless the event belongs to one studio */
  P.STUDIOS = [
    { name: 'Kilsyth',  phone: '0434 198 929', email: 'kilsyth@pathfindermusiclessons.com.au' },
    { name: 'Ringwood', phone: '0489 930 719', email: 'ringwood@pathfindermusiclessons.com.au' },
  ];
  P.SITE = 'https://www.pathfindermusiclessons.com.au';
  P.DEFAULT_PERFORMER_NOTE = 'Forgotten your password? Tap “Forgot password?” on the sign-in page.';

  // ---------- small helpers ----------
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const toMins = t => { const [h, m] = String(t ?? '0:0').split(':').map(Number); return (h || 0) * 60 + (m || 0); };
  const dateParts = ds => {
    const [y, m, d] = String(ds ?? '').slice(0, 10).split('-').map(Number);
    if (!y || !m || !d) return null;
    return { y, m, d, wd: DAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()] };
  };
  /** 12:00 PM, 7:00 PM, 11:30 AM */
  P.clock = mins => {
    const h24 = Math.floor(mins / 60) % 24, m = mins % 60, h12 = h24 % 12 === 0 ? 12 : h24 % 12;
    return `${h12}:${String(m).padStart(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}`;
  };
  P.money = cents => {
    const n = Number(cents) / 100;
    return '$' + (Number.isInteger(n) ? String(n) : n.toFixed(2));
  };
  /** Same rule as the portal's PF.capacity: ceil((end-start)/block) blocks × slots per block */
  P.capacity = ev => {
    const bm = ev.block_minutes || 60, per = ev.slots_per_block || 12;
    const blocks = Math.max(1, Math.ceil((toMins(ev.end_time) - toMins(ev.start_time)) / bm));
    return blocks * per;
  };

  /**
   * "2026 Year-end Concert" -> { year: '2026', line1: 'Year-end', line2: 'Concert' }
   * Two words or fewer split one per line; longer names break near the middle
   * (the second line is the orange one).
   */
  P.splitName = name => {
    let n = String(name ?? '').trim().replace(/\s+/g, ' ');
    let year = '';
    const m = n.match(/(?:^|\s)(20\d\d)(?=\s|$)/);
    if (m) { year = m[1]; n = n.replace(m[0], ' ').trim(); }
    const w = n.split(' ').filter(Boolean);
    if (!w.length) return { year, line1: '', line2: '' };
    if (w.length === 1) return { year, line1: w[0], line2: '' };
    let best = 1, bestDiff = Infinity;
    for (let i = 1; i < w.length; i++) {
      const d = Math.abs(w.slice(0, i).join(' ').length - w.slice(i).join(' ').length);
      if (d < bestDiff) { bestDiff = d; best = i; }
    }
    if (w.length === 2) best = 1;
    return { year, line1: w.slice(0, best).join(' '), line2: w.slice(best).join(' ') };
  };

  /** One extra line -> which little icon to use */
  P.iconFor = text => /parking|car park/i.test(text) ? 'p'
    : /park|garden|walk|explor|lake|river/i.test(text) ? 'tree' : 'star';

  // ---------- QR codes (needs qrcode-generator.js loaded as global `qrcode`, or passed in) ----------
  let QR = (typeof qrcode !== 'undefined') ? qrcode : null;
  P.useQr = lib => { QR = lib; };
  P.qrMatrix = url => {
    if (!QR) throw new Error('QR library is not loaded');
    const q = QR(0, 'M'); q.addData(String(url)); q.make();
    const n = q.getModuleCount(), rows = [];
    for (let r = 0; r < n; r++) { const row = []; for (let c = 0; c < n; c++) row.push(q.isDark(r, c)); rows.push(row); }
    return rows;
  };
  /** SVG with a 4-module white quiet zone */
  P.qrSvg = url => {
    const m = P.qrMatrix(url), n = m.length, qz = 4;
    let d = '';
    m.forEach((row, y) => row.forEach((v, x) => { if (v) d += `M${x + qz} ${y + qz}h1v1h-1z`; }));
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${n + 2 * qz} ${n + 2 * qz}" shape-rendering="crispEdges"><rect width="${n + 2 * qz}" height="${n + 2 * qz}" fill="#fff"/><path d="${d}" fill="#000"/></svg>`;
  };
  /** PNG for pasting into other tools (browser only) */
  P.qrPngBlob = (url, px) => new Promise(resolve => {
    const m = P.qrMatrix(url), n = m.length, qz = 4, tot = n + 2 * qz;
    const scale = Math.max(1, Math.floor((px || 1000) / tot)), size = tot * scale;
    const cv = document.createElement('canvas'); cv.width = cv.height = size;
    const g = cv.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, size, size); g.fillStyle = '#000';
    m.forEach((row, y) => row.forEach((v, x) => { if (v) g.fillRect((x + qz) * scale, (y + qz) * scale, scale, scale); }));
    cv.toBlob(resolve, 'image/png');
  });

  // ---------- settings ----------
  /**
   * Turn an event row into the editable settings that drive the layout.
   * ev: row from `events` (promo_* columns optional)
   * o:  { origin, studioName, assets: { logo, fontBase }, today }
   */
  P.fromEvent = (ev, o) => {
    o = o || {};
    const origin = (o.origin || P.SITE).replace(/\/+$/, '');
    const nm = P.splitName(ev.name);
    const d = dateParts(ev.event_date);
    const startH = Math.floor(toMins(ev.start_time) / 60);
    const part = startH < 12 ? 'a morning' : startH < 17 ? 'an afternoon' : 'an evening';
    const hl = String(ev.promo_highlights ?? '').split(/\r?\n/).map(x => x.trim()).filter(Boolean);
    const dl = String(ev.booking_deadline ?? '').slice(0, 10);
    const dp = dateParts(dl);
    const tix = !!ev.tickets_enabled;
    const open = ev.status === 'open';
    const studios = (o.studioName
      ? P.STUDIOS.filter(s => String(o.studioName).toLowerCase().includes(s.name.toLowerCase()))
      : []);
    const sel = studios.length ? studios : P.STUDIOS.slice();
    const s = {
      headline1: nm.line1, headline2: nm.line2,
      kicker: `Live at Pathfinder${nm.year ? ' · ' + nm.year : (d ? ' · ' + d.y : '')}`,
      pill: tix ? 'Tickets on sale now' : 'You’re invited',
      lead: (ev.promo_tagline || '').trim() ||
        `Come and cheer on our students as they take the stage. Bring your family and friends for ${part} of live music!`,
      dateLine: d ? `${d.wd} ${d.d} ${MONTHS[d.m - 1]}` : '',
      year: d ? String(d.y) : '',
      timeLine: `${P.clock(toMins(ev.start_time))} – ${P.clock(toMins(ev.end_time))}`,
      doorsLine: hl[0] || '',
      extras: hl.slice(1, 5),
      venueName: ev.venue_name || '',
      venueAddress: ev.venue_address || '',
      studios: sel,
      tickets: {
        on: tix,
        price: P.money(ev.ticket_price_cents ?? 0),
        url: `${origin}/tickets?event=${ev.id}`,
        shownUrl: 'pathfindermusiclessons.com.au/tickets',
        strip: 'Family and friends welcome',
        bullets: ['Pay securely online', 'Tickets are emailed to you straight away', 'Show the QR code on your phone at the door'],
      },
      perf: {
        on: open,
        url: `${origin}/portal/event-book.html?event=${ev.id}`,
        deadline: dp ? `${dp.d} ${MONTHS[dp.m - 1].slice(0, 3)}` : '',
        spots: P.capacity(ev),
        showSpots: true,
        steps: ['Scan and sign in to the Student Portal', 'Choose up to three time blocks', 'Enter your piece and any accompaniment'],
        note: (ev.promo_performer_note || '').trim() || P.DEFAULT_PERFORMER_NOTE,
      },
      leaflet: {
        kicker: 'You’re invited · bring family & friends',
        qr: tix ? 'tickets' : 'book',
        performerLine: open && tix,
      },
      assets: o.assets || {},
    };
    return s;
  };

  // ---------- icons ----------
  const svg = inner => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${inner}</svg>`;
  const ICON = {
    cal: svg('<rect x="3" y="4.5" width="18" height="16" rx="2.5"/><path d="M3 9.5h18M8 2.5v4M16 2.5v4"/>'),
    clk: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5.5l3.5 2"/>'),
    pin: svg('<path d="M12 21.5s7-6.2 7-11.8a7 7 0 1 0-14 0c0 5.6 7 11.8 7 11.8z"/><circle cx="12" cy="9.7" r="2.6"/>'),
    p:   svg('<rect x="3" y="3" width="18" height="18" rx="4"/><path d="M9.5 17V7.5h3.6a3 3 0 0 1 0 6H9.5"/>'),
    tree: svg('<path d="M12 21v-5M12 3.5c-3.3 3-5 5.6-5 8a5 5 0 0 0 10 0c0-2.4-1.7-5-5-8z"/>'),
    star: svg('<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9-5.2-2.8-5.2 2.8 1-5.9L3.5 9.7l5.9-.8z"/>'),
  };

  // ---------- CSS ----------
  const fonts = base => [['Regular', 400], ['Medium', 500], ['SemiBold', 600], ['Bold', 700], ['ExtraBold', 800], ['Black', 900]]
    .map(([n, w]) => `@font-face{font-family:'Inter';font-weight:${w};src:url('${base || ''}promo-Inter-${n}.woff2') format('woff2');}`).join('');

  const SHARED_CSS = `
.row{display:flex;gap:4.5mm;align-items:flex-start}
.row+.row{margin-top:4.5mm}
.row b{display:block}
h1{font-weight:900;text-transform:uppercase}
h1 span{color:${ORANGE}}
.qr svg{width:100%;height:100%}
`;

  const POSTER_CSS = `
.hdr{position:absolute;left:-30mm;right:-30mm;top:-30mm;height:62mm;background:${ORANGE}}
.hdr-in{position:absolute;left:0;right:0;top:0;height:32mm;display:flex;align-items:center;justify-content:space-between;padding:0 16mm}
.hdr-in img{height:24mm;display:block}
.hdr-r{text-align:right;font-weight:800;letter-spacing:.2em;font-size:5.2mm;line-height:1.5;text-transform:uppercase}
.hdr-r small{display:block;font-weight:600;letter-spacing:.08em;font-size:4mm;opacity:.95;text-transform:none}
.body{position:absolute;left:16mm;right:16mm;top:32mm;bottom:30mm;display:flex;flex-direction:column;justify-content:space-between;padding:9mm 0 8mm}
.pill{display:inline-block;background:#fff;color:${ORANGE};font-weight:900;letter-spacing:.16em;font-size:5mm;padding:2.2mm 5mm;border-radius:99mm;text-transform:uppercase}
.kick{margin-top:7mm;color:${ORANGE};font-weight:800;letter-spacing:.24em;font-size:5.6mm;text-transform:uppercase}
h1{font-weight:900;line-height:.92;letter-spacing:-.02em;margin-top:3mm;text-transform:uppercase}
.lead{margin-top:6mm;font-size:6.6mm;line-height:1.4;font-weight:500;color:rgba(255,255,255,.82);max-width:235mm}
.info{background:${ORANGE};border-radius:4mm;padding:8mm 10mm;display:grid;grid-template-columns:1.05fr 1fr;gap:10mm;align-items:center}
.info.one{grid-template-columns:1fr}
.row{display:flex;gap:4.5mm;align-items:flex-start}
.row+.row{margin-top:4.5mm}
.row svg{width:9mm;height:9mm;flex:none;margin-top:1mm}
.row b{display:block;font-weight:900;font-size:8.6mm;line-height:1.1}
.row div{font-size:5.4mm;line-height:1.35;font-weight:500}
.row div.big{font-size:6.2mm;font-weight:700}
.info .col2{border-left:.6mm solid rgba(255,255,255,.55);padding-left:9mm}
.panels{display:grid;grid-template-columns:1fr 1fr;gap:8mm}
.panels.one{grid-template-columns:minmax(0,150mm);justify-content:center}
.card{background:#fff;color:${CHAR};border-radius:4mm;overflow:hidden;height:141mm;position:relative}
.card-h{background:${ORANGE};color:#fff;text-align:center;font-weight:900;letter-spacing:.1em;font-size:5.6mm;padding:3.8mm 4mm;text-transform:uppercase;white-space:nowrap}
.strip{background:#FDE9E2;color:${ORANGE};text-align:center;font-weight:800;font-size:4.7mm;letter-spacing:.02em;padding:2.1mm 4mm;white-space:nowrap}
.card-body{display:flex;gap:5mm;padding:5mm 6mm 0 6mm;align-items:flex-start}
.qr{width:55mm;height:55mm;flex:none;border:.5mm solid #e4e4e4;border-radius:2mm;overflow:hidden}
.qr svg{width:100%;height:100%}
.side .amt{font-weight:900;font-size:19mm;line-height:.95;color:${ORANGE};letter-spacing:-.02em}
.side .amt small{font-size:6mm;font-weight:700;color:${CHAR};letter-spacing:0;display:block;margin-top:1.5mm}
.side .amt.date{font-size:11.5mm;line-height:1}
.scan{font-weight:800;font-size:5mm;line-height:1.3;margin-top:4mm}
.url{text-align:center;font-weight:800;font-size:5.4mm;margin-top:4mm;color:${CHAR}}
.ul{list-style:none;padding:3mm 8mm 0 8mm;font-size:5.4mm;line-height:1.35;font-weight:500}
.ul li{position:relative;padding-left:7mm;margin-top:2.2mm}
.ul li:before{content:"";position:absolute;left:0;top:1.6mm;width:3mm;height:3mm;border-radius:50%;background:${ORANGE}}
.steps{list-style:none;padding:3mm 8mm 0 8mm;font-size:5mm;line-height:1.3;font-weight:500;counter-reset:s}
.steps li{position:relative;padding-left:9mm;margin-top:2.2mm;counter-increment:s}
.steps li:before{content:counter(s);position:absolute;left:0;top:-.2mm;width:6.4mm;height:6.4mm;border-radius:50%;background:${CHAR};color:#fff;font-weight:900;font-size:4.2mm;text-align:center;line-height:6.4mm}
.note{position:absolute;left:8mm;right:8mm;bottom:5mm;font-size:4.3mm;line-height:1.35;color:#555;font-weight:500}
.ft{position:absolute;left:-10mm;right:-10mm;bottom:-10mm;height:40mm;background:#111;padding:0 26mm 10mm;display:flex;align-items:center;justify-content:space-between;gap:10mm}
.ft .q{font-weight:900;font-size:6.4mm;letter-spacing:.04em;text-transform:uppercase;white-space:nowrap}
.ft .c{font-size:5mm;line-height:1.5;font-weight:600;text-align:right;white-space:nowrap}
.ft .c .em{font-size:4.2mm;font-weight:500;color:rgba(255,255,255,.8)}
.ft .c span{color:${ORANGE};font-weight:800}
.ft .c .em{color:rgba(255,255,255,.8);font-weight:500}
`;

  const LEAF_CSS = `
.lf{position:relative;width:105mm;height:148mm;color:#fff}
.lf .hdr{position:absolute;left:-10mm;right:-10mm;top:-10mm;height:31mm;background:${ORANGE}}
.lf .hdr-in{position:absolute;left:0;right:0;top:0;height:21mm;display:flex;align-items:center;justify-content:center;padding:0}
.lf .hdr-in img{height:14mm}
.lf .body{position:absolute;left:7mm;right:7mm;top:21mm;bottom:19mm;display:flex;flex-direction:column;justify-content:space-between;padding:3.5mm 0 1.5mm}
.lf .kick{margin:0;color:${ORANGE};font-weight:800;letter-spacing:.2em;font-size:2.7mm;text-transform:uppercase}
.lf h1{line-height:.92;margin:1.4mm 0 0;letter-spacing:-.02em}
.lf .rows{margin-top:2.2mm}
.lf .row b{display:inline}
.lf .row .v{display:block}
.lf .row{gap:2.4mm;align-items:flex-start}
.lf .row+.row{margin-top:1.2mm}
.lf .row svg{width:4.6mm;height:4.6mm;margin-top:.3mm;color:${ORANGE}}
.lf .row b{font-size:4.1mm;line-height:1.2;font-weight:800}
.lf .row div{font-size:3.2mm;line-height:1.3;font-weight:500;color:rgba(255,255,255,.9)}
.lf .buy{display:flex;gap:4.5mm;align-items:center;background:#fff;color:${CHAR};border-radius:2.6mm;padding:3mm}
.lf .qr{width:31mm;height:31mm;border:none;border-radius:1mm;flex:none}
.lf .buy .t{font-size:2.8mm;font-weight:900;letter-spacing:.12em;color:${ORANGE};text-transform:uppercase}
.lf .buy .amt{font-weight:900;font-size:13mm;line-height:.95;letter-spacing:-.02em;margin-top:.8mm}
.lf .buy .amt.date{font-size:8.6mm;line-height:1}
.lf .buy .amt small{font-size:3.2mm;font-weight:700;letter-spacing:0;display:block;margin-top:.5mm}
.lf .buy .s{font-size:3.2mm;font-weight:800;line-height:1.25;margin-top:1.8mm}
.lf .url{text-align:center;font-weight:800;font-size:3.5mm;margin-top:2mm;color:#fff}
.lf .ft{position:absolute;left:-10mm;right:-10mm;bottom:-10mm;height:29mm;background:#111;padding:0 15mm 10mm;display:flex;flex-direction:column;justify-content:center;align-items:center;text-align:center;font-size:3.1mm;line-height:1.45;font-weight:600}
.lf .ft span{color:${ORANGE};font-weight:800}
.lf .ft .perf{font-size:3mm;font-weight:600;margin-bottom:.8mm;color:#fff}
.lf .ft .perf b{color:${ORANGE};font-weight:800}
`;

  // ---------- artwork ----------
  const headlineSize = (l1, l2, widthMm, maxMm) => {
    const n = Math.max(String(l1).length, String(l2).length, 1);
    return Math.round(Math.min(maxMm, widthMm / (0.75 * n)) * 10) / 10;
  };
  const h1 = (s, widthMm, maxMm) => {
    const size = headlineSize(s.headline1, s.headline2, widthMm, maxMm);
    return `<h1 style="font-size:${size}mm">${esc(s.headline1)}${s.headline2 ? `<br><span>${esc(s.headline2)}</span>` : ''}</h1>`;
  };
  const contactBlock = (s, cls) => {
    const st = s.studios;
    return st.map(x => `<span>${esc(x.name)}</span> ${esc(x.phone)}`).join(' &nbsp;·&nbsp; ');
  };
  const emailLine = s => s.studios.map(x => esc(x.email)).join(' &nbsp;·&nbsp; ');
  const cityLine = s => s.studios.map(x => esc(x.name)).join(' &nbsp;·&nbsp; ');
  const hasPerf = s => s.perf && s.perf.on;
  const hasTix = s => s.tickets && s.tickets.on;

  const posterArt = s => {
    const L = s.assets.logo || '';
    const extras = (s.extras || []).map(t => `<div class="row">${ICON[P.iconFor(t)]}<div>${esc(t)}</div></div>`).join('');
    const venue = (s.venueName || s.venueAddress)
      ? `<div class="row">${ICON.pin}<div><b style="font-size:6mm">${esc(s.venueName)}</b>${s.venueAddress ? `<div>${esc(s.venueAddress)}</div>` : ''}</div></div>` : '';
    const col2 = venue + extras;
    const spots = hasPerf(s) && s.perf.showSpots && s.perf.spots
      ? `<div class="strip">Limited to ${s.perf.spots} performance spots</div>` : '<div class="strip">&nbsp;</div>';
    const tCard = hasTix(s) ? `
  <div class="card">
    <div class="card-h">Buy your tickets</div>
    ${s.tickets.strip ? `<div class="strip">${esc(s.tickets.strip)}</div>` : '<div class="strip">&nbsp;</div>'}
    <div class="card-body">
      <div class="qr">${P.qrSvg(s.tickets.url)}</div>
      <div class="side"><div class="amt">${esc(s.tickets.price)}<small>per ticket</small></div><div class="scan">Scan with your phone camera to buy</div></div>
    </div>
    <div class="url">${esc(s.tickets.shownUrl)}</div>
    <ul class="ul">${(s.tickets.bullets || []).map(b => `<li>${esc(b)}</li>`).join('')}</ul>
  </div>` : '';
    const pCard = hasPerf(s) ? `
  <div class="card">
    <div class="card-h">Performing? Book your spot</div>
    ${spots}
    <div class="card-body">
      <div class="qr">${P.qrSvg(s.perf.url)}</div>
      <div class="side">${s.perf.deadline ? `<div class="amt date">Book by<br>${esc(s.perf.deadline)}</div>` : `<div class="amt date">Book<br>now</div>`}<div class="scan">Scan and sign in with your Student Portal login</div></div>
    </div>
    <ol class="steps">${(s.perf.steps || []).map(b => `<li>${esc(b)}</li>`).join('')}</ol>
    ${s.perf.note ? `<div class="note">${esc(s.perf.note)}</div>` : ''}
  </div>` : '';
    const nCards = (tCard ? 1 : 0) + (pCard ? 1 : 0);
    return `
<div class="hdr"></div>
<div class="hdr-in"><img src="${esc(L)}" alt=""><div class="hdr-r">${cityLine(s)}<small>pathfindermusiclessons.com.au</small></div></div>
<div class="body"><div class="hero">
  <span class="pill">${esc(s.pill)}</span>
  <div class="kick">${esc(s.kicker)}</div>
  ${h1(s, 262, 43)}
  <p class="lead">${esc(s.lead)}</p>
</div>
<div class="info${col2 ? '' : ' one'}">
  <div>
    <div class="row">${ICON.cal}<div><b>${esc(s.dateLine)}</b><div class="big">${esc(s.year)}</div></div></div>
    <div class="row">${ICON.clk}<div><b style="font-size:6.6mm">${esc(s.timeLine)}</b>${s.doorsLine ? `<div>${esc(s.doorsLine)}</div>` : ''}</div></div>
  </div>
  ${col2 ? `<div class="col2">${col2}</div>` : ''}
</div>
${nCards ? `<div class="panels${nCards === 1 ? ' one' : ''}">${tCard}${pCard}</div>` : ''}
</div><div class="ft"><div class="q">Questions?</div><div class="c">${contactBlock(s)}<br><span class="em">${emailLine(s)}</span></div></div>`;
  };

  /** '12:00 PM – 7:00 PM' -> '12:00 – 7:00 PM' (drop the first AM/PM when both ends match) */
  const leafTime = t => t.replace(/ (AM|PM) – (.*) \1$/, ' – $2 $1');
  const leafletArt = s => {
    const L = s.assets.logo || '';
    const mode = !hasTix(s) && !hasPerf(s) ? 'none' : ((s.leaflet.qr === 'book' && hasPerf(s)) || !hasTix(s) ? 'book' : 'tickets');
    const venueShort = String(s.venueName || '').replace(/\s*\([^)]*\)\s*/g, ' ').trim();
    const addrShort = String(s.venueAddress || '').replace(/[,\s]+\d{4}\s*$/, '').trim();
    const parkTxt = (s.extras || []).find(t => P.iconFor(t) === 'p');
    const venueRow = (venueShort || addrShort)
      ? `<div class="row">${ICON.pin}<div>${venueShort ? `<b class="v" style="font-size:3.6mm;display:block">${esc(venueShort)}</b>` : ''}${esc(addrShort)}${parkTxt ? '<br>' + esc(parkTxt) : ''}</div></div>` : '';
    const box = mode === 'none' ? '' : mode === 'tickets' ? `
    <div class="buy"><div class="qr">${P.qrSvg(s.tickets.url)}</div><div><div class="t">Tickets on sale now</div><div class="amt">${esc(s.tickets.price)}<small>per ticket</small></div><div class="s">Scan to buy your tickets online</div></div></div>
    <div class="url">${esc(s.tickets.shownUrl)}</div>` : `
    <div class="buy"><div class="qr">${P.qrSvg(s.perf.url)}</div><div><div class="t">Performers: book your spot</div><div class="amt date">${s.perf.deadline ? `Book by<br>${esc(s.perf.deadline)}` : 'Book now'}</div><div class="s">Scan and sign in to the Student Portal</div></div></div>
    <div class="url">pathfindermusiclessons.com.au/portal</div>`;
    const perfLine = s.leaflet.performerLine && hasPerf(s)
      ? `<div class="perf">Performing? Book your spot in the Student Portal${s.perf.deadline ? ` by <b>${esc(s.perf.deadline)}</b>` : ''}${s.perf.showSpots && s.perf.spots ? ` — limited to <b>${s.perf.spots}</b> spots` : ''}.</div>` : '';
    return `<div class="lf">
<div class="hdr"></div><div class="hdr-in"><img src="${esc(L)}" alt=""></div>
<div class="body">
  <div>
    <div class="kick">${esc(s.leaflet.kicker)}</div>
    ${h1(s, 91, 12.6)}
    <div class="rows">
      <div class="row">${ICON.cal}<div><b>${esc(s.dateLine)} ${esc(s.year)}</b></div></div>
      <div class="row">${ICON.clk}<div><b>${esc(leafTime(s.timeLine))}</b>${s.doorsLine ? ` &nbsp;·&nbsp; ${esc(s.doorsLine.replace(/^doors open at/i, 'doors open'))}` : ''}</div></div>
      ${venueRow}
    </div>
  </div>
  <div>${box}</div>
</div>
<div class="ft">${perfLine}<div>${contactBlock(s)}</div></div>
</div>`;
  };

  // ---------- page wrapper ----------
  const wrap = (css, art, W, H, b, marks, s, title) => {
    const pw = marks ? W + 2 * (b + SLUG) : W, ph = marks ? H + 2 * (b + SLUG) : H;
    const ox = marks ? b + SLUG : 0, off = ox - b;
    let m = '';
    if (marks) {
      const L = 5, gap = b + 1;
      const hl = (x, y) => `<i class="cm" style="left:${x}mm;top:${y}mm;width:${L}mm;height:0;border-top:.1mm solid #000"></i>`;
      const vl = (x, y) => `<i class="cm" style="left:${x}mm;top:${y}mm;height:${L}mm;width:0;border-left:.1mm solid #000"></i>`;
      [ox, ox + W].forEach(cx => [ox, ox + H].forEach((cy, i) => {
        const sx = cx === ox ? -1 : 1, sy = i === 0 ? -1 : 1;
        m += hl(sx > 0 ? cx + gap : cx - gap - L, cy) + vl(cx, sy > 0 ? cy + gap : cy - gap - L);
      }));
    }
    return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title><style>
${fonts(s.assets.fontBase)}
@page{size:${pw}mm ${ph}mm;margin:0}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${pw}mm;height:${ph}mm;background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact}
body{font-family:'Inter',sans-serif;color:#fff;position:relative;overflow:hidden}
.cm{position:absolute;display:block}
.art{position:absolute;left:${off}mm;top:${off}mm;width:${W + 2 * b}mm;height:${H + 2 * b}mm;background:${CHAR};overflow:hidden}
.inner{position:absolute;left:${b}mm;top:${b}mm;width:${W}mm;height:${H}mm}
svg{display:block}
${SHARED_CSS}${css}
</style></head><body>${m}<div class="art"><div class="inner">${art}</div></div></body></html>`;
  };

  const sheet = (s, title) => {
    const sc = 0.924, gut = 4, cw = 105 * sc, ch = 148 * sc;
    const tw = 2 * cw + gut, th = 2 * ch + gut, x0 = (210 - tw) / 2, y0 = (297 - th) / 2;
    const art = leafletArt(s);
    let cells = '';
    for (let r = 0; r < 2; r++) for (let c = 0; c < 2; c++) {
      const x = x0 + c * (cw + gut), y = y0 + r * (ch + gut);
      cells += `<div style="position:absolute;left:${x}mm;top:${y}mm;width:${cw}mm;height:${ch}mm;overflow:hidden;background:${CHAR}"><div style="transform:scale(${sc});transform-origin:0 0;width:105mm;height:148mm;position:relative">${art}</div></div>`;
    }
    const gv = x0 + cw + gut / 2, gh = y0 + ch + gut / 2;
    const guides = `<i class="cm" style="left:${gv}mm;top:0;height:297mm;border-left:.15mm dashed #aaa"></i><i class="cm" style="left:0;top:${gh}mm;width:210mm;border-top:.15mm dashed #aaa"></i>`;
    return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title><style>${fonts(s.assets.fontBase)}
@page{size:210mm 297mm;margin:0} *{box-sizing:border-box;margin:0;padding:0}
html,body{width:210mm;height:297mm;background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact}
body{font-family:'Inter',sans-serif;position:relative;overflow:hidden} .cm{position:absolute;display:block} svg{display:block}
${SHARED_CSS}${LEAF_CSS}</style></head><body>${cells}${guides}</body></html>`;
  };

  /** Page size in mm for a kind/mode */
  P.pageSize = (kind, mode) => {
    if (kind === 'sheet') return { w: 210, h: 297 };
    const [W, H] = kind === 'poster' ? [297, 420] : [105, 148];
    return mode === 'print' ? { w: W + 2 * (BLEED + SLUG), h: H + 2 * (BLEED + SLUG) } : { w: W, h: H };
  };
  /** Trim and bleed boxes (mm, from the top-left of the page) — for stamping PDFs */
  P.boxes = (kind, mode) => {
    if (mode !== 'print' || kind === 'sheet') return null;
    const [W, H] = kind === 'poster' ? [297, 420] : [105, 148];
    const o = BLEED + SLUG;
    return { trim: [o, o, W, H], bleed: [o - BLEED, o - BLEED, W + 2 * BLEED, H + 2 * BLEED] };
  };

  P.html = (kind, s, mode) => {
    const title = `${s.headline1} ${s.headline2}`.trim() + (kind === 'poster' ? ' — poster' : ' — leaflet');
    if (kind === 'sheet') return sheet(s, title);
    const marks = mode === 'print';
    const b = marks ? BLEED : 0;
    return kind === 'poster'
      ? wrap(POSTER_CSS, posterArt(s), 297, 420, b, marks, s, title)
      : wrap(LEAF_CSS, leafletArt(s), 105, 148, b, marks, s, title);
  };

  // ---------- text for emails and social posts ----------
  P.shareText = s => {
    const bits = [];
    bits.push(`${[s.headline1, s.headline2].filter(Boolean).join(' ')} — ${s.dateLine} ${s.year}`.trim());
    bits.push(`${s.timeLine}${s.doorsLine ? ' (' + s.doorsLine.charAt(0).toLowerCase() + s.doorsLine.slice(1) + ')' : ''}`);
    if (s.venueName) bits.push(`${s.venueName}${s.venueAddress ? ', ' + s.venueAddress : ''}`);
    let t = bits.join('\n');
    if (hasTix(s)) t += `\n\nTickets ${s.tickets.price} each — buy online: ${s.tickets.url}`;
    if (hasPerf(s)) t += `\n\nPerformers: book your spot in the Student Portal${s.perf.deadline ? ' by ' + s.perf.deadline : ''}${s.perf.showSpots && s.perf.spots ? ` (limited to ${s.perf.spots} performance spots)` : ''}: ${s.perf.url}`;
    return t;
  };

  return P;
});
