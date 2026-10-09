// ============================================================
// Netlify Function: voucher-checkout   (public)
//
// Turns the voucher order form into a payment:
//   1. validates the form and takes the price ON THE SERVER from
//      VOUCHER_TYPES (the browser never says what to charge);
//   2. stores the order as 'pending';
//   3. asks eWAY for a hosted payment page for exactly that amount and
//      returns its address for the browser to go to.
//
// The voucher is NOT issued here — only voucher-confirm (and the
// scheduled reconcile job), after eWAY itself confirms the payment.
//
// POST { type, purchaserName, purchaserEmail, recipientName,
//        recipientEmail?, subject?, message?, website }
//        website = hidden "honeypot" field; real visitors leave it empty
// POST { retryAccessCode }   a declined payment: start again with the
//        same details (as a NEW order, so every eWAY payment page maps
//        to exactly one order)
// → { url, orderNo }
// ============================================================
'use strict';
const crypto = require('crypto');
const V = require('./lib/vouchers');
const T = V.T;

const RATE_WINDOW_MIN = 10;
const RATE_MAX_ORDERS = 8;      // orders started per address in that window

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return T.json(405, { error: 'Method not allowed' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return T.json(400, { error: 'Invalid request.' }); }

  let cfg;
  try { cfg = V.loadConfig(); }
  catch (e) { console.error('voucher-checkout:', e.message); return T.json(500, { error: 'Voucher sales are temporarily unavailable. Please try again later.' }); }
  const db = V.makeDb(cfg);

  // bots fill every field; people never see this one
  if (body.website) return T.json(200, { url: `${cfg.site}/gift-vouchers.html`, orderNo: 'VO-AAAAAA' });

  try {
    // ---- the details of the order ----
    let fields;
    if (body.retryAccessCode !== undefined) {
      const retryCode = T.normAccessCode(body.retryAccessCode);
      if (!T.isAccessCode(retryCode)) return T.json(400, { error: 'Invalid request.' });
      const prev = await db.orderByCode(retryCode);
      if (!prev) return T.json(404, { error: 'We could not find that order.' });
      if (prev.status === 'paid') return T.json(409, { error: 'That order has already been paid.', code: 'already_paid' });
      if (prev.status === 'refunded') return T.json(409, { error: 'That order was refunded.' });
      // re-validated like a fresh order, so the price is today's price
      const again = V.parseOrder({
        type: prev.voucher_type, purchaserName: prev.purchaser_name, purchaserEmail: prev.purchaser_email,
        recipientName: prev.recipient_name, recipientEmail: prev.recipient_email, subject: prev.subject, message: prev.message,
      });
      if (again.error) return T.json(400, { error: again.error });
      fields = again.value;
    } else {
      const parsed = V.parseOrder(body);
      if (parsed.error) return T.json(400, { error: parsed.error });
      fields = parsed.value;
    }

    // ---- slow down floods (per network address) ----
    const ip = String(event.headers?.['x-nf-client-connection-ip'] || event.headers?.['x-forwarded-for'] || '').split(',')[0].trim();
    const ipHash = ip
      ? crypto.createHash('sha256').update(ip + '|' + cfg.sbKey.slice(-12)).digest('hex').slice(0, 24)
      : null;
    if (ipHash) {
      const since = new Date(Date.now() - RATE_WINDOW_MIN * 60000).toISOString();
      const recent = await db.get(`voucher_orders?ip_hash=eq.${ipHash}&created_at=gte.${encodeURIComponent(since)}&select=id&limit=${RATE_MAX_ORDERS}`);
      if (recent.length >= RATE_MAX_ORDERS) {
        return T.json(429, { error: 'Too many attempts from your connection. Please wait a few minutes and try again.' });
      }
    }

    // ---- the order ----
    let order = null;
    for (let attempt = 0; attempt < 6 && !order; attempt++) {
      try {
        order = await db.insert('voucher_orders', { order_no: V.newOrderNo(), ...fields, ip_hash: ipHash });
      } catch (e) {
        if (e.status !== 409) throw e;          // order number clash → try another
      }
    }
    if (!order) throw new Error('Could not allocate an order number.');

    // ---- eWAY payment page ----
    let pay;
    try {
      pay = await V.ewayCreatePayment(cfg, order);
    } catch (e) {
      console.error('voucher-checkout: eWAY', order.order_no, e.message);
      await db.patch(`voucher_orders?id=eq.${order.id}&status=eq.pending`, {
        status: 'failed', status_note: ('eWAY refused to start the payment: ' + e.message).slice(0, 500),
      }).catch(() => {});
      return T.json(502, { error: 'We could not start the payment just now. Nothing has been charged — please try again in a minute.' });
    }
    await db.patch(`voucher_orders?id=eq.${order.id}`, { eway_access_code: pay.accessCode });

    return T.json(200, { url: pay.url, orderNo: order.order_no });
  } catch (err) {
    console.error('voucher-checkout:', err.message);
    return T.json(500, { error: 'Something went wrong on our side. Nothing has been charged — please try again.' });
  }
};
