// ============================================================
// Netlify Function: voucher-config   (public, read-only)
//
// Tells the public /gift-vouchers page which vouchers are on sale and
// what they cost, so the prices live in ONE place (VOUCHER_TYPES in
// lib/vouchers.js) and the page can never advertise a price the server
// would not charge.
//
// GET /.netlify/functions/voucher-config
// → { testMode, maxMessage, maxSubject, types: [{ key, title, lessons,
//      priceCents, saveCents, badge }] }
// ============================================================
'use strict';
const V = require('./lib/vouchers');

exports.handler = async (event) => {
  if (event.httpMethod !== 'GET') return V.T.json(405, { error: 'Method not allowed' });
  let cfg;
  try { cfg = V.loadConfig(); }
  catch (e) { console.error('voucher-config:', e.message); return V.T.json(500, { error: 'Voucher sales are temporarily unavailable.' }); }
  return V.T.json(200, {
    testMode: cfg.sandbox,
    maxMessage: V.MAX_MESSAGE,
    maxSubject: V.MAX_SUBJECT,
    types: V.publicTypes(),
  });
};
