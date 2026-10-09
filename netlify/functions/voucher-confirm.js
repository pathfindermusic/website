// ============================================================
// Netlify Function: voucher-confirm   (public)
//
// Called by voucher-result.html when eWAY sends the visitor back. The
// address carries only eWAY's AccessCode; this function looks the
// order up by it and asks eWAY (server to server) whether the payment
// was approved. If so it issues the voucher and emails the PDF — once,
// however many times this is called.
//
// POST { accessCode }
// → { state: paid | failed | pending | refunded, message?, retryable?,
//     order: { orderNo, voucherTitle, subject, purchaserName, recipientName,
//              emailMasked, recipientEmailMasked, totalCents },
//     voucher: { expiresOn } | null,
//     emailed, recipientEmailed }
// ============================================================
'use strict';
const V = require('./lib/vouchers');
const T = V.T;

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return T.json(405, { error: 'Method not allowed' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return T.json(400, { error: 'Invalid request.' }); }
  const accessCode = T.normAccessCode(body.accessCode);
  if (!T.isAccessCode(accessCode)) return T.json(400, { error: 'This page needs a payment reference. Please use the link from the payment page.' });

  let cfg;
  try { cfg = V.loadConfig(); }
  catch (e) { console.error('voucher-confirm:', e.message); return T.json(500, { error: 'Voucher sales are temporarily unavailable.' }); }
  const db = V.makeDb(cfg);

  try {
    const order = await db.orderByCode(accessCode);
    if (!order) return T.json(404, { error: 'We could not find an order for this payment.' });

    let res;
    try {
      res = await V.settleAndDeliver(cfg, db, order);
    } catch (e) {
      // eWAY unreachable or odd reply: tell the visitor we are still checking;
      // the scheduled job keeps trying, so a paid order is never lost
      console.error('voucher-confirm: settle', order.order_no, e.message);
      res = { state: 'pending', message: 'We are still confirming your payment.' };
    }

    const fresh = await db.orderById(order.id);
    const voucher = res.state === 'paid' ? await db.voucherOf(order.id) : null;
    return T.json(200, {
      state: res.state,
      message: res.message ?? null,
      retryable: res.state === 'failed' && !res.review,
      emailed: !!fresh?.purchaser_emailed_at,
      recipientEmailed: !!fresh?.recipient_emailed_at,
      order: {
        orderNo: fresh.order_no, voucherTitle: fresh.voucher_title, subject: fresh.subject,
        purchaserName: fresh.purchaser_name, recipientName: fresh.recipient_name,
        emailMasked: T.maskEmail(fresh.purchaser_email),
        recipientEmailMasked: fresh.recipient_email ? T.maskEmail(fresh.recipient_email) : null,
        totalCents: fresh.amount_cents,
      },
      voucher: voucher ? { expiresOn: voucher.expires_on } : null,
    });
  } catch (err) {
    console.error('voucher-confirm:', err.message);
    return T.json(500, { error: 'We could not check your payment just now. If you were charged, your voucher will be emailed to you shortly — or contact us with your receipt.' });
  }
};
