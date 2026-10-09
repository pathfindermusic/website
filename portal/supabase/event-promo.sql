-- ============================================================
-- PATHFINDER PORTAL — Posters & leaflets (event-promo.html)
--
-- Lets admins "remember" the friendly wording for an event's poster
-- and leaflet (the invitation sentence, the extra details such as
-- "Doors open at 11:30 AM / Parking available", and the note under
-- the booking steps). Everything else on a poster or leaflet is read
-- from the event itself.
--
-- This script is OPTIONAL for the page to work: without it the page
-- still makes posters and leaflets, it just cannot remember wording.
--
-- ⚠ Run ONE STATEMENT AT A TIME, in order, and check each result.
-- ⚠ Safe to run more than once.
-- ============================================================


-- ============================================================
-- STEP 1 — three optional text columns on events
--   (only admins can read/write the events table, as before)
-- ============================================================
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS promo_tagline        text
                           CHECK (promo_tagline IS NULL OR char_length(promo_tagline) <= 300),
  ADD COLUMN IF NOT EXISTS promo_highlights     text
                           CHECK (promo_highlights IS NULL OR char_length(promo_highlights) <= 600),
  ADD COLUMN IF NOT EXISTS promo_performer_note text
                           CHECK (promo_performer_note IS NULL OR char_length(promo_performer_note) <= 300);


-- ============================================================
-- STEP 2 (optional) — fill in the 2026 Year-end Concert so its
--   poster has the doors/parking details straight away, and the
--   "arrive 30 minutes before" note is on the performer box.
--   Matches the event by name; check "1 row updated".
-- ============================================================
UPDATE events
   SET promo_highlights     = E'Doors open at 11:30 AM\nParking available\nLovely parks nearby to explore if you arrive early',
       promo_performer_note = 'Forgotten your password? Tap “Forgot password?” on the sign-in page. Please arrive 30 minutes before your performance.'
 WHERE name = '2026 Year-end Concert'
   AND promo_highlights IS NULL;


-- ============================================================
-- To undo (only if you really want to):
-- ALTER TABLE events DROP COLUMN IF EXISTS promo_tagline, DROP COLUMN IF EXISTS promo_highlights, DROP COLUMN IF EXISTS promo_performer_note;
-- ============================================================
