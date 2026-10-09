// ============================================================
// Netlify scheduled function: reconcile-voucher-orders
//
// Safety net for buyers whose browser never made it back to
// voucher-result.html (they closed the tab on eWAY's page, lost signal,
// or their email app opened the link elsewhere). Every few minutes it:
//   1. asks eWAY about orders still 'pending' for more than 5 minutes
//      and issues + emails the voucher for any that were actually paid;
//      orders with no payment attempt after 3 hours are marked
//      'abandoned' (and still re-checked once more as they are closed);
//   2. retries the email for paid orders whose voucher was never
//      delivered to the purchaser or the recipient.
//
// Schedule: see netlify.toml.
// ============================================================
'use strict';
const V = require('./lib/vouchers');

const MIN_AGE_MIN   = 5;
const ABANDON_HOURS = 3;
const GIVE_UP_DAYS  = 3;
const MAX_ATTEMPTS  = 12;     // failed delivery rounds before we stop retrying (an admin can resend by hand)
const BATCH         = 40;

exports.handler = async () => {
  let cfg;
  try { cfg = V.loadConfig(); }
  catch (e) { console.error('reconcile-voucher-orders:', e.message); return { statusCode: 200, body: 'not configured' }; }
  const db = V.makeDb(cfg);
  const out = { checked: 0, issued: 0, failed: 0, abandoned: 0, emailed: 0, errors: 0 };

  try {
    const ago = (ms) => encodeURIComponent(new Date(Date.now() - ms).toISOString());

    // 1. unconfirmed payments
    const pending = await db.get(
      `voucher_orders?status=eq.pending&eway_access_code=not.is.null` +
      `&created_at=lt.${ago(MIN_AGE_MIN * 60000)}&created_at=gt.${ago(GIVE_UP_DAYS * 86400000)}` +
      `&select=*&order=created_at.asc&limit=${BATCH}`);
    for (const o of pending) {
      out.checked++;
      try {
        const res = await V.settleAndDeliver(cfg, db, o);
        if (res.state === 'paid' && res.issued) out.issued++;
        else if (res.state === 'failed') out.failed++;
        else if (res.state === 'pending' && Date.now() - Date.parse(o.created_at) > ABANDON_HOURS * 3600000) {
          await db.patch(`voucher_orders?id=eq.${o.id}&status=eq.pending`, {
            status: 'abandoned', status_note: 'No payment was made.',
          });
          out.abandoned++;
        }
      } catch (e) { out.errors++; console.error('reconcile', o.order_no, e.message); }
    }

    // orders that never even got a payment page (the eWAY call died mid-way)
    await db.patch(`voucher_orders?status=eq.pending&eway_access_code=is.null&created_at=lt.${ago(ABANDON_HOURS * 3600000)}`, {
      status: 'abandoned', status_note: 'No payment page was created.',
    }).catch(() => {});

    // 2. paid but not (fully) delivered
    const paidWindow = `&paid_at=lt.${ago(3 * 60000)}&paid_at=gt.${ago(GIVE_UP_DAYS * 86400000)}&delivery_attempts=lt.${MAX_ATTEMPTS}`;
    const noPurchaser = await db.get(`voucher_orders?status=eq.paid&purchaser_emailed_at=is.null${paidWindow}&select=*&order=paid_at.asc&limit=${BATCH}`);
    const noRecipient = await db.get(`voucher_orders?status=eq.paid&recipient_email=not.is.null&recipient_emailed_at=is.null${paidWindow}&select=*&order=paid_at.asc&limit=${BATCH}`);
    const seen = new Set();
    for (const o of [...noPurchaser, ...noRecipient]) {
      if (seen.has(o.id)) continue;
      seen.add(o.id);
      try {
        const r = await V.deliver(cfg, db, o);
        if (r.purchaser.sent || r.recipient.sent) out.emailed++;
        if (r.purchaser.error || r.recipient.error) out.errors++;
      } catch (e) { out.errors++; console.error('reconcile email', o.order_no, e.message); }
    }
  } catch (err) {
    console.error('reconcile-voucher-orders:', err.message);
    return { statusCode: 500, body: err.message };
  }
  console.log('reconcile-voucher-orders', JSON.stringify(out));
  return { statusCode: 200, body: JSON.stringify(out) };
};
