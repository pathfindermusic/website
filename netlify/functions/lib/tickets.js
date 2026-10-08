// ============================================================
// Shared code for the concert-ticket functions
//   ticket-event, ticket-checkout, ticket-confirm, ticket-admin,
//   reconcile-ticket-orders
//
// This folder has no function of its own name in it, so Netlify
// bundles it into the functions that require it but never deploys it
// as a function.
//
// WHAT IS TRUSTED — only eWAY. The visitor's browser says "I paid"
// by arriving at ticket-result.html; that proves nothing. Every order
// is settled by asking eWAY's server (with our secret API key) what
// happened to that payment's access code. Tickets are issued only when
// eWAY says the payment was approved AND the amount equals the order
// total we stored ourselves when the order was created.
//
// Environment variables
//   SUPABASE_URL, SUPABASE_SERVICE_KEY, RESEND_API_KEY   (as other functions)
//   EWAY_API_KEY, EWAY_API_PASSWORD   MYeWAY → My Account → API Key
//   EWAY_ENDPOINT                     "sandbox" or "production"
//   SITE_URL            optional; default https://www.pathfindermusiclessons.com.au
//   TICKETS_FROM_EMAIL  optional; default admin@pathfindermusiclessons.com.au
//   TICKETS_BCC         optional; comma-separated addresses copied on every
//                       ticket email (leave unset to copy nobody)
// ============================================================
'use strict';

const crypto = require('crypto');

const TZ                 = 'Australia/Melbourne';
const MAX_PER_ORDER      = 10;
// eWAY response codes that mean "approved" (10, partial approval, is
// deliberately not here: we only accept the full amount).
const APPROVED_CODES     = ['00', '08', '11', '16'];
const DEFAULT_SITE       = 'https://www.pathfindermusiclessons.com.au';
const DEFAULT_FROM       = 'admin@pathfindermusiclessons.com.au';
const ALPHABET           = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';   // no 0 O 1 I L

// ------------------------------------------------------------
// configuration
// ------------------------------------------------------------
class ConfigError extends Error {}

function loadConfig() {
  const e = process.env;
  const missing = ['SUPABASE_URL', 'SUPABASE_SERVICE_KEY', 'RESEND_API_KEY',
                   'EWAY_API_KEY', 'EWAY_API_PASSWORD', 'EWAY_ENDPOINT'].filter(k => !String(e[k] ?? '').trim());
  if (missing.length) throw new ConfigError('Missing environment variables: ' + missing.join(', '));

  const mode = String(e.EWAY_ENDPOINT).trim();
  let ewayBase;
  if (/^(production|live)$/i.test(mode))      ewayBase = 'https://api.ewaypayments.com';
  else if (/^(sandbox|test)$/i.test(mode))    ewayBase = 'https://api.sandbox.ewaypayments.com';
  else if (/^https?:\/\//i.test(mode))        ewayBase = mode.replace(/\/+$/, '');   // explicit URL (tests)
  else throw new ConfigError('EWAY_ENDPOINT must be "sandbox" or "production".');

  return {
    sbUrl:     e.SUPABASE_URL.replace(/\/+$/, ''),
    sbKey:     e.SUPABASE_SERVICE_KEY,
    resendKey: e.RESEND_API_KEY,
    resendUrl: e.RESEND_API_URL || 'https://api.resend.com/emails',
    ewayKey:   e.EWAY_API_KEY,
    ewayPass:  e.EWAY_API_PASSWORD,
    ewayBase,
    sandbox:   /sandbox/i.test(ewayBase),
    site:      String(e.SITE_URL || DEFAULT_SITE).replace(/\/+$/, ''),
    from:      String(e.TICKETS_FROM_EMAIL || DEFAULT_FROM).trim(),
    bcc:       String(e.TICKETS_BCC || '').split(',').map(s => s.trim()).filter(isValidEmail),
  };
}

// ------------------------------------------------------------
// responses
// ------------------------------------------------------------
function json(statusCode, obj) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    body: JSON.stringify(obj),
  };
}

// ------------------------------------------------------------
// validation helpers
// ------------------------------------------------------------
const isUuid = (s) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(s ?? ''));
// eWAY's access codes are long and can include characters such as + / =
// (so don't be strict about the alphabet; they are always URL-encoded when
// used in a query). A "+" that lost its encoding on the way back through
// the browser arrives as a space, so put it back.
const normAccessCode = (s) => String(s ?? '').trim().replace(/ /g, '+');
const isAccessCode = (s) => /^[\x21-\x7E]{8,2000}$/.test(String(s ?? ''));

function isValidEmail(addr) {
  const s = String(addr ?? '').trim();
  if (!s || s.length > 254 || /\s/.test(s)) return false;
  return /^[^@]+@[^@.]+(\.[^@.]+)+$/.test(s);
}

// Free text from a visitor: one line, no control characters, bounded.
function cleanText(s, max) {
  return String(s ?? '')
    .normalize('NFC')
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function maskEmail(addr) {
  const [u, d] = String(addr ?? '').split('@');
  if (!d) return '';
  return (u.length <= 2 ? u[0] ?? '' : u.slice(0, 2)) + '***@' + d;
}

function randomCode(n) {
  const b = crypto.randomBytes(n);
  let s = '';
  for (let i = 0; i < n; i++) s += ALPHABET[b[i] % ALPHABET.length];
  return s;
}
const newOrderNo = () => 'TO-' + randomCode(6);

function todayMelbourne() {
  return new Date().toLocaleDateString('en-CA', { timeZone: TZ });
}

function money(cents) {
  return '$' + (cents / 100).toFixed(2);
}

function formatDateLong(dateStr) {
  if (!dateStr) return '';
  const [y, m, d] = String(dateStr).slice(0, 10).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-AU', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC',
  });
}

function formatTime(t) {
  if (!t) return '';
  const [h, m] = String(t).split(':').map(Number);
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

function firstName(full) {
  return String(full ?? '').trim().split(/\s+/)[0] || 'there';
}

function splitName(full) {
  const parts = String(full ?? '').trim().split(/\s+/);
  return { first: parts[0] || '-', last: parts.slice(1).join(' ') || '-' };
}

// An event can sell tickets when an admin switched it on and it has not happened yet.
function onSale(ev) {
  return !!(ev && ev.tickets_enabled && String(ev.event_date).slice(0, 10) >= todayMelbourne());
}

const EVENT_COLS = 'id,studio_id,name,description,event_date,start_time,end_time,venue_name,venue_address,tickets_enabled,ticket_price_cents,ticket_info';

// ------------------------------------------------------------
// Supabase (service role) — thin REST client
// ------------------------------------------------------------
function makeDb(cfg) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${cfg.sbKey}`,
    'apikey': cfg.sbKey,
  };
  const rest = (p) => `${cfg.sbUrl}/rest/v1/${p}`;

  async function call(method, path, body, prefer) {
    const r = await fetch(rest(path), {
      method,
      headers: prefer ? { ...headers, Prefer: prefer } : headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await r.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!r.ok) {
      const err = new Error(`DB error on ${method} ${path.split('?')[0]}: ${typeof data === 'string' ? data : (data?.message || r.status)}`);
      err.status = r.status;
      err.pgCode = data?.code;
      throw err;
    }
    return data;
  }

  return {
    get:    (path)                => call('GET', path),
    first:  async (path)          => (await call('GET', path))?.[0] ?? null,
    insert: async (table, row)    => (await call('POST', table, row, 'return=representation'))?.[0] ?? null,
    patch:  async (path, fields)  => (await call('PATCH', path, fields, 'return=representation')) ?? [],
    rpc:    (fn, args)            => call('POST', `rpc/${fn}`, args),
    log:    (row) => call('POST', 'email_log', row, 'return=minimal').catch(() => {}),   // logging never breaks a send

    event:        (id)   => makeDbEvent(call, id),
    orderById:    (id)   => call('GET', `ticket_orders?id=eq.${id}&select=*`).then(r => r?.[0] ?? null),
    orderByCode:  (code) => call('GET', `ticket_orders?eway_access_code=eq.${encodeURIComponent(code)}&select=*`).then(r => r?.[0] ?? null),
    ticketsOf:    (id)   => call('GET', `tickets?order_id=eq.${id}&select=ticket_no,seq,status&order=seq.asc`),

    // Verify a signed-in user's access token and load what we need to
    // know about them (role, status, studios).
    async user(token) {
      const ur = await fetch(`${cfg.sbUrl}/auth/v1/user`, {
        headers: { apikey: cfg.sbKey, Authorization: `Bearer ${token}` },
      });
      if (!ur.ok) return null;
      const u = await ur.json();
      if (!u?.id) return null;
      const prof = await call('GET', `profiles?id=eq.${encodeURIComponent(u.id)}&select=role,status`).then(r => r?.[0] ?? null);
      let studioIds = [];
      if (prof?.role === 'admin') {
        const a = await call('GET', `admins?user_id=eq.${encodeURIComponent(u.id)}&select=studio_ids`).then(r => r?.[0] ?? null);
        studioIds = a?.studio_ids ?? [];
      }
      return { id: u.id, email: u.email, role: prof?.role ?? null, status: prof?.status ?? null, studioIds };
    },
  };
}

async function makeDbEvent(call, id) {
  const r = await call('GET', `events?id=eq.${id}&select=${EVENT_COLS}`);
  return r?.[0] ?? null;
}

// May this signed-in user manage this event's ticket sales?
// (superuser: any; admin: events of their studios, or of all studios;
//  an admin with no studios listed manages every studio, as elsewhere)
function canManage(user, ev) {
  if (!user || user.status === 'inactive' || !ev) return false;
  if (user.role === 'superuser') return true;
  if (user.role !== 'admin') return false;
  return !ev.studio_id || !user.studioIds.length || user.studioIds.includes(ev.studio_id);
}

// ------------------------------------------------------------
// eWAY Rapid API
// ------------------------------------------------------------
async function ewayCall(cfg, method, path, body) {
  const auth = Buffer.from(`${cfg.ewayKey}:${cfg.ewayPass}`).toString('base64');
  const r = await fetch(cfg.ewayBase + path, {
    method,
    headers: { 'Authorization': `Basic ${auth}`, 'Content-Type': 'application/json', 'Accept': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  let j = null;
  try { j = text ? JSON.parse(text) : null; } catch { /* not json */ }
  return { status: r.status, ok: r.ok, json: j, text };
}

// Start a payment on eWAY's hosted "Responsive Shared Page". The amount,
// reference and return addresses are fixed here, on our server — the
// visitor cannot alter them. Returns { accessCode, url }.
async function ewayCreatePayment(cfg, { order, event }) {
  const nm = splitName(order.purchaser_name);
  const desc = `${order.quantity} ticket${order.quantity === 1 ? '' : 's'} - ${event.name}`.slice(0, 64);
  const res = await ewayCall(cfg, 'POST', '/AccessCodesShared', {
    Customer: { FirstName: nm.first.slice(0, 50), LastName: nm.last.slice(0, 50), Email: order.purchaser_email, Country: 'au' },
    Payment:  {
      TotalAmount: order.total_cents,
      InvoiceReference: order.order_no,
      InvoiceDescription: desc,
      CurrencyCode: 'AUD',
    },
    RedirectUrl: `${cfg.site}/ticket-result.html`,
    CancelUrl:   `${cfg.site}/tickets.html`,
    Method: 'ProcessPayment',
    TransactionType: 'Purchase',
    CustomerReadOnly: true,
    HeaderText: 'Pathfinder Music Lessons',
    LogoUrl: `${cfg.site}/Logo_-_long.png`,
    Language: 'EN',
    DeviceID: 'pathfinder-tickets',
  });
  const j = res.json;
  if (!res.ok || !j || j.Errors || !j.AccessCode || !j.SharedPaymentUrl) {
    const err = new Error(`eWAY did not create the payment page (HTTP ${res.status}${j?.Errors ? ', ' + j.Errors : ''}).`);
    err.ewayErrors = j?.Errors ?? null;
    throw err;
  }
  return { accessCode: j.AccessCode, url: j.SharedPaymentUrl };
}

// Ask eWAY what became of an access code.
async function ewayGetResult(cfg, accessCode) {
  let res = await ewayCall(cfg, 'GET', `/AccessCode/${encodeURIComponent(accessCode)}`);
  if (!res.ok) {
    res = await ewayCall(cfg, 'POST', '/GetAccessCodeResult', { AccessCode: accessCode });
  }
  if (!res.ok || !res.json) {
    throw new Error(`eWAY result lookup failed (HTTP ${res.status}).`);
  }
  const j = res.json;
  const code = String(j.ResponseCode ?? '').trim();
  const txn  = j.TransactionID;
  const attempted = !!(code || (txn && Number(txn) !== 0));
  const approved = j.TransactionStatus === true && (code === '' || APPROVED_CODES.includes(code));
  const total = Number(j.TotalAmount ?? j.Payment?.TotalAmount);
  return {
    approved,
    attempted,
    code,
    message: String(j.ResponseMessage ?? '').trim(),
    txnId: txn ? String(txn) : null,
    totalCents: Number.isFinite(total) ? total : null,
    invoiceRef: j.InvoiceReference ?? j.Payment?.InvoiceReference ?? null,
    errors: j.Errors || null,
  };
}

// ------------------------------------------------------------
// Settle an order: the ONE place that decides whether tickets exist.
//
// Returns { state, message?, issued? }
//   paid       tickets exist (issued = true if THIS call created them)
//   failed     eWAY declined / the payment did not match the order
//   pending    eWAY has no payment attempt for it (yet)
//   refunded   already refunded
// Throws when eWAY can't be reached — the caller treats that as "still
// confirming" and the scheduled job tries again.
// ------------------------------------------------------------
async function settleOrder(cfg, db, order) {
  if (order.status === 'paid')     return { state: 'paid', issued: false };
  if (order.status === 'refunded') return { state: 'refunded' };
  if (!order.eway_access_code)     return { state: 'pending' };

  const r = await ewayGetResult(cfg, order.eway_access_code);
  const now = new Date().toISOString();

  if (r.approved) {
    const problems = [];
    if (r.totalCents !== order.total_cents) problems.push(`amount paid ${r.totalCents === null ? 'unknown' : money(r.totalCents)} ≠ order total ${money(order.total_cents)}`);
    if (r.invoiceRef && r.invoiceRef !== order.order_no) problems.push(`invoice reference ${r.invoiceRef} ≠ ${order.order_no}`);
    if (problems.length) {
      await db.patch(`ticket_orders?id=eq.${order.id}&status=in.(pending,failed,abandoned)`, {
        status: 'failed',
        eway_transaction_id: r.txnId, eway_response_code: r.code,
        eway_message: r.message.slice(0, 300),
        status_note: ('Approved by eWAY but not issued: ' + problems.join('; ')).slice(0, 500),
        last_checked_at: now,
      });
      return { state: 'failed', review: true, message: 'We could not match your payment to this order.' };
    }
    const issued = await db.rpc('ticket_issue_order', {
      p_order: order.id, p_txn: r.txnId, p_response: r.code, p_message: r.message || 'Approved',
    });
    return { state: 'paid', issued: issued === true };
  }

  if (r.attempted) {
    // declined (or otherwise not approved)
    await db.patch(`ticket_orders?id=eq.${order.id}&status=eq.pending`, {
      status: 'failed',
      eway_transaction_id: r.txnId, eway_response_code: r.code,
      eway_message: (r.message || r.errors || 'Not approved').toString().slice(0, 300),
      last_checked_at: now,
    });
    return { state: 'failed', message: 'Your payment was not approved.' };
  }

  await db.patch(`ticket_orders?id=eq.${order.id}&status=eq.pending`, { last_checked_at: now });
  return { state: 'pending' };
}

// ------------------------------------------------------------
// The tickets as a PDF (one page per seat) with a QR code on each
// ------------------------------------------------------------
async function buildTicketsPdf({ order, event, tickets, site }) {
  const { PDFDocument, StandardFonts, rgb } = require('pdf-lib');
  const QRCode = require('qrcode');

  const pdf = await PDFDocument.create();
  pdf.setTitle(`Tickets ${order.order_no} — ${event.name}`);
  pdf.setAuthor('Pathfinder Music Lessons');
  const helv  = await pdf.embedFont(StandardFonts.Helvetica);
  const bold  = await pdf.embedFont(StandardFonts.HelveticaBold);
  const mono  = await pdf.embedFont(StandardFonts.CourierBold);

  const W = 595.28, H = 297.64;
  const ORANGE = rgb(0.910, 0.286, 0.118);
  const CHAR   = rgb(0.110, 0.110, 0.118);
  const GREY   = rgb(0.45, 0.45, 0.47);
  const LIGHT  = rgb(0.86, 0.86, 0.88);
  const X0 = 28, COL_R = W - 200;            // left column right edge / stub divider

  // Standard fonts only encode Latin-1-ish text; anything else prints as "?"
  const safeText = (font, s) => {
    const set = new Set(font.getCharacterSet());
    let out = '';
    for (const ch of String(s ?? '').replace(/[\r\n\t]+/g, ' ')) out += set.has(ch.codePointAt(0)) ? ch : '?';
    return out;
  };
  const wrap = (font, text, size, maxW, maxLines) => {
    const words = safeText(font, text).split(' ').filter(Boolean);
    const lines = []; let cur = '';
    for (const w of words) {
      const t = cur ? cur + ' ' + w : w;
      if (font.widthOfTextAtSize(t, size) <= maxW) { cur = t; continue; }
      if (cur) lines.push(cur);
      cur = w;
      while (font.widthOfTextAtSize(cur, size) > maxW && cur.length > 1) {   // a single very long word
        let k = cur.length - 1;
        while (k > 1 && font.widthOfTextAtSize(cur.slice(0, k), size) > maxW) k--;
        lines.push(cur.slice(0, k)); cur = cur.slice(k);
      }
    }
    if (cur) lines.push(cur);
    if (lines.length > maxLines) {
      lines.length = maxLines;
      let last = lines[maxLines - 1];
      while (last.length > 1 && font.widthOfTextAtSize(last + '...', size) > maxW) last = last.slice(0, -1);
      lines[maxLines - 1] = last + '...';
    }
    return lines;
  };

  const when = `${formatDateLong(event.event_date)}  ·  ${formatTime(event.start_time)}`;
  const venue = [event.venue_name, event.venue_address].filter(Boolean).join(', ');
  const info = event.ticket_info || 'Please show this ticket on your phone or printed. Each ticket admits one person and can be used once.';

  for (const t of tickets) {
    const page = pdf.addPage([W, H]);
    const text = (s, x, y, size, font = helv, color = CHAR) =>
      page.drawText(safeText(font, s), { x, y, size, font, color });

    // header band
    page.drawRectangle({ x: 0, y: H - 52, width: W, height: 52, color: CHAR });
    page.drawRectangle({ x: 0, y: H - 55, width: W, height: 3, color: ORANGE });
    text('PATHFINDER MUSIC LESSONS', X0, H - 32, 12, bold, ORANGE);
    const admit = 'ADMIT ONE';
    text(admit, W - X0 - bold.widthOfTextAtSize(admit, 12), H - 32, 12, bold, rgb(1, 1, 1));

    // event
    let y = H - 86;
    const nameLines = wrap(bold, event.name, 19, COL_R - X0 - 14, 2);
    for (const line of nameLines) { text(line, X0, y, 19, bold); y -= 23; }
    y += 3;
    y -= 14;
    for (const line of wrap(bold, when, 12, COL_R - X0 - 14, 1)) { text(line, X0, y, 12, bold, ORANGE); y -= 15; }
    // a two-line event name leaves room for one line of venue only
    for (const line of wrap(helv, venue, 10, COL_R - X0 - 14, nameLines.length > 1 ? 1 : 2)) { text(line, X0, y, 10, helv, GREY); y -= 13; }

    // performer + purchaser
    y -= 8;
    page.drawLine({ start: { x: X0, y: y + 4 }, end: { x: COL_R - 14, y: y + 4 }, thickness: 0.6, color: LIGHT });
    y -= 12;
    text('PERFORMER', X0, y, 7.5, bold, ORANGE);
    y -= 17;
    let size = 16;
    const perf = safeText(bold, order.performer_name);
    while (size > 9 && bold.widthOfTextAtSize(perf, size) > COL_R - X0 - 14) size -= 0.5;
    const perfLines = wrap(bold, perf, size, COL_R - X0 - 14, 1);
    text(perfLines[0] ?? '', X0, y, size, bold);
    y -= 22;
    text('PURCHASED BY', X0, y, 7.5, bold, ORANGE);
    y -= 14;
    text(wrap(helv, order.purchaser_name, 11, COL_R - X0 - 14, 1)[0] ?? '', X0, y, 11);

    // footer
    text(`Ticket ${t.seq} of ${order.quantity}   ·   Order ${order.order_no}`, X0, 33, 8.5, bold, GREY);
    let fy = 21;
    for (const line of wrap(helv, info, 7.5, COL_R - X0 - 14, 2)) { text(line, X0, fy, 7.5, helv, GREY); fy -= 9.5; }

    // tear-off stub
    for (let yy = 14; yy < H - 66; yy += 9) {
      page.drawLine({ start: { x: COL_R, y: yy }, end: { x: COL_R, y: yy + 4 }, thickness: 0.8, color: LIGHT });
    }
    const qrPng = await QRCode.toBuffer(`${site}/portal/ticket-sales.html?ticket=${t.ticket_no}`, {
      errorCorrectionLevel: 'M', margin: 1, scale: 8,
    });
    const img = await pdf.embedPng(qrPng);
    const cx = COL_R + (W - COL_R) / 2;
    const qs = 138;
    page.drawImage(img, { x: cx - qs / 2, y: H - 66 - qs - 8, width: qs, height: qs });
    const no = t.ticket_no;
    text(no, cx - mono.widthOfTextAtSize(no, 13) / 2, 52, 13, mono);
    const hint = 'Scan at the door';
    text(hint, cx - helv.widthOfTextAtSize(hint, 8) / 2, 38, 8, helv, GREY);
  }
  return Buffer.from(await pdf.save());
}

// ------------------------------------------------------------
// The email
// ------------------------------------------------------------
function ticketEmailText({ order, event, from }) {
  // visitor-typed text goes through the markdown-ish email template, so
  // neutralise its special characters (** and [ ])
  const safe = (t) => String(t ?? '').replace(/\*+/g, '').replace(/\[/g, '(').replace(/\]/g, ')');
  const n = order.quantity;
  const lines = [];
  lines.push(`Hi ${safe(firstName(order.purchaser_name))},`);
  lines.push('');
  lines.push(`Thank you — your payment has been received. Your ${n === 1 ? 'ticket is' : `${n} tickets are`} attached to this email as a PDF.`);
  lines.push('');
  const details = [
    `Event: ${safe(event.name)}`,
    `Date: ${formatDateLong(event.event_date)}`,
    `Starts: ${formatTime(event.start_time)}`,
  ];
  if (event.venue_name || event.venue_address) {
    details.push(`Venue: ${safe([event.venue_name, event.venue_address].filter(Boolean).join(', '))}`);
  }
  details.push(`Performer: ${safe(order.performer_name)}`);
  details.push(`Tickets: ${n} · ${money(order.total_cents)} paid · Order ${order.order_no}`);
  lines.push(`**${details.join('\n')}**`);
  lines.push('');
  lines.push(n === 1
    ? `Show the ticket at the door, on your phone or printed. Its QR code is scanned on entry, and it can be used once.`
    : `Each seat has its own page and its own QR code, scanned on entry — a ticket can be used once. Show them on your phone or print them out. If your group will arrive separately, forward each person their own page.`);
  if (event.ticket_info) { lines.push(''); lines.push(safe(event.ticket_info)); }
  lines.push('');
  lines.push(`Can't find your tickets later, or something doesn't look right? Just reply to this email and quote order ${order.order_no}.`);
  lines.push('');
  lines.push(`We're looking forward to seeing ${safe(order.performer_name)} on stage!`);
  lines.push('');
  lines.push('The team at Pathfinder Music Lessons');
  return lines.join('\n');
}

// Build the PDF and email it. Records the outcome on the order.
// Never throws — returns { ok, error? }.
async function sendOrderEmail(cfg, db, order, event, { by = null, to = null } = {}) {
  const subject = `Your tickets: ${event.name}`.slice(0, 150);
  const text = ticketEmailText({ order, event, from: cfg.from });
  const recipient = (to || order.purchaser_email).trim();
  const bcc = cfg.bcc.filter(b => b.toLowerCase() !== recipient.toLowerCase());
  let resendId = null;
  try {
    if (!isValidEmail(recipient)) throw new Error('The email address is not valid.');
    const tickets = await db.ticketsOf(order.id);
    if (!tickets.length) throw new Error('This order has no tickets yet.');
    const pdf = await buildTicketsPdf({ order, event, tickets, site: cfg.site });

    const payload = {
      from:     `Pathfinder Music Lessons <${cfg.from}>`,
      to:       [recipient],
      reply_to: cfg.from,
      subject,
      html:     emailTemplate(text, cfg.from, null),
      text:     text.replace(/\*\*/g, ''),
      attachments: [{ filename: `Pathfinder-Tickets-${order.order_no}.pdf`, content: pdf.toString('base64') }],
    };
    if (bcc.length) payload.bcc = bcc;

    const r = await fetch(cfg.resendUrl, {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${cfg.resendKey}`,
        // the return page, the scheduled job and a double-click can all
        // reach this point for the same order within moments of each other:
        // one email per attempt number per 5-minute window (a later retry
        // after a failure gets a fresh key)
        'Idempotency-Key': `tickets-${order.id}-${(order.send_count ?? 0) + 1}-${Math.floor(Date.now() / 300000)}-${crypto.createHash('sha1').update(recipient).digest('hex').slice(0, 8)}`,
      },
      body: JSON.stringify(payload),
    });
    const rj = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(rj?.message || rj?.error || `Resend returned ${r.status}`);
    resendId = rj?.id ?? null;

    await db.patch(`ticket_orders?id=eq.${order.id}`, {
      emailed_at: new Date().toISOString(), emailed_to: recipient, email_error: null,
      send_count: (order.send_count ?? 0) + 1,
      ...(to ? { purchaser_email: recipient } : {}),
    }).catch(() => {});
    await db.log({
      sent_by: by, subject, body: text.replace(/\*\*/g, ''), recipient_mode: 'tickets',
      recipient_count: 1, recipients: [{ name: recipient, addresses: [recipient], resend_id: resendId }],
      bcc: bcc.join(', '), status: 'sent', error: null,
    });
    return { ok: true, resendId };
  } catch (err) {
    const msg = String(err.message || err).slice(0, 500);
    await db.patch(`ticket_orders?id=eq.${order.id}`, { email_error: msg }).catch(() => {});
    await db.log({
      sent_by: by, subject, body: text.replace(/\*\*/g, ''), recipient_mode: 'tickets',
      recipient_count: 0, recipients: [{ name: recipient, addresses: [recipient], resend_id: null }],
      bcc: bcc.join(', '), status: 'failed', error: msg,
    });
    return { ok: false, error: msg };
  }
}

// ------------------------------------------------------------
// Settle an order and, if THIS call is the one that issued the tickets,
// email them. Shared by the return page, the admin "Check payment"
// button and the scheduled job.
// ------------------------------------------------------------
async function settleAndDeliver(cfg, db, order) {
  const res = await settleOrder(cfg, db, order);
  if (res.state === 'paid' && res.issued) {
    const fresh = await db.orderById(order.id);
    const ev = await db.event(order.event_id);
    res.email = await sendOrderEmail(cfg, db, fresh, ev);
  }
  return res;
}

module.exports = {
  TZ, MAX_PER_ORDER, APPROVED_CODES,
  ConfigError, loadConfig, json, isUuid, isAccessCode, normAccessCode, isValidEmail, cleanText, maskEmail,
  newOrderNo, randomCode, todayMelbourne, money, formatDateLong, formatTime, firstName, onSale, EVENT_COLS,
  makeDb, canManage,
  ewayCreatePayment, ewayGetResult,
  settleOrder, settleAndDeliver, buildTicketsPdf, sendOrderEmail, ticketEmailText,
};

// ============================================================
// Email shell — copied verbatim from send-voucher.js / send-email.js so
// a ticket email looks exactly like every other Pathfinder email.
// ============================================================
function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// Plain text → branded HTML email.
// A paragraph wrapped entirely in **double asterisks** becomes a
// highlighted callout block; **bold** works inline elsewhere; a
// [label](url) works inline anywhere, same syntax as markdown links; a
// paragraph where every line starts with "- " becomes a real bullet list
// (each line may itself contain a [label](url)).
//
// `studioAddress` is the sending studio's own postal address, resolved
// by the caller from the `studios` table — the same field admins edit on
// the Studios page. It used to be a hardcoded line naming both studios'
// addresses regardless of which one actually sent the email. When no
// address is on file for this studio, the line is left out rather than
// printed blank.
function emailTemplate(bodyText, studioEmail, studioAddress) {
  const inlineBold = (s) => s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  const inlineLink = (s) => s.replace(/\[([^\]]+)\]\(([^)]+)\)/g,
    '<a href="$2" style="color:#E8491E;text-decoration:none;">$1</a>');
  const formatInline = (s) => inlineBold(inlineLink(s));

  const isBulletBlock = (t) => {
    const lines = t.split('\n').map(l => l.trim()).filter(Boolean);
    return lines.length > 0 && lines.every(l => l.startsWith('- '));
  };

  const para = (p) => {
    const t = p.trim();
    // A paragraph of only dashes is a section break
    if (/^-{3,}$/.test(t)) {
      return '<div style="border-top:1px solid #e5e5e5;margin:22px 0 18px;"></div>';
    }
    // A paragraph where every line is "- something" is a bullet list
    if (isBulletBlock(t)) {
      const items = t.split('\n').map(l => l.trim()).filter(Boolean);
      return `<ul style="margin:0 0 14px;padding-left:20px;">` +
        items.map(l => `<li style="margin:0 0 6px;line-height:1.5;">${formatInline(l.slice(2))}</li>`).join('') +
        `</ul>`;
    }
    // A short ALL-CAPS line is a heading
    if (/^[A-Z][A-Z0-9 &'’,.\-\/]{2,40}$/.test(t) && !t.includes('\n')) {
      return `<p style="margin:0 0 10px;font-size:12px;font-weight:bold;letter-spacing:0.08em;
              text-transform:uppercase;color:#E8491E;">${t}</p>`;
    }
    return `<p style="margin:0 0 14px;">${formatInline(t.replace(/\n/g, '<br>'))}</p>`;
  };

  const callout = (inner) =>
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 16px;">
      <tr>
        <td style="width:4px;background:#E8491E;border-radius:2px 0 0 2px;">&nbsp;</td>
        <td style="background:#f5f5f7;padding:14px 16px;border-radius:0 2px 2px 0;font-size:15px;line-height:1.6;color:#1c1c1e;">
          ${inner.split(/\n\s*\n/).map(b =>
            `<div style="margin:0 0 10px;">${formatInline(b.trim().replace(/\n/g, '<br>'))}</div>`
          ).join('')}
        </td>
      </tr>
    </table>`;

  // A callout may span blank lines, so it is extracted from the whole
  // body before paragraphs are split. Matching per paragraph meant a
  // multi-paragraph block never matched and its asterisks showed
  // through literally.
  const src = escapeHtml(bodyText);
  let html = '';
  let last = 0;
  const re = /\*\*([\s\S]+?)\*\*(?=\s*(?:\n\s*\n|$))/g;
  let m;

  while ((m = re.exec(src)) !== null) {
    // Only treat it as a block when it starts its own paragraph —
    // otherwise **bold** mid-sentence would be swallowed.
    const before = src.slice(last, m.index);
    const startsBlock = /(^|\n\s*\n)\s*$/.test(before);
    if (!startsBlock) continue;

    before.split(/\n\s*\n/).filter(p => p.trim()).forEach(p => { html += para(p); });
    html += callout(m[1]);
    last = m.index + m[0].length;
  }

  src.slice(last).split(/\n\s*\n/).filter(p => p.trim()).forEach(p => { html += para(p); });

  return `<!DOCTYPE html>
<html><body style="margin:0;padding:0;background:#f5f5f7;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f7;padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:560px;background:#ffffff;border-radius:8px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;">
        <tr><td style="background:#1c1c1e;padding:18px 24px;border-bottom:3px solid #E8491E;">
          <div style="color:#E8491E;font-size:11px;letter-spacing:0.12em;text-transform:uppercase;font-weight:bold;">
            Pathfinder Music Lessons
          </div>
        </td></tr>
        <tr><td style="padding:24px;color:#1c1c1e;font-size:15px;line-height:1.65;">
          ${html}
        </td></tr>
        <tr><td style="padding:16px 24px;border-top:1px solid #eeeeee;color:#999999;font-size:12px;line-height:1.6;">
          Pathfinder Music Lessons · <a href="mailto:${studioEmail}" style="color:#E8491E;text-decoration:none;">${studioEmail}</a><br>
          ${studioAddress ? `${escapeHtml(studioAddress)}<br>` : ''}
          <a href="https://www.pathfindermusiclessons.com.au" style="color:#999999;">pathfindermusiclessons.com.au</a>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}
