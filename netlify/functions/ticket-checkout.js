// ============================================================
// Netlify Function: ticket-checkout   (public)
//
// Turns the order form into a payment:
//   1. validates the form and works out the total ON THE SERVER from
//      the event's price (the browser never says what to charge);
//   2. stores the order as 'pending';
//   3. asks eWAY for a hosted payment page for exactly that amount and
//      returns its address for the browser to go to.
//
// Tickets are NOT issued here — only ticket-confirm (and the scheduled
// reconcile job), after eWAY itself confirms the payment.
//
// POST { eventId, name, email, performer, quantity, website }
//        website = hidden "honeypot" field; real visitors leave it empty
// POST { retryAccessCode }   a declined payment: start again with the
//        same details (as a NEW order, so every eWAY payment page maps
//        to exactly one order)
// → { url, orderNo }
// ============================================================
'use strict';
const crypto = require('crypto');
const T = require('./lib/tickets');

const RATE_WINDOW_MIN = 10;
const RATE_MAX_ORDERS = 8;      // orders started per address in that window

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return T.json(405, { error: 'Method not allowed' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return T.json(400, { error: 'Invalid request.' }); }

  let cfg;
  try { cfg = T.loadConfig(); }
  catch (e) { console.error('ticket-checkout:', e.message); return T.json(500, { error: 'Ticket sales are temporarily unavailable. Please try again later.' }); }
  const db = T.makeDb(cfg);

  // bots fill every field; people never see this one
  if (body.website) return T.json(200, { url: `${cfg.site}/tickets.html`, orderNo: 'TO-AAAAAA' });

  try {
    // ---- the details of the order ----
    let ev, name, email, performer, quantity;

    if (body.retryAccessCode !== undefined) {
      const retryCode = T.normAccessCode(body.retryAccessCode);
      if (!T.isAccessCode(retryCode)) return T.json(400, { error: 'Invalid request.' });
      const prev = await db.orderByCode(retryCode);
      if (!prev) return T.json(404, { error: 'We could not find that order.' });
      if (prev.status === 'paid') return T.json(409, { error: 'That order has already been paid.', code: 'already_paid' });
      if (prev.status === 'refunded') return T.json(409, { error: 'That order was refunded.' });
      ev = await db.event(prev.event_id);
      name = prev.purchaser_name; email = prev.purchaser_email;
      performer = prev.performer_name; quantity = prev.quantity;
    } else {
      if (!T.isUuid(body.eventId)) return T.json(400, { error: 'Please choose an event.' });
      ev = await db.event(body.eventId);
      name      = T.cleanText(body.name, 120);
      email     = String(body.email ?? '').trim().toLowerCase();
      performer = T.cleanText(body.performer, 120);
      quantity  = Number(body.quantity);
      const bad = [];
      if (!name) bad.push('your name');
      if (!T.isValidEmail(email)) bad.push('a valid email address');
      if (!performer) bad.push('the name of the performer you are coming to see');
      if (!Number.isInteger(quantity) || quantity < 1 || quantity > T.MAX_PER_ORDER) {
        bad.push(`a number of tickets from 1 to ${T.MAX_PER_ORDER}`);
      }
      if (bad.length) return T.json(400, { error: 'Please enter ' + bad.join(', ') + '.' });
    }

    if (!T.onSale(ev)) {
      return T.json(409, { error: 'Sorry — tickets for this event are not on sale.', code: 'not_on_sale' });
    }

    // ---- slow down floods (per network address) ----
    const ip = String(event.headers?.['x-nf-client-connection-ip'] || event.headers?.['x-forwarded-for'] || '').split(',')[0].trim();
    const ipHash = ip
      ? crypto.createHash('sha256').update(ip + '|' + cfg.sbKey.slice(-12)).digest('hex').slice(0, 24)
      : null;
    if (ipHash) {
      const since = new Date(Date.now() - RATE_WINDOW_MIN * 60000).toISOString();
      const recent = await db.get(`ticket_orders?ip_hash=eq.${ipHash}&created_at=gte.${encodeURIComponent(since)}&select=id&limit=${RATE_MAX_ORDERS}`);
      if (recent.length >= RATE_MAX_ORDERS) {
        return T.json(429, { error: 'Too many attempts from your connection. Please wait a few minutes and try again.' });
      }
    }

    // ---- the order (price from the event, total computed here) ----
    const unit = ev.ticket_price_cents;
    let order = null;
    for (let attempt = 0; attempt < 6 && !order; attempt++) {
      try {
        order = await db.insert('ticket_orders', {
          order_no: T.newOrderNo(), event_id: ev.id,
          purchaser_name: name, purchaser_email: email, performer_name: performer,
          quantity, unit_price_cents: unit, total_cents: unit * quantity,
          ip_hash: ipHash,
        });
      } catch (e) {
        if (e.status !== 409) throw e;          // order number clash → try another
      }
    }
    if (!order) throw new Error('Could not allocate an order number.');

    // ---- eWAY payment page ----
    let pay;
    try {
      pay = await T.ewayCreatePayment(cfg, { order, event: ev });
    } catch (e) {
      console.error('ticket-checkout: eWAY', order.order_no, e.message);
      await db.patch(`ticket_orders?id=eq.${order.id}&status=eq.pending`, {
        status: 'failed', status_note: ('eWAY refused to start the payment: ' + e.message).slice(0, 500),
      }).catch(() => {});
      return T.json(502, { error: 'We could not start the payment just now. Nothing has been charged — please try again in a minute.' });
    }
    await db.patch(`ticket_orders?id=eq.${order.id}`, { eway_access_code: pay.accessCode });

    return T.json(200, { url: pay.url, orderNo: order.order_no });
  } catch (err) {
    console.error('ticket-checkout:', err.message);
    return T.json(500, { error: 'Something went wrong on our side. Nothing has been charged — please try again.' });
  }
};
