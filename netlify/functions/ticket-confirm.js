// ============================================================
// Netlify Function: ticket-confirm   (public)
//
// Called by ticket-result.html when eWAY sends the visitor back. The
// address carries only eWAY's AccessCode; this function looks the
// order up by it and asks eWAY (server to server) whether the payment
// was approved. If so it issues the tickets and emails the PDF — once,
// however many times this is called.
//
// POST { accessCode }
// → { state: paid | failed | pending | refunded, message?, retryable?,
//     order: { orderNo, quantity, performer, purchaserName, emailMasked, totalCents },
//     event: { name, date, startTime, venueName, venueAddress },
//     emailed }
// ============================================================
'use strict';
const T = require('./lib/tickets');

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return T.json(405, { error: 'Method not allowed' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return T.json(400, { error: 'Invalid request.' }); }
  const accessCode = T.normAccessCode(body.accessCode);
  if (!T.isAccessCode(accessCode)) return T.json(400, { error: 'This page needs a payment reference. Please use the link from the payment page.' });

  let cfg;
  try { cfg = T.loadConfig(); }
  catch (e) { console.error('ticket-confirm:', e.message); return T.json(500, { error: 'Ticket sales are temporarily unavailable.' }); }
  const db = T.makeDb(cfg);

  try {
    const order = await db.orderByCode(accessCode);
    if (!order) return T.json(404, { error: 'We could not find an order for this payment.' });

    let res;
    try {
      res = await T.settleAndDeliver(cfg, db, order);
    } catch (e) {
      // eWAY unreachable or odd reply: tell the visitor we are still checking;
      // the scheduled job keeps trying, so a paid order is never lost
      console.error('ticket-confirm: settle', order.order_no, e.message);
      res = { state: 'pending', message: 'We are still confirming your payment.' };
    }

    const [fresh, ev] = await Promise.all([db.orderById(order.id), db.event(order.event_id)]);
    return T.json(200, {
      state: res.state,
      message: res.message ?? null,
      retryable: res.state === 'failed' && !res.review,
      emailed: !!fresh?.emailed_at,
      order: {
        orderNo: fresh.order_no, quantity: fresh.quantity, performer: fresh.performer_name,
        purchaserName: fresh.purchaser_name, emailMasked: T.maskEmail(fresh.purchaser_email),
        totalCents: fresh.total_cents,
      },
      event: {
        name: ev.name, date: ev.event_date, startTime: ev.start_time,
        venueName: ev.venue_name, venueAddress: ev.venue_address,
      },
    });
  } catch (err) {
    console.error('ticket-confirm:', err.message);
    return T.json(500, { error: 'We could not check your payment just now. If you were charged, your tickets will be emailed to you shortly — or contact us with your receipt.' });
  }
};
