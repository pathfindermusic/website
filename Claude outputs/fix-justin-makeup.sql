-- Converts Justin Galgut's 14 Sep makeup lesson from Group 5:30-6:30 PM
-- (60 min) to Private 5:30-6:00 PM (30 min) — no longer overlaps
-- Daniel Vu's 6:00-6:30 PM lesson with Myra Kaur; they now sit
-- back-to-back instead. Nothing else about the lesson changes (same
-- teacher, day, start time, and its "Makeup lesson for 7 September
-- 2026" note still applies).
UPDATE lessons
   SET lesson_type   = 'private',
       duration_mins = 30,
       max_students  = 1
 WHERE id = '3f5dbd18-33ca-4ea4-82b8-03086c9e03ec';

-- Verify — should now show private / 30 / 1
SELECT id, lesson_type, duration_mins, max_students, start_time, series_notes
  FROM lessons
 WHERE id = '3f5dbd18-33ca-4ea4-82b8-03086c9e03ec';
