-- Read-only lookup — find the series you edited with "Edit series" that
-- moved to 4pm on Wednesdays, so we can confirm the exact lesson_id
-- before reverting it. Safe to run as-is; changes nothing.
--
-- Matches: active, Wednesday, 4:00pm start. If more than one row comes
-- back, use the student/teacher names and date range to pick the one
-- you edited — "earliest_occurrence" / "latest_occurrence" show the
-- full span of dates currently attached to that lesson_id, which should
-- help confirm it's the right series.

SELECT
  l.id                 AS lesson_id,
  l.day_of_week,
  l.start_time,
  l.duration_mins,
  l.lesson_type,
  l.instrument,
  st.name               AS studio_name,
  tp.first_name || ' ' || tp.last_name AS teacher_name,
  STRING_AGG(DISTINCT COALESCE(s.first_name, sp.first_name) || ' ' || COALESCE(s.last_name, sp.last_name), ', ') AS students,
  MIN(lo.date)          AS earliest_occurrence,
  MAX(lo.date)          AS latest_occurrence,
  COUNT(lo.id)          AS occurrence_count
FROM lessons l
JOIN studios  st ON st.id = l.studio_id
JOIN teachers t  ON t.id  = l.teacher_id
JOIN profiles tp ON tp.id = t.user_id
LEFT JOIN lesson_students ls ON ls.lesson_id = l.id AND ls.added_for_occurrence_id IS NULL
LEFT JOIN students s  ON s.id = ls.student_id
LEFT JOIN profiles sp ON sp.id = s.user_id
LEFT JOIN lesson_occurrences lo ON lo.lesson_id = l.id
WHERE l.status = 'active'
  AND l.day_of_week = 3          -- Wednesday
  AND l.start_time = '16:00:00'  -- 4pm
GROUP BY l.id, l.day_of_week, l.start_time, l.duration_mins, l.lesson_type,
         l.instrument, st.name, tp.first_name, tp.last_name
ORDER BY earliest_occurrence;
