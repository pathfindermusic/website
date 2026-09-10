-- ============================================================
-- STEP 1b — detail check for the two Ario Ameri records, before
-- deciding which one is the broken duplicate
-- ============================================================
-- Run each of these three separately and read the results.

-- 1. What lesson(s) does each record actually have? A real, ongoing
--    enrolment should show recurrence_type = 'indefinite' (or
--    'occurrences'/'date_range') and status = 'active'. A record
--    stuck at "trial" stage may only have a one-off trial lesson, or
--    none at all if the trial was booked under the other duplicate.
SELECT
  l.student_id, l.id AS lesson_id, l.instrument, l.day_of_week,
  l.start_time, l.recurrence_type, l.recurrence_start, l.recurrence_end,
  l.status, l.created_at,
  t_p.first_name AS teacher_first, t_p.last_name AS teacher_last
FROM lessons l
LEFT JOIN teachers  t   ON t.id = l.teacher_id
LEFT JOIN profiles  t_p ON t_p.id = t.user_id
WHERE l.student_id IN ('26368637-e3df-4ce0-a183-115f54122d66', '85f91df1-a29c-4927-92b6-eb3733029956')
   OR l.id IN (SELECT lesson_id FROM lesson_students WHERE student_id IN
        ('26368637-e3df-4ce0-a183-115f54122d66', '85f91df1-a29c-4927-92b6-eb3733029956'))
ORDER BY l.student_id, l.created_at;

-- 2. Full process history (not just "in_progress") for each record —
--    this shows whether one of them actually has a completed
--    ongoing_enrolment, or whether BOTH are incomplete in different
--    ways.
SELECT student_id, process_type, status, started_at, completed_at
FROM student_processes
WHERE student_id IN ('26368637-e3df-4ce0-a183-115f54122d66', '85f91df1-a29c-4927-92b6-eb3733029956')
ORDER BY student_id, started_at;

-- 3. Every task tied to each record (open and done), so we can see
--    what's actually outstanding.
SELECT subject_id AS student_id, title, status, source, due_date, created_at
FROM tasks
WHERE subject_type = 'student'
  AND subject_id IN ('26368637-e3df-4ce0-a183-115f54122d66', '85f91df1-a29c-4927-92b6-eb3733029956')
ORDER BY subject_id, created_at;
