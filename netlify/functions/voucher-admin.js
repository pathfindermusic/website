// ============================================================
// Netlify Function: voucher-admin   (signed-in admins only)
//
// The Vouchers page's actions on ONLINE voucher orders that need the server:
//   resend   email the voucher again — to the purchaser, the recipient or
//            both, optionally to a corrected address (the order and the
//            register are updated to match; the PDF is rebuilt)
//   check    ask eWAY again about an unpaid order (a buyer who paid but
//            whose return page never loaded) and issue the voucher if it
//            was approved
//   refund   mark a paid order refunded AFTER you have refunded it in
//            MYeWAY; its voucher is voided (unless already redeemed)
//
// POST { action, orderId, target?, purchaserEmail?, recipientEmail?, note? }
//   target: 'purchaser' | 'recipient' | 'both'   (resend; default 'both')
//   Authorization: Bearer <the admin's Supabase access token>
// ============================================================
'use strict';
const V = require('./lib/vouchers');
const T = V.T;

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return T.json(405, { error: 'Method not allowed' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return T.json(400, { error: 'Invalid request body' }); }

  let cfg;
  try { cfg = V.loadConfig(); }
  catch (e) { return T.json(500, { error: 'Server misconfigured — ' + e.message }); }
  const db = V.makeDb(cfg);

  try {
    const token = (event.headers?.authorization || event.headers?.Authorization || '').replace(/^Bearer\s+/i, '');
    if (!token) return T.json(401, { error: 'Not signed in.' });
    const user = await db.user(token);
    if (!user) return T.json(401, { error: 'Your session has expired — please sign in again.' });
    if (!V.canManage(user)) return T.json(403, { error: 'Only admins can manage voucher sales.' });

    if (!T.isUuid(body.orderId)) return T.json(400, { error: 'orderId is required.' });
    const order = await db.orderById(body.orderId);
    if (!order) return T.json(404, { error: 'Order not found.' });

    // ---------------- resend ----------------
    if (body.action === 'resend') {
      if (order.status !== 'paid') return T.json(409, { error: `This order is ${order.status} — it has no voucher to send.` });
      const voucher = await db.voucherOf(order.id);
      if (!voucher) return T.json(409, { error: 'This order has no voucher yet.' });
      if (voucher.status !== 'issued') return T.json(409, { error: `This voucher is ${voucher.status} — it can’t be emailed.` });
      const today = T.todayMelbourne();
      if (String(voucher.expires_on).slice(0, 10) < today) return T.json(409, { error: 'This voucher has expired.' });

      const target = ['purchaser', 'recipient', 'both'].includes(body.target) ? body.target : 'both';
      const fields = {};
      if (body.purchaserEmail !== undefined) {
        const a = String(body.purchaserEmail).trim().toLowerCase();
        if (!T.isValidEmail(a)) return T.json(400, { error: 'The purchaser’s email address is not valid.' });
        if (a !== order.purchaser_email) fields.purchaser_email = a;
      }
      if (body.recipientEmail !== undefined) {
        const a = String(body.recipientEmail).trim().toLowerCase();
        if (a && !T.isValidEmail(a)) return T.json(400, { error: 'The recipient’s email address is not valid.' });
        if ((a || null) !== (order.recipient_email || null)) fields.recipient_email = a || null;
      }
      if (Object.keys(fields).length) {
        await db.patch(`voucher_orders?id=eq.${order.id}`, fields);
        await db.patch(`gift_vouchers?id=eq.${voucher.id}`, {
          ...(fields.purchaser_email ? { purchaser_email: fields.purchaser_email } : {}),
          ...('recipient_email' in fields ? { recipient_email: fields.recipient_email } : {}),
        }).catch(() => {});
      }
      const fresh = await db.orderById(order.id);
      if (target === 'recipient' && !fresh.recipient_email) {
        return T.json(400, { error: 'There is no recipient email address on this order.' });
      }
      const res = await V.deliver(cfg, db, fresh, { force: target, by: user.id });
      const failures = ['purchaser', 'recipient'].filter(k => res[k].error).map(k => `${k}: ${res[k].error}`);
      if (failures.length) return T.json(502, { error: 'The email could not be sent — ' + failures.join('; '), result: res });
      return T.json(200, {
        sent: true,
        purchaser: res.purchaser.sent ? res.purchaser.to : null,
        recipient: res.recipient.sent ? res.recipient.to : null,
      });
    }

    // ---------------- check ----------------
    if (body.action === 'check') {
      let res;
      try { res = await V.settleAndDeliver(cfg, db, order); }
      catch (e) { return T.json(502, { error: 'Could not reach eWAY: ' + e.message }); }
      const fresh = await db.orderById(order.id);
      return T.json(200, {
        state: res.state, issued: !!res.issued, emailed: !!fresh.purchaser_emailed_at,
        message: res.state === 'paid' ? (res.issued ? 'Payment confirmed — voucher issued and emailed.' : 'This order is already paid.')
               : res.state === 'failed' ? 'eWAY reports the payment was not approved.'
               : res.state === 'refunded' ? 'This order was refunded.'
               : 'eWAY has no completed payment for this order.',
      });
    }

    // ---------------- refund ----------------
    if (body.action === 'refund') {
      if (order.status !== 'paid') return T.json(409, { error: `Only a paid order can be marked refunded (this one is ${order.status}).` });
      const note = T.cleanText(body.note, 400);
      await db.patch(`voucher_orders?id=eq.${order.id}&status=eq.paid`, {
        status: 'refunded',
        status_note: (`Marked refunded by ${user.email || user.id}` + (note ? ': ' + note : '')).slice(0, 500),
      });
      const voucher = await db.voucherOf(order.id);
      return T.json(200, { refunded: true, voucherStatus: voucher?.status ?? null });
    }

    return T.json(400, { error: 'Unknown action.' });
  } catch (err) {
    console.error('voucher-admin:', err.message);
    return T.json(500, { error: err.message });
  }
};
