// ============================================================
// Shared code for the gift-voucher shop
//   voucher-config, voucher-checkout, voucher-confirm, voucher-admin,
//   reconcile-voucher-orders
//
// Built on lib/tickets.js (configuration, the Supabase client, the eWAY
// calls and the branded email shell) so a voucher purchase behaves exactly
// like a ticket purchase:
//
//   * the browser never says what to charge — the price comes from
//     VOUCHER_TYPES below;
//   * a voucher exists only after eWAY's own server says the payment was
//     approved for exactly the order total;
//   * the voucher is created by one atomic database function, so the return
//     page, the scheduled job and the admin "Check payment" button can all
//     race and still issue exactly one.
//
// The voucher PDF is drawn by portal/js/voucher-pdf.js — the SAME file the
// front-desk Vouchers page uses — so an online voucher looks identical to
// one an admin issues by hand.
//
// Optional environment variable
//   VOUCHERS_BCC   comma-separated addresses blind-copied on the purchaser's
//                  email. Default: the email address of every active studio
//                  (the Studios page), so both studios see each sale.
// ============================================================
'use strict';

const crypto = require('crypto');
const T = require('./tickets');

// ------------------------------------------------------------
// THE VOUCHERS ON SALE — the one place their prices live.
// (cents; the website reads them from the voucher-config function)
// ------------------------------------------------------------
const VOUCHER_TYPES = [
  { key: '5-lesson',  title: '5-Lesson Voucher',  lessons: 5,  cents: 24000 },
  { key: '10-lesson', title: '10-Lesson Voucher', lessons: 10, cents: 45600, badge: 'Best Value' },
];

const MAX_NAME    = 120;
const MAX_SUBJECT = 120;
const MAX_MESSAGE = 500;      // what fits on the voucher; the database allows a little more

function voucherType(key) {
  return VOUCHER_TYPES.find(t => t.key === key) || null;
}

// What a visitor sees: the types with the saving over buying the smallest
// voucher repeatedly (so "Save $24" is never typed by hand).
function publicTypes() {
  const base = VOUCHER_TYPES[0];
  return VOUCHER_TYPES.map(t => {
    const save = Math.round(base.cents / base.lessons * t.lessons) - t.cents;
    return {
      key: t.key, title: t.title, lessons: t.lessons, priceCents: t.cents,
      saveCents: t === base || save <= 0 ? 0 : save,
      badge: t.badge || null,
    };
  });
}

const newOrderNo = () => 'VO-' + T.randomCode(6);

// "5-Lesson Voucher for Jo Smith"
const defaultSubject = (type, recipientName) => `${type.title} for ${recipientName}`;

// ------------------------------------------------------------
// input from the order form
// ------------------------------------------------------------
// The voucher PDF can print only Latin text (letters, accents, curly quotes…);
// anything else is dropped. A name made only of unprintable characters would
// print as nothing, so those are refused up front.
function printable(s) {
  return require('../../../portal/js/voucher-pdf.js').clean(s);
}

// A message may have line breaks. No control characters, bounded.
function cleanMessage(s, max) {
  const t = String(s ?? '')
    .normalize('NFC')
    .replace(/\r\n?/g, '\n')
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\u2028\u2029]/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/ ?\n ?/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return [...t].slice(0, max).join('').trim();
}

// → { error } | { value: {...fields to store} }
function parseOrder(body) {
  const type = voucherType(body.type);
  if (!type) return { error: 'Please choose a voucher.' };

  const purchaserName  = T.cleanText(body.purchaserName, MAX_NAME);
  const purchaserEmail = String(body.purchaserEmail ?? '').trim().toLowerCase();
  const recipientName  = T.cleanText(body.recipientName, MAX_NAME);
  let   recipientEmail = String(body.recipientEmail ?? '').trim().toLowerCase();
  const subjectIn      = T.cleanText(body.subject, 400);
  const message        = cleanMessage(body.message, 2000);

  const bad = [];
  if (!purchaserName) bad.push('your name');
  if (!T.isValidEmail(purchaserEmail)) bad.push('a valid email address for yourself');
  if (!recipientName) bad.push('the name of the person the voucher is for');
  if (recipientEmail && !T.isValidEmail(recipientEmail)) bad.push('a valid email address for the recipient (or leave it empty)');
  if (bad.length) return { error: 'Please enter ' + bad.join(', ') + '.' };

  if (!printable(purchaserName) || !printable(recipientName)) {
    return { error: 'Names are printed on the voucher, which can show letters (including accents) but not emoji or other scripts. Please use English letters for the names — you can still add the full details in the personal message if you like.' };
  }
  if (message.length > MAX_MESSAGE) {
    return { error: `Please keep your personal message to ${MAX_MESSAGE} characters or fewer (it is ${message.length}).` };
  }
  const subject = subjectIn || defaultSubject(type, recipientName);
  if ([...subject].length > MAX_SUBJECT) {
    return { error: `Please keep the voucher description to ${MAX_SUBJECT} characters or fewer.` };
  }
  if (!printable(subject)) {
    return { error: 'The voucher description can’t be printed — it needs some English letters or numbers.' };
  }
  // buying it for yourself: one email is enough
  if (recipientEmail && recipientEmail === purchaserEmail) recipientEmail = '';

  return {
    type,
    value: {
      voucher_type: type.key, voucher_title: type.title, subject,
      amount_cents: type.cents,
      purchaser_name: purchaserName, purchaser_email: purchaserEmail,
      recipient_name: recipientName, recipient_email: recipientEmail || null,
      message: message || null,
    },
  };
}

// ------------------------------------------------------------
// database helpers (on top of T.makeDb)
// ------------------------------------------------------------
function makeDb(cfg) {
  const db = T.makeDb(cfg);
  return Object.assign(db, {
    orderById:   (id)   => db.first(`voucher_orders?id=eq.${id}&select=*`),
    orderByCode: (code) => db.first(`voucher_orders?eway_access_code=eq.${encodeURIComponent(code)}&select=*`),
    voucherOf:   (orderId) => db.first(`gift_vouchers?order_id=eq.${orderId}&select=*`),
    // email addresses of the studios that honour a voucher
    async studioEmails() {
      const rows = await db.get('studios?status=eq.active&select=name,email&order=name.asc').catch(() => []);
      return (rows || []).map(r => String(r.email || '').trim().toLowerCase()).filter(T.isValidEmail)
        .filter((e, i, a) => a.indexOf(e) === i);
    },
  });
}

// May this signed-in user manage voucher sales? (any active admin or superuser,
// as for the front-desk voucher register)
const canManage = (user) => !!user && user.status !== 'inactive' && ['admin', 'superuser'].includes(user.role);

// ------------------------------------------------------------
// eWAY
// ------------------------------------------------------------
async function ewayCreatePayment(cfg, order) {
  const nm = T.splitName(order.purchaser_name);
  const res = await T.ewayCall(cfg, 'POST', '/AccessCodesShared', {
    Customer: { FirstName: nm.first.slice(0, 50), LastName: nm.last.slice(0, 50), Email: order.purchaser_email, Country: 'au' },
    Payment: {
      TotalAmount: order.amount_cents,
      InvoiceReference: order.order_no,
      InvoiceDescription: `Gift voucher - ${order.voucher_title}`.slice(0, 64),
      CurrencyCode: 'AUD',
    },
    RedirectUrl: `${cfg.site}/voucher-result.html`,
    CancelUrl:   `${cfg.site}/gift-vouchers.html`,
    Method: 'ProcessPayment',
    TransactionType: 'Purchase',
    CustomerReadOnly: true,
    HeaderText: 'Pathfinder Music Lessons',
    LogoUrl: `${cfg.site}/Logo_-_long.png`,
    Language: 'EN',
    DeviceID: 'pathfinder-vouchers',
  });
  const j = res.json;
  if (!res.ok || !j || j.Errors || !j.AccessCode || !j.SharedPaymentUrl) {
    const err = new Error(`eWAY did not create the payment page (HTTP ${res.status}${j?.Errors ? ', ' + j.Errors : ''}).`);
    err.ewayErrors = j?.Errors ?? null;
    throw err;
  }
  return { accessCode: j.AccessCode, url: j.SharedPaymentUrl };
}

// ------------------------------------------------------------
// Settle an order: the ONE place that decides whether a voucher exists.
// Same contract as tickets.settleOrder:
//   { state: 'paid', issued } | { state: 'failed', review?, message } |
//   { state: 'pending' } | { state: 'refunded' }
// Throws when eWAY can't be reached (callers treat that as "still confirming").
// ------------------------------------------------------------
async function settleOrder(cfg, db, order) {
  if (order.status === 'paid')     return { state: 'paid', issued: false };
  if (order.status === 'refunded') return { state: 'refunded' };
  if (!order.eway_access_code)     return { state: 'pending' };

  const r = await T.ewayGetResult(cfg, order.eway_access_code);
  const now = new Date().toISOString();

  if (r.approved) {
    const problems = [];
    if (r.totalCents !== order.amount_cents) {
      problems.push(`amount paid ${r.totalCents === null ? 'unknown' : T.money(r.totalCents)} ≠ order total ${T.money(order.amount_cents)}`);
    }
    if (r.invoiceRef && r.invoiceRef !== order.order_no) problems.push(`invoice reference ${r.invoiceRef} ≠ ${order.order_no}`);
    if (problems.length) {
      await db.patch(`voucher_orders?id=eq.${order.id}&status=in.(pending,failed,abandoned)`, {
        status: 'failed',
        eway_transaction_id: r.txnId, eway_response_code: r.code,
        eway_message: r.message.slice(0, 300),
        status_note: ('Approved by eWAY but not issued: ' + problems.join('; ')).slice(0, 500),
        last_checked_at: now,
      });
      return { state: 'failed', review: true, message: 'We could not match your payment to this order.' };
    }
    const issued = await db.rpc('voucher_issue_order', {
      p_order: order.id, p_txn: r.txnId, p_response: r.code, p_message: r.message || 'Approved',
    });
    return { state: 'paid', issued: issued === true };
  }

  if (r.attempted) {
    await db.patch(`voucher_orders?id=eq.${order.id}&status=eq.pending`, {
      status: 'failed',
      eway_transaction_id: r.txnId, eway_response_code: r.code,
      eway_message: (r.message || r.errors || 'Not approved').toString().slice(0, 300),
      last_checked_at: now,
    });
    return { state: 'failed', message: 'Your payment was not approved.' };
  }

  await db.patch(`voucher_orders?id=eq.${order.id}&status=eq.pending`, { last_checked_at: now });
  return { state: 'pending' };
}

// ------------------------------------------------------------
// The voucher as a PDF — drawn by the portal's own voucher-pdf.js
// ------------------------------------------------------------
async function buildVoucherPdf(voucher, studioEmails) {
  const { jsPDF } = require('jspdf');
  const PFV = require('../../../portal/js/voucher-pdf.js');
  const assets = require('./voucher-assets');
  const out = await PFV.build({
    voucherNo: voucher.voucher_no, subject: voucher.subject, valueAmount: voucher.value_amount,
    recipientName: voucher.recipient_name, purchaserName: voucher.purchaser_name,
    purchaseDate: String(voucher.purchase_date).slice(0, 10), expiresOn: String(voucher.expires_on).slice(0, 10),
    message: voucher.message,
    studio: { name: 'Pathfinder Music Lessons', emails: studioEmails },
  }, { jsPDF, assets });
  return Buffer.from(out.base64, 'base64');
}

// ------------------------------------------------------------
// The emails
// ------------------------------------------------------------
// visitor-typed text goes through the markdown-ish email template, so
// neutralise its special characters (** and [ ])
const safe = (t) => String(t ?? '').replace(/\*+/g, '').replace(/\[/g, '(').replace(/\]/g, ')').replace(/\s*\n\s*/g, ' ');

function redeemLine(studioEmails) {
  if (!studioEmails.length) return 'reply to this email';
  if (studioEmails.length === 1) return `write to ${studioEmails[0]}`;
  return `write to ${studioEmails.slice(0, -1).join(', ')} or ${studioEmails[studioEmails.length - 1]}`;
}

function purchaserEmailText({ order, voucher, studioEmails }) {
  const L = [];
  const recFirst = safe(T.firstName(order.recipient_name));
  L.push(`Hi ${safe(T.firstName(order.purchaser_name))},`, '');
  L.push(`Thank you — your payment has been received and your gift voucher is ready. It is attached to this email as a PDF.`, '');
  L.push(`**Gift voucher: ${safe(voucher.subject)}\nFor: ${safe(order.recipient_name)}\nVoucher number: ${voucher.voucher_no}\nValid until: ${T.formatDateLong(voucher.expires_on)}\nPaid: ${T.money(order.amount_cents)} AUD · Order ${order.order_no}**`, '');
  if (order.recipient_email) {
    L.push(`We have also emailed the voucher to ${recFirst} at ${safe(order.recipient_email)}${order.message ? ', with your personal message on it' : ''}, so there is nothing more for you to do.`, '');
  } else {
    L.push(`Print it out and wrap it up, or forward this email to ${recFirst} whenever the time is right${order.message ? ' — your personal message is already on the voucher' : ''}.`, '');
  }
  L.push('HOW IT IS REDEEMED', '');
  L.push(`${recFirst} simply needs to ${redeemLine(studioEmails)} and quote the voucher number, and we will find a lesson time that suits. The voucher can be used at either our Kilsyth or Ringwood studio, for any instrument, and is valid for one year from today.`, '');
  L.push(`Something not right, or a question? Just reply to this email and quote order ${order.order_no}.`, '');
  L.push('Thank you for sharing the gift of music!', '');
  L.push('The team at Pathfinder Music Lessons');
  return L.join('\n');
}

function recipientEmailText({ order, voucher, studioEmails }) {
  const L = [];
  const by = safe(order.purchaser_name);
  L.push(`Hi ${safe(T.firstName(order.recipient_name))},`, '');
  L.push(`Great news — ${by} has given you a gift: ${safe(voucher.subject)}!`, '');
  L.push(`Your voucher is attached to this email as a PDF${order.message ? `, with a personal message from ${by} on it` : ''}. Print it out, or just keep it handy on your phone.`, '');
  L.push(`**Voucher: ${safe(voucher.subject)}\nVoucher number: ${voucher.voucher_no}\nValid until: ${T.formatDateLong(voucher.expires_on)}**`, '');
  L.push(`Ready to get started? Just reply to this email or ${redeemLine(studioEmails)}, quote your voucher number, and we will find the perfect lesson time for you. You can have your lessons at either our Kilsyth or Ringwood studio, on any instrument you like.`, '');
  L.push(`We can't wait to make some music with you!`, '');
  L.push('The team at Pathfinder Music Lessons');
  return L.join('\n');
}

const plain = (t) => t.replace(/\*\*/g, '');

async function resendSend(cfg, payload, idemKey) {
  const r = await fetch(cfg.resendUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${cfg.resendKey}`,
      'Idempotency-Key': idemKey,
    },
    body: JSON.stringify(payload),
  });
  const rj = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(rj?.message || rj?.error || `Resend returned ${r.status}`);
  return rj?.id ?? null;
}

// Email a PAID order's voucher: to the purchaser (BCC the studios) and, if the
// purchaser gave an address, to the recipient. Each of the two is sent once —
// unless `force` names it ('purchaser' | 'recipient' | 'both') as an admin's
// deliberate re-send. Records every outcome on the order and the register.
// Never throws → { purchaser, recipient } each { sent?, skipped?, error? }.
async function deliver(cfg, db, order, { force = null, by = null } = {}) {
  const res = { purchaser: { skipped: true }, recipient: { skipped: true } };
  const wantP = force === 'purchaser' || force === 'both' || (!force && !order.purchaser_emailed_at);
  const wantR = !!order.recipient_email &&
                (force === 'recipient' || force === 'both' || (!force && !order.recipient_emailed_at));
  if (!wantP && !wantR) return res;

  let voucher, studioEmails, pdf;
  try {
    voucher = await db.voucherOf(order.id);
    if (!voucher) throw new Error('This order has no voucher yet.');
    if (voucher.status === 'void') throw new Error('This voucher has been voided.');
    studioEmails = await db.studioEmails();
    pdf = await buildVoucherPdf(voucher, studioEmails);
  } catch (err) {
    const msg = String(err.message || err).slice(0, 500);
    if (wantP) res.purchaser = { error: msg };
    if (wantR) res.recipient = { error: msg };
    await db.patch(`voucher_orders?id=eq.${order.id}`, {
      ...(wantP ? { purchaser_email_error: msg } : {}), ...(wantR ? { recipient_email_error: msg } : {}),
      delivery_attempts: (order.delivery_attempts ?? 0) + 1,
    }).catch(() => {});
    return res;
  }

  const attachment = [{ filename: `Pathfinder-Voucher-${voucher.voucher_no}.pdf`, content: pdf.toString('base64') }];
  const window5 = Math.floor(Date.now() / 300000);
  const fields = {};
  let failed = false;

  async function one(who, to, subject, text, bcc, count) {
    const payload = {
      from: `Pathfinder Music Lessons <${cfg.from}>`, to: [to], reply_to: cfg.from, subject,
      html: T.emailTemplate(text, cfg.from, null), text: plain(text), attachments: attachment,
    };
    if (bcc.length) payload.bcc = bcc;
    const key = `voucher-${order.id}-${who[0]}-${count + 1}-${window5}-${crypto.createHash('sha1').update(to).digest('hex').slice(0, 8)}`;
    try {
      const id = await resendSend(cfg, payload, key);
      await db.log({
        sent_by: by, subject, body: plain(text), recipient_mode: 'voucher', recipient_count: 1,
        recipients: [{ name: to, addresses: [to], resend_id: id }], bcc: bcc.join(', '), status: 'sent', error: null,
      });
      return { sent: true, to };
    } catch (err) {
      const msg = String(err.message || err).slice(0, 500);
      await db.log({
        sent_by: by, subject, body: plain(text), recipient_mode: 'voucher', recipient_count: 0,
        recipients: [{ name: to, addresses: [to], resend_id: null }], bcc: bcc.join(', '), status: 'failed', error: msg,
      });
      return { error: msg };
    }
  }

  if (wantP) {
    const bcc = (cfg.vouchersBcc ?? studioEmails).filter(b => b.toLowerCase() !== order.purchaser_email.toLowerCase());
    const text = purchaserEmailText({ order, voucher, studioEmails });
    const r = await one('purchaser', order.purchaser_email, `Your gift voucher: ${voucher.subject}`.slice(0, 150), text, bcc, order.purchaser_send_count ?? 0);
    res.purchaser = r;
    if (r.sent) Object.assign(fields, { purchaser_emailed_at: new Date().toISOString(), purchaser_email_error: null, purchaser_send_count: (order.purchaser_send_count ?? 0) + 1 });
    else { fields.purchaser_email_error = r.error; failed = true; }
  }
  if (wantR) {
    const text = recipientEmailText({ order, voucher, studioEmails });
    const r = await one('recipient', order.recipient_email, `A gift of music from ${order.purchaser_name}`.slice(0, 150), text, [], order.recipient_send_count ?? 0);
    res.recipient = r;
    if (r.sent) Object.assign(fields, { recipient_emailed_at: new Date().toISOString(), recipient_email_error: null, recipient_send_count: (order.recipient_send_count ?? 0) + 1 });
    else { fields.recipient_email_error = r.error; failed = true; }
  }
  if (failed) fields.delivery_attempts = (order.delivery_attempts ?? 0) + 1;
  await db.patch(`voucher_orders?id=eq.${order.id}`, fields).catch(() => {});

  // the front-desk register shows "Sent <date>" from these
  const sentTo = res.recipient.sent ? res.recipient.to : res.purchaser.sent ? res.purchaser.to : null;
  if (sentTo) {
    await db.patch(`gift_vouchers?id=eq.${voucher.id}`, {
      emailed_at: new Date().toISOString(), emailed_to: sentTo, email_error: null,
      send_count: (voucher.send_count ?? 0) + 1,
    }).catch(() => {});
  } else if (failed) {
    await db.patch(`gift_vouchers?id=eq.${voucher.id}`, {
      email_error: (res.purchaser.error || res.recipient.error || '').slice(0, 500),
    }).catch(() => {});
  }
  return res;
}

// Settle an order and, if THIS call is the one that issued the voucher, email it.
async function settleAndDeliver(cfg, db, order) {
  const res = await settleOrder(cfg, db, order);
  if (res.state === 'paid' && res.issued) {
    const fresh = await db.orderById(order.id);
    res.email = await deliver(cfg, db, fresh);
  }
  return res;
}

function loadConfig() {
  const cfg = T.loadConfig();
  const list = String(process.env.VOUCHERS_BCC || '').split(',').map(s => s.trim()).filter(T.isValidEmail);
  cfg.vouchersBcc = list.length ? list : null;     // null → every active studio's address
  return cfg;
}

module.exports = {
  T, VOUCHER_TYPES, MAX_MESSAGE, MAX_NAME, MAX_SUBJECT,
  voucherType, publicTypes, newOrderNo, defaultSubject, parseOrder, cleanMessage,
  loadConfig, makeDb, canManage,
  ewayCreatePayment, settleOrder, settleAndDeliver, deliver, buildVoucherPdf,
  purchaserEmailText, recipientEmailText,
};
