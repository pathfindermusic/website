// ============================================================
// PATHFINDER PORTAL — Gift voucher PDF
//
// Draws the voucher as a vector PDF (A4 landscape) with jsPDF, in the
// browser, so the preview an admin looks at is byte-for-byte the file
// that gets emailed. No server rendering involved.
//
//   const out = await PFVoucher.build({
//     voucherNo, subject, valueAmount,           // valueAmount optional
//     recipientName, purchaserName,
//     purchaseDate, expiresOn,                   // 'YYYY-MM-DD'
//     message,                                   // optional
//     studio: { name, email },                   // or emails: [..] when several studios honour it
//   });
//   out.blob / out.base64 / out.filename / out.url
//
// Needs window.jspdf (jsPDF 2.5, loaded from a CDN by the page) and the
// assets under portal/fonts and portal/img (loaded once, then cached).
// Also runs in Node for tests: PFVoucher.build(data, { jsPDF, assets }).
// ============================================================
(function (root) {
  'use strict';

  const PFV = {};

  // ---------- brand ----------
  const C = {
    orange:   [232, 73, 30],     // #E8491E
    orangeLt: [255, 107, 69],    // #FF6B45
    char:     [28, 28, 30],      // #1C1C1E
    charMid:  [44, 44, 46],      // #2C2C2E
    charLt:   [58, 58, 60],      // #3A3A3C
    white:    [255, 255, 255],
    grey:     [153, 153, 153],
    greyLt:   [206, 206, 210],
    page:     [255, 255, 255],
  };

  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
                  'August', 'September', 'October', 'November', 'December'];

  // ---------- dates ----------
  /** 'YYYY-MM-DD' + 1 year. 29 Feb rolls to 28 Feb, same as Postgres. */
  PFV.addOneYear = function (iso) {
    const [y, m, d] = iso.split('-').map(Number);
    const ny = y + 1;
    const dim = new Date(Date.UTC(ny, m, 0)).getUTCDate();
    return `${ny}-${String(m).padStart(2, '0')}-${String(Math.min(d, dim)).padStart(2, '0')}`;
  };
  PFV.fmtDate = function (iso) {
    if (!iso) return '';
    const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
    return `${d} ${MONTHS[m - 1]} ${y}`;
  };

  // ---------- voucher numbers ----------
  // PF-XXXX-XXXX from an unambiguous alphabet (no 0/O, 1/I/L). Random, so a
  // number cannot be guessed from the one before it — the number is what
  // proves a voucher at the front desk.
  const ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  PFV.newVoucherNo = function () {
    const buf = new Uint8Array(8);
    (root.crypto || require('crypto').webcrypto).getRandomValues(buf);
    const ch = Array.from(buf, b => ALPHABET[b % ALPHABET.length]);
    return `PF-${ch.slice(0, 4).join('')}-${ch.slice(4).join('')}`;
  };
  PFV.VOUCHER_NO_RE = /^PF-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$/;

  // ---------- text safety ----------
  // The embedded Inter subset covers Latin (incl. accents, curly quotes,
  // dashes, € …). Anything else (emoji, CJK) would print as a box, so it is
  // dropped rather than shown broken.
  function supported(cp) {
    return (cp >= 0x20 && cp < 0x7F) || (cp >= 0xA0 && cp < 0x250) ||
           (cp >= 0x2010 && cp < 0x2028) || (cp >= 0x1E00 && cp < 0x1F00) ||
           cp === 0x20AC || cp === 0x2122 || cp === 0x2030 || cp === 0x2039 || cp === 0x203A ||
           cp === 0x266A || cp === 0x266B;
  }
  PFV.clean = function (s, keepNewlines) {
    let out = '';
    for (const ch of String(s ?? '').replace(/\r\n?/g, '\n')) {
      const cp = ch.codePointAt(0);
      if (ch === '\n') { out += keepNewlines ? '\n' : ' '; continue; }
      if (ch === '\t') { out += ' '; continue; }
      if (cp === 0xFE0F || cp === 0x200D) continue;         // emoji joiners
      if (supported(cp)) out += ch;
    }
    out = out.replace(/[ ]{2,}/g, ' ');
    return keepNewlines ? out.replace(/\n{3,}/g, '\n\n').trim() : out.replace(/\s+/g, ' ').trim();
  };
  PFV.stripUnsupported = PFV.clean;

  // ---------- assets (fonts + logo) ----------
  const ASSET_FILES = {
    regular:  'fonts/Inter-Regular.ttf',
    italic:   'fonts/Inter-Italic.ttf',
    semibold: 'fonts/Inter-SemiBold.ttf',
    extra:    'fonts/Inter-ExtraBold.ttf',
    logo:     'img/voucher-logo.png',
  };
  let assetCache = null;

  function bufToB64(buf) {
    const bytes = new Uint8Array(buf);
    let bin = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(bin);
  }

  /** Fetches the font + logo files once. `base` is the portal folder URL. */
  PFV.loadAssets = async function (base = '') {
    if (assetCache) return assetCache;
    const entries = await Promise.all(Object.entries(ASSET_FILES).map(async ([k, path]) => {
      const r = await fetch(base + path);
      if (!r.ok) throw new Error(`Could not load ${path} (${r.status})`);
      return [k, bufToB64(await r.arrayBuffer())];
    }));
    assetCache = Object.fromEntries(entries);
    return assetCache;
  };

  // ---------- drawing helpers ----------
  const fill = (doc, c) => doc.setFillColor(c[0], c[1], c[2]);
  const stroke = (doc, c) => doc.setDrawColor(c[0], c[1], c[2]);
  const ink = (doc, c) => doc.setTextColor(c[0], c[1], c[2]);

  // font roles → [family, style]
  const F = {
    regular:  ['Inter', 'normal'],
    italic:   ['Inter', 'italic'],
    bold:     ['Inter', 'bold'],          // ExtraBold file
    semibold: ['InterSemi', 'normal'],
  };
  function font(doc, role, size) {
    doc.setFont(F[role][0], F[role][1]);
    doc.setFontSize(size);
  }

  /** Tracked (letter-spaced) text; returns the drawn width in mm. */
  function tracked(doc, text, x, y, space, opt = {}) {
    space = space * 0.36;                    // spacing values below are in 'pt/4' — tuned by eye
    const n = [...text].length;
    const w = doc.getTextWidth(text) + space * Math.max(0, n - 1);
    let sx = x;
    if (opt.align === 'right') sx = x - w;
    else if (opt.align === 'center') sx = x - w / 2;
    doc.text(text, sx, y, { charSpace: space, baseline: opt.baseline || 'alphabetic' });
    return w;
  }

  /** Shrinks `size` until `text` wraps into at most `maxLines` lines. */
  function fit(doc, role, text, width, maxLines, start, min, lineH = 1.12) {
    let size = start;
    for (; size > min; size -= 0.5) {
      font(doc, role, size);
      if (doc.splitTextToSize(text, width).length <= maxLines) break;
    }
    font(doc, role, size);
    let lines = doc.splitTextToSize(text, width);
    if (lines.length > maxLines) {                       // last resort: trim with an ellipsis
      lines = lines.slice(0, maxLines);
      let last = lines[maxLines - 1];
      while (last.length > 1 && doc.getTextWidth(last + '…') > width) last = last.slice(0, -1);
      lines[maxLines - 1] = last.trimEnd() + '…';
    }
    return { size, lines, lineMm: size * 0.3528 * lineH };
  }

  /** Small decorative stave with a couple of notes (vector, no glyphs). */
  function stave(doc, x, y, w, withNotes) {
    const gap = 2.6;
    stroke(doc, C.charLt); doc.setLineWidth(0.25);
    for (let i = 0; i < 5; i++) doc.line(x, y + i * gap, x + w, y + i * gap);
    if (!withNotes) return;
    fill(doc, C.orange); stroke(doc, C.orange); doc.setLineWidth(0.5);
    const note = (nx, ny, up) => {
      doc.ellipse(nx, ny, 1.9, 1.4, 'F');
      if (up) doc.line(nx + 1.75, ny - 0.1, nx + 1.75, ny - 9);
      else doc.line(nx - 1.75, ny + 0.1, nx - 1.75, ny + 9);
    };
    // two beamed eighths + a lone quarter
    const n1 = [x + w * 0.30, y + gap * 3], n2 = [x + w * 0.44, y + gap * 2.0];
    note(n1[0], n1[1], true); note(n2[0], n2[1], true);
    doc.setLineWidth(1.1);
    doc.line(n1[0] + 1.75, n1[1] - 9, n2[0] + 1.75, n2[1] - 9);
    doc.setLineWidth(0.5);
    note(x + w * 0.66, y + gap * 1.0, false);
    const n4 = [x + w * 0.82, y + gap * 4];
    note(n4[0], n4[1], true);
    // flag on the last note
    doc.setLineWidth(0.7);
    doc.lines([[3.2, 2.2, 3.4, 4.6, 1.4, 6.2]], n4[0] + 1.75, n4[1] - 9);
  }

  /** One address ("a@x"), or several for a voucher redeemable at more than one
   *  studio ("a@x or b@x" / "a@x, b@x or c@x"). Accepts studio.emails (array)
   *  or studio.email (string). */
  function redeemEmails(studio) {
    const list = (Array.isArray(studio?.emails) ? studio.emails : [studio?.email])
      .map(e => PFV.clean(e)).filter(Boolean);
    if (list.length <= 1) return list[0] || '';
    return list.slice(0, -1).join(', ') + ' or ' + list[list.length - 1];
  }

  // ---------- the voucher ----------
  /**
   * Builds the voucher. Resolves to { doc, blob, base64, filename, url }.
   * opts.jsPDF / opts.assets let tests (Node) inject both.
   */
  PFV.build = async function (data, opts = {}) {
    const JsPDF = opts.jsPDF || (root.jspdf && root.jspdf.jsPDF);
    if (!JsPDF) throw new Error('jsPDF is not loaded.');
    const assets = opts.assets || await PFV.loadAssets(opts.base || '');

    const d = {
      voucherNo: PFV.clean(data.voucherNo),
      subject:   PFV.clean(data.subject),
      value:     data.valueAmount === '' || data.valueAmount == null ? null : Number(data.valueAmount),
      to:        PFV.clean(data.recipientName),
      from:      PFV.clean(data.purchaserName),
      bought:    data.purchaseDate,
      expires:   data.expiresOn || PFV.addOneYear(data.purchaseDate),
      message:   PFV.clean(data.message, true),
      studioName:  PFV.clean(data.studio?.name),
      studioEmail: redeemEmails(data.studio),
    };

    const doc = new JsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4', compress: true });
    doc.setProperties({
      title: `Gift Voucher — ${d.subject}`,
      subject: 'Pathfinder Music Lessons gift voucher',
      author: 'Pathfinder Music Lessons',
      creator: 'Pathfinder Portal',
    });

    // fonts
    const addFont = (key, file, family, style) => {
      doc.addFileToVFS(file, assets[key]);
      doc.addFont(file, family, style);
    };
    addFont('regular',  'Inter-Regular.ttf',   'Inter', 'normal');
    addFont('italic',   'Inter-Italic.ttf',    'Inter', 'italic');
    addFont('extra',    'Inter-ExtraBold.ttf', 'Inter', 'bold');
    addFont('semibold', 'Inter-SemiBold.ttf',  'InterSemi', 'normal');

    const W = 297, H = 210, M = 10;                  // page + white margin
    const CW = W - 2 * M, CH = H - 2 * M;            // card
    const STUB = 70;                                 // orange stub width
    const split = M + CW - STUB;                     // x of the perforation
    const pad = 16;                                  // inner padding of the main panel

    // ----- page + card -----
    fill(doc, C.page); doc.rect(0, 0, W, H, 'F');
    fill(doc, C.char); doc.roundedRect(M, M, CW, CH, 5, 5, 'F');

    // orange stub (right-hand side, clipped to the card's rounded corners)
    fill(doc, C.orange);
    doc.roundedRect(split, M, STUB, CH, 5, 5, 'F');
    fill(doc, C.orange); doc.rect(split, M, 10, CH, 'F');    // square off the left edge
    // thin darker rule where stub meets card, then the perforation
    stroke(doc, C.orangeLt); doc.setLineWidth(0.35);
    doc.setLineDashPattern([1.4, 1.6], 0);
    doc.line(split, M + 6, split, M + CH - 6);
    doc.setLineDashPattern([], 0);
    // ticket notches
    fill(doc, C.page);
    doc.circle(split, M, 4.2, 'F');
    doc.circle(split, M + CH, 4.2, 'F');

    // ----- main panel -----
    const mx = M + pad;                              // left text edge
    const mw = split - mx - pad + 2;                 // text width
    let y = M + pad + 4;

    // decorative stave, top-right of the panel
    stave(doc, split - 74, M + 12, 56, true);

    // logo (white, transparent) top-left
    const logoW = 60, logoH = logoW * 315 / 1100;
    doc.addImage('data:image/png;base64,' + assets.logo, 'PNG', mx, y - 4, logoW, logoH, undefined, 'FAST');
    y += logoH + 14;

    // eyebrow
    font(doc, 'semibold', 9.5); ink(doc, C.orange);
    tracked(doc, 'A GIFT OF MUSIC', mx, y, 1.6);
    y += 16;

    // the subject — the headline
    ink(doc, C.white);
    const sub = fit(doc, 'bold', d.subject, mw, 2, 34, 18, 1.08);
    sub.lines.forEach((ln, i) => doc.text(ln, mx, y + i * sub.lineMm));
    y += (sub.lines.length - 1) * sub.lineMm;
    if (sub.lines.length === 1) y += 6;            // balance a one-line headline

    // optional dollar value
    if (d.value != null && !Number.isNaN(d.value)) {
      const txt = 'Value  ' + new Intl.NumberFormat('en-AU', { style: 'currency', currency: 'AUD',
        minimumFractionDigits: Number.isInteger(d.value) ? 0 : 2 }).format(d.value);
      font(doc, 'semibold', 10.5);
      const tw = doc.getTextWidth(txt) + 9;
      y += 6;
      fill(doc, C.orange); doc.roundedRect(mx, y, tw, 7.6, 3.8, 3.8, 'F');
      ink(doc, C.white); doc.text(txt, mx + 4.5, y + 5.2);
      y += 7.6;
    }
    y += 12;

    // TO / FROM / PURCHASED row
    const colW = [mw * 0.38, mw * 0.33, mw * 0.29];
    const cols = [mx, mx + colW[0], mx + colW[0] + colW[1]];
    const labels = ['TO', 'FROM', 'PURCHASED'];
    const values = [d.to, d.from, PFV.fmtDate(d.bought)];
    stroke(doc, C.charLt); doc.setLineWidth(0.3);
    doc.line(mx, y - 6.5, mx + mw, y - 6.5);
    for (let i = 0; i < 3; i++) {
      font(doc, 'semibold', 8); ink(doc, C.orange);
      tracked(doc, labels[i], cols[i], y, 1.4);
      ink(doc, C.white);
      const f = fit(doc, 'semibold', values[i], colW[i] - 6, i === 2 ? 1 : 2, 16, i === 2 ? 11 : 9.5, 1.15);
      f.lines.forEach((ln, j) => doc.text(ln, cols[i], y + 7 + j * f.lineMm));
    }
    y += 24;

    // personal message
    const footY = M + CH - 22;                       // top of the footer zone
    if (d.message) {
      const tw = mw - 14, maxH = Math.max(20, footY - y - 4);
      let size = 13, lines;
      for (; size >= 7; size -= 0.5) {
        font(doc, 'italic', size);
        lines = doc.splitTextToSize(d.message, tw);
        if (lines.length * size * 0.3528 * 1.45 + 14 <= maxH) break;
      }
      font(doc, 'italic', size);
      const lh = size * 0.3528 * 1.45;
      const maxLines = Math.max(1, Math.floor((maxH - 14) / lh));
      if (lines.length > maxLines) {
        lines = lines.slice(0, maxLines);
        let last = lines[maxLines - 1];
        while (last.length > 1 && doc.getTextWidth(last + '…') > tw) last = last.slice(0, -1);
        lines[maxLines - 1] = last.trimEnd() + '…';
      }
      const boxH = Math.min(maxH, Math.max(26, lines.length * lh + 15));
      fill(doc, C.charMid); doc.roundedRect(mx, y, mw, boxH, 2.5, 2.5, 'F');
      fill(doc, C.orange);  doc.roundedRect(mx, y, 1.8, boxH, 0.9, 0.9, 'F');
      font(doc, 'semibold', 7.5); ink(doc, C.orange);
      tracked(doc, 'A PERSONAL MESSAGE', mx + 7, y + 6.6, 1.3);
      font(doc, 'italic', size); ink(doc, C.greyLt);
      lines.forEach((ln, i) => doc.text(ln, mx + 7, y + 14 + i * lh));
    } else {
      // no personal message: a short line in the studio's voice, same panel
      const boxH = 26;
      fill(doc, C.charMid); doc.roundedRect(mx, y, mw, boxH, 2.5, 2.5, 'F');
      fill(doc, C.orange);  doc.roundedRect(mx, y, 1.8, boxH, 0.9, 0.9, 'F');
      font(doc, 'semibold', 7.5); ink(doc, C.orange);
      tracked(doc, 'FROM ALL OF US AT PATHFINDER', mx + 7, y + 6.6, 1.3);
      font(doc, 'italic', 13); ink(doc, C.greyLt);
      doc.text('Happy playing! We can\u2019t wait to make some music with you.', mx + 7, y + 17, { maxWidth: mw - 14 });
    }

    // footer: validity + how to redeem
    stroke(doc, C.charLt); doc.setLineWidth(0.3);
    doc.line(mx, footY + 3, mx + mw, footY + 3);
    font(doc, 'semibold', 9.5); ink(doc, C.white);
    doc.text(`Valid for one year from the date of purchase — until ${PFV.fmtDate(d.expires)}.`, mx, footY + 10);
    font(doc, 'regular', 8.5); ink(doc, C.grey);
    const redeem = 'To redeem, ' + (d.studioEmail ? 'email ' + d.studioEmail : 'contact us') +
                   ' and quote your voucher number.  pathfindermusiclessons.com.au';
    doc.text(doc.splitTextToSize(redeem, mw), mx, footY + 15.5);

    // ----- stub -----
    const sx = split + 12, sw = STUB - 24, scx = split + STUB / 2;
    ink(doc, C.white);
    font(doc, 'bold', 27);
    doc.text('GIFT', scx, M + 38, { align: 'center' });
    doc.text('VOUCHER', scx, M + 38 + 12, { align: 'center' });
    font(doc, 'semibold', 8); ink(doc, [255, 226, 214]);
    tracked(doc, 'PATHFINDER MUSIC LESSONS', scx, M + 38 + 21, 1.0, { align: 'center' });

    // a record, for the music
    const rcx = scx, rcy = M + 98, rr = 22;
    fill(doc, [196, 58, 20]); doc.circle(rcx, rcy, rr, 'F');
    stroke(doc, [214, 66, 26]); doc.setLineWidth(0.3);
    for (let r = rr - 3; r > 9; r -= 2.6) doc.circle(rcx, rcy, r, 'S');
    fill(doc, C.white); doc.circle(rcx, rcy, 7.4, 'F');
    fill(doc, C.orange); doc.circle(rcx, rcy, 6.2, 'F');
    fill(doc, C.white); doc.circle(rcx, rcy, 1.1, 'F');

    // voucher number + expiry at the bottom
    const sy = M + CH - 52;
    font(doc, 'semibold', 7.5); ink(doc, [255, 226, 214]);
    tracked(doc, 'VOUCHER NO.', scx, sy, 1.3, { align: 'center' });
    font(doc, 'bold', 15); ink(doc, C.white);
    doc.text(d.voucherNo, scx, sy + 8, { align: 'center' });
    font(doc, 'semibold', 7.5); ink(doc, [255, 226, 214]);
    tracked(doc, 'VALID UNTIL', scx, sy + 21, 1.3, { align: 'center' });
    font(doc, 'bold', 12); ink(doc, C.white);
    doc.text(PFV.fmtDate(d.expires), scx, sy + 28.5, { align: 'center' });

    // ----- output -----
    const filename = `Pathfinder-Voucher-${d.voucherNo}.pdf`;
    const ab = doc.output('arraybuffer');
    let base64;
    if (typeof Buffer !== 'undefined') base64 = Buffer.from(ab).toString('base64');
    else base64 = bufToB64(ab);
    const out = { doc, base64, filename, size: ab.byteLength };
    if (typeof Blob !== 'undefined') {
      out.blob = new Blob([ab], { type: 'application/pdf' });
      if (typeof URL !== 'undefined' && URL.createObjectURL) out.url = URL.createObjectURL(out.blob);
    }
    return out;
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = PFV;
  root.PFVoucher = PFV;
})(typeof window !== 'undefined' ? window : globalThis);
