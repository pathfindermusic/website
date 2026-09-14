-- ============================================================
-- Good — the unique constraint on (lesson_id, date) does exist,
-- so a duplicated occurrence row for the exact same lesson+date is
-- ruled out. Next step: pull every occurrence at Ringwood on 14 Sep
-- so I can replicate the grid's own row-span/column logic against
-- the real data and find exactly where it goes wrong.
--
-- Read-only SELECT — completely safe to run.
-- ============================================================
SELECT
  lo.id AS occurrence_id, lo.date, lo.status AS occ_status,
  lo.is_online, lo.occurrence_notes, lo.is_makeup,
  lo.substitute_teacher_id, lo.substitute_name,
  l.id AS lesson_id, l.teacher_id AS original_teacher_id,
  COALESCE(lo.substitute_teacher_id, l.teacher_id) AS effective_teacher_id,
  tp.first_name || ' ' || tp.last_name AS original_teacher_name,
  l.instrument, l.start_time, l.duration_mins, l.lesson_type,
  l.status AS lesson_status, l.frequency,
  l.studio_id, st.name AS studio_name
FROM lesson_occurrences lo
JOIN lessons  l  ON l.id  = lo.lesson_id
JOIN teachers t  ON t.id  = l.teacher_id
JOIN profiles tp ON tp.id = t.user_id
JOIN studios  st ON st.id = l.studio_id
WHERE lo.date = '2026-09-14'
  AND st.name = 'Ringwood'
ORDER BY COALESCE(lo.substitute_teacher_id, l.teacher_id), l.start_time;
