// ============================================================
// Netlify Function: ticket-admin   (signed-in admins only)
//
// The ticket-sales page's actions that need the server:
//   resend   email an order's tickets again (optionally to a corrected
//            address, with corrected names — the PDF is rebuilt)
//   check    ask eWAY again about an unpaid order (a buyer who paid but
//            whose return page never loaded) and issue the tickets if
//            it was approved
//   refund   mark a paid order refunded AFTER you have refunded it in
//            MYeWAY; its tickets become void and cannot be admitted
//
// POST { action, orderId, to?, purchaserName?, performerName?, note? }
//   Authorization: Bearer <the admin's Supabase access token>
// ============================================================
'use strict';
const T = require('./lib/tickets');

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return T.json(405, { error: 'Method not allowed' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return T.json(400, { error: 'Invalid request body' }); }

  let cfg;
  try { cfg = T.loadConfig(); }
  catch (e) { return T.json(500, { error: 'Server misconfigured — ' + e.message }); }
  const db = T.makeDb(cfg);

  try {
    const token = (event.headers?.authorization || event.headers?.Authorization || '').replace(/^Bearer\s+/i, '');
    if (!token) return T.json(401, { error: 'Not signed in.' });
    const user = await db.user(token);
    if (!user) return T.json(401, { error: 'Your session has expired — please sign in again.' });

    if (!T.isUuid(body.orderId)) return T.json(400, { error: 'orderId is required.' });
    const order = await db.orderById(body.orderId);
    if (!order) return T.json(404, { error: 'Order not found.' });
    const ev = await db.event(order.event_id);
    if (!T.canManage(user, ev)) return T.json(403, { error: 'You can’t manage ticket sales for this event.' });

    // ---------------- resend ----------------
    if (body.action === 'resend') {
      if (order.status !== 'paid') return T.json(409, { error: `This order is ${order.status} — it has no tickets to send.` });
      const fields = {};
      if (body.purchaserName !== undefined) {
        const n = T.cleanText(body.purchaserName, 120);
        if (!n) return T.json(400, { error: 'The purchaser name can’t be empty.' });
        if (n !== order.purchaser_name) fields.purchaser_name = n;
      }
      if (body.performerName !== undefined) {
        const n = T.cleanText(body.performerName, 120);
        if (!n) return T.json(400, { error: 'The performer name can’t be empty.' });
        if (n !== order.performer_name) fields.performer_name = n;
      }
      let to = body.to === undefined ? null : String(body.to).trim().toLowerCase();
      if (to !== null && !T.isValidEmail(to)) return T.json(400, { error: 'That email address is not valid.' });
      if (to === order.purchaser_email) to = null;
      if (Object.keys(fields).length) await db.patch(`ticket_orders?id=eq.${order.id}`, fields);

      const fresh = await db.orderById(order.id);
      const sent = await T.sendOrderEmail(cfg, db, fresh, ev, { by: user.id, to });
      if (!sent.ok) return T.json(502, { error: 'The email could not be sent: ' + sent.error });
      return T.json(200, { sent: true, to: to || fresh.purchaser_email });
    }

    // ---------------- check ----------------
    if (body.action === 'check') {
      let res;
      try { res = await T.settleAndDeliver(cfg, db, order); }
      catch (e) { return T.json(502, { error: 'Could not reach eWAY: ' + e.message }); }
      const fresh = await db.orderById(order.id);
      return T.json(200, {
        state: res.state, issued: !!res.issued, emailed: !!fresh.emailed_at,
        message: res.state === 'paid' ? (res.issued ? 'Payment confirmed — tickets issued and emailed.' : 'This order is already paid.')
               : res.state === 'failed' ? 'eWAY reports the payment was not approved.'
               : res.state === 'refunded' ? 'This order was refunded.'
               : 'eWAY has no completed payment for this order.',
      });
    }

    // ---------------- refund ----------------
    if (body.action === 'refund') {
      if (order.status !== 'paid') return T.json(409, { error: `Only a paid order can be marked refunded (this one is ${order.status}).` });
      const note = T.cleanText(body.note, 400);
      await db.patch(`ticket_orders?id=eq.${order.id}&status=eq.paid`, {
        status: 'refunded',
        status_note: (`Marked refunded by ${user.email || user.id}` + (note ? ': ' + note : '')).slice(0, 500),
      });
      return T.json(200, { refunded: true });
    }

    return T.json(400, { error: 'Unknown action.' });
  } catch (err) {
    console.error('ticket-admin:', err.message);
    return T.json(500, { error: err.message });
  }
};
