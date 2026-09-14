-- Reinstates Abishag's cancelled 14 Sep occurrence (Vikatoa Tupou,
-- Drums, 6:00 PM, Ringwood). Scoped to this exact row's id AND its
-- current 'cancelled' status, so it can't accidentally touch anything
-- else even if run twice.
UPDATE lesson_occurrences
   SET status = 'scheduled'
 WHERE id = '7eb54162-ea9c-43a0-82c5-2c7e7881137d'
   AND status = 'cancelled';

-- Verify — should now show status = 'scheduled'
SELECT id, date, status FROM lesson_occurrences
 WHERE id = '7eb54162-ea9c-43a0-82c5-2c7e7881137d';
