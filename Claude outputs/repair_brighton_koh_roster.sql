-- Repairs Brighton Koh's Drums series after the FIRST version of the
-- split-series fix (since corrected in lessons.html) deleted the old
-- lesson's roster instead of leaving it alone. The new lesson row the
-- split created for 7 Oct onward is already correct (4pm, Brighton on
-- the roster) — nothing to do there. This only restores the old row:
-- old lesson_id a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a, still at 5pm,
-- still holding every occurrence before 7 Oct.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.

-- a. Confirm there's exactly one Brighton Koh, and that the old row
--    still looks right otherwise (5pm, Wednesday, Drums, active).
SELECT id AS student_id, first_name, last_name FROM students
 WHERE first_name = 'Brighton' AND last_name = 'Koh';

SELECT id, day_of_week, start_time, duration_mins, instrument, status
  FROM lessons
 WHERE id = 'a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a';

-- b. Confirm the roster really is missing (expect 0 rows).
SELECT * FROM lesson_students
 WHERE lesson_id = 'a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a'
   AND added_for_occurrence_id IS NULL;

-- c. Restore it. Only run this if (a) returned exactly one Brighton Koh.
INSERT INTO lesson_students (lesson_id, student_id, added_for_occurrence_id)
SELECT 'a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a', s.id, NULL
  FROM students s
 WHERE s.first_name = 'Brighton' AND s.last_name = 'Koh'
RETURNING *;

-- d. Mark the old row cancelled, so it stops counting as Christian's
--    CURRENT lesson anywhere that checks status='active' (My Students,
--    the Attendance and Grading reports). Its past occurrences keep
--    displaying normally either way — same rule as any other series
--    that stopped.
UPDATE lessons SET status = 'cancelled'
 WHERE id = 'a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a'
RETURNING id, status;

-- e. Confirm a pre-7-Oct occurrence resolves a real student again.
SELECT lo.date, ls.student_id
  FROM lesson_occurrences lo
  LEFT JOIN lesson_students ls
    ON ls.lesson_id = lo.lesson_id AND ls.added_for_occurrence_id IS NULL
 WHERE lo.lesson_id = 'a8f49376-b0d6-40b5-bc0b-4ce78a9fbb3a'
 ORDER BY lo.date
 LIMIT 5;
