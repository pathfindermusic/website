// ============================================================
// Netlify Function: ticket-event   (public, read-only)
//
// Tells the public /tickets page which events are on sale and what
// the ticket costs. Uses the service role, so the events table itself
// stays closed to the public; only the fields below are returned, and
// only for events an admin switched "Sell tickets online" on for that
// haven't happened yet.
//
// GET /.netlify/functions/ticket-event            → { events: [...] }
// GET /.netlify/functions/ticket-event?event=<id> → { events: [that one] }
// ============================================================
'use strict';
const T = require('./lib/tickets');

exports.handler = async (event) => {
  if (event.httpMethod !== 'GET') return T.json(405, { error: 'Method not allowed' });

  let cfg;
  try { cfg = T.loadConfig(); }
  catch (e) { console.error('ticket-event:', e.message); return T.json(500, { error: 'Ticket sales are temporarily unavailable.' }); }
  const db = T.makeDb(cfg);

  try {
    const only = event.queryStringParameters?.event;
    const today = T.todayMelbourne();
    let path = `events?tickets_enabled=eq.true&event_date=gte.${today}&status=in.(open,closed)&select=${T.EVENT_COLS}&order=event_date.asc,start_time.asc&limit=20`;
    if (only) {
      if (!T.isUuid(only)) return T.json(400, { error: 'Unknown event.' });
      path += `&id=eq.${only}`;
    }
    const rows = await db.get(path);
    return T.json(200, {
      testMode: cfg.sandbox,
      maxPerOrder: T.MAX_PER_ORDER,
      events: rows.map(e => ({
        id: e.id, name: e.name, description: e.description,
        date: e.event_date, startTime: e.start_time, endTime: e.end_time,
        venueName: e.venue_name, venueAddress: e.venue_address,
        priceCents: e.ticket_price_cents, info: e.ticket_info,
      })),
    });
  } catch (err) {
    console.error('ticket-event:', err.message);
    return T.json(500, { error: 'Could not load the ticket details. Please try again shortly.' });
  }
};
