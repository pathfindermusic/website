-- ============================================================
-- DIAGNOSTIC ONLY — every statement below is a read-only SELECT.
-- Run each one separately and share the results.
-- ============================================================

-- 1. Is there actually a uniqueness guarantee on (lesson_id, date)?
--    The app's occurrence-regeneration logic depends on this existing.
SELECT conname, contype, pg_get_constraintdef(oid) AS definition
  FROM pg_constraint
 WHERE conrelid = 'public.lesson_occurrences'::regclass
   AND contype IN ('u','p');

-- 2. Same question, from the index side (a unique constraint shows up
--    as a unique index too, but this also catches a unique index that
--    was created without a named constraint).
SELECT indexname, indexdef
  FROM pg_indexes
 WHERE tablename = 'lesson_occurrences';

-- 3. Find the lesson (Vikatoa Tupou, Drums, 6:00 PM, Ringwood)
SELECT l.id AS lesson_id, l.day_of_week, l.start_time, l.duration_mins,
       l.instrument, l.status, l.frequency, l.recurrence_type,
       tp.first_name || ' ' || tp.last_name AS teacher_name,
       st.name AS studio_name
  FROM lessons l
  JOIN teachers t  ON t.id  = l.teacher_id
  JOIN profiles tp ON tp.id = t.user_id
  JOIN studios  st ON st.id = l.studio_id
 WHERE tp.first_name = 'Vikatoa' AND tp.last_name = 'Tupou'
   AND l.instrument = 'Drums'
   AND l.start_time = '18:00:00';

-- 4. Every occurrence row for that lesson around 14 Sep 2026 — paste
--    the lesson_id from query 3's result in place of PASTE-LESSON-ID.
-- SELECT id, date, status, is_online, occurrence_notes, created_at
--   FROM lesson_occurrences
--  WHERE lesson_id = 'PASTE-LESSON-ID'
--    AND date BETWEEN '2026-08-31' AND '2026-09-28'
--  ORDER BY date, created_at;

-- 5. A broader scan — any lesson anywhere with more than one occurrence
--    row on the same date. This tells us how widespread the issue is.
SELECT lesson_id, date, COUNT(*) AS row_count,
       array_agg(id ORDER BY created_at)     AS occurrence_ids,
       array_agg(status ORDER BY created_at) AS statuses
  FROM lesson_occurrences
 GROUP BY lesson_id, date
HAVING COUNT(*) > 1
 ORDER BY date DESC;
