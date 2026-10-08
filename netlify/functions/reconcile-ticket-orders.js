// ============================================================
// Netlify scheduled function: reconcile-ticket-orders
//
// Safety net for buyers whose browser never made it back to
// ticket-result.html (they closed the tab on eWAY's page, lost signal,
// or their email app opened the link elsewhere). Every few minutes it:
//   1. asks eWAY about orders still 'pending' for more than 5 minutes
//      and issues + emails tickets for any that were actually paid;
//      orders with no payment attempt after 3 hours are marked
//      'abandoned' (and still re-checked once more as they are closed);
//   2. retries the email for paid orders that were never delivered.
//
// Schedule: see netlify.toml.
// ============================================================
'use strict';
const T = require('./lib/tickets');

const MIN_AGE_MIN   = 5;
const ABANDON_HOURS = 3;
const GIVE_UP_DAYS  = 3;
const BATCH         = 40;

exports.handler = async () => {
  let cfg;
  try { cfg = T.loadConfig(); }
  catch (e) { console.error('reconcile-ticket-orders:', e.message); return { statusCode: 200, body: 'not configured' }; }
  const db = T.makeDb(cfg);
  const out = { checked: 0, issued: 0, failed: 0, abandoned: 0, emailed: 0, errors: 0 };

  try {
    const ago = (ms) => encodeURIComponent(new Date(Date.now() - ms).toISOString());

    // 1. unconfirmed payments
    const pending = await db.get(
      `ticket_orders?status=eq.pending&eway_access_code=not.is.null` +
      `&created_at=lt.${ago(MIN_AGE_MIN * 60000)}&created_at=gt.${ago(GIVE_UP_DAYS * 86400000)}` +
      `&select=*&order=created_at.asc&limit=${BATCH}`);
    for (const o of pending) {
      out.checked++;
      try {
        const res = await T.settleAndDeliver(cfg, db, o);
        if (res.state === 'paid' && res.issued) out.issued++;
        else if (res.state === 'failed') out.failed++;
        else if (res.state === 'pending' && Date.now() - Date.parse(o.created_at) > ABANDON_HOURS * 3600000) {
          await db.patch(`ticket_orders?id=eq.${o.id}&status=eq.pending`, {
            status: 'abandoned', status_note: 'No payment was made.',
          });
          out.abandoned++;
        }
      } catch (e) { out.errors++; console.error('reconcile', o.order_no, e.message); }
    }

    // orders that never even got a payment page (the eWAY call died mid-way)
    await db.patch(`ticket_orders?status=eq.pending&eway_access_code=is.null&created_at=lt.${ago(ABANDON_HOURS * 3600000)}`, {
      status: 'abandoned', status_note: 'No payment page was created.',
    }).catch(() => {});

    // 2. paid but never emailed
    const unsent = await db.get(
      `ticket_orders?status=eq.paid&emailed_at=is.null&paid_at=lt.${ago(3 * 60000)}&paid_at=gt.${ago(GIVE_UP_DAYS * 86400000)}` +
      `&select=*&order=paid_at.asc&limit=${BATCH}`);
    for (const o of unsent) {
      try {
        const ev = await db.event(o.event_id);
        const sent = await T.sendOrderEmail(cfg, db, o, ev);
        if (sent.ok) out.emailed++; else out.errors++;
      } catch (e) { out.errors++; console.error('reconcile email', o.order_no, e.message); }
    }
  } catch (err) {
    console.error('reconcile-ticket-orders:', err.message);
    return { statusCode: 500, body: err.message };
  }
  console.log('reconcile-ticket-orders', JSON.stringify(out));
  return { statusCode: 200, body: JSON.stringify(out) };
};
