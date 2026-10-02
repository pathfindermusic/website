-- Revert the one series affected by the "Edit series" time bug:
-- Brighton Koh, Drums, with Christian Nardella at Kilsyth.
-- lesson_id: a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a
--
-- This puts the WHOLE series back to 5pm — past and future occurrences
-- alike — exactly undoing the original bad edit, since there's nowhere
-- else for the old time to live until the code fix is deployed. Once
-- you've deployed and redone the 5pm→4pm change via Edit Series
-- (starting 7 Oct), only the future occurrences will actually move.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.

-- a. Confirm this is the row we expect before touching it.
SELECT id, day_of_week, start_time, duration_mins, instrument, status
  FROM lessons
 WHERE id = 'a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a';

-- b. Revert it to 5pm.
UPDATE lessons
   SET start_time = '17:00:00'
 WHERE id = 'a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a'
RETURNING id, start_time;

-- c. Confirm every occurrence now resolves back to 5pm (reads from
--    the lessons row directly — there's no per-occurrence time, which
--    is exactly the gap the code fix closes).
SELECT lo.date, l.start_time
  FROM lesson_occurrences lo
  JOIN lessons l ON l.id = lo.lesson_id
 WHERE lo.lesson_id = 'a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a'
 ORDER BY lo.date
 LIMIT 5;
