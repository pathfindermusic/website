-- ============================================================
-- PATHFINDER PORTAL — indexes for the schedule views
--
-- Reported: a teacher's My Schedule page failed to load today's
-- lessons with "cancelling statement due to statement timeout".
--
-- Root cause: schedule_view / student_schedule_view run several
-- correlated subqueries per row against lesson_students and
-- attendance (counting students, counting/looking up attendance),
-- and the base query itself filters lesson_occurrences by date and
-- joins to lessons by teacher_id. None of the columns actually
-- driving those lookups had an index:
--   lesson_occurrences.date
--   lesson_occurrences.lesson_id
--   lessons.teacher_id
--   lesson_students.lesson_id / .student_id
--   attendance.lesson_occurrence_id / .student_id
-- Only two narrow partial indexes existed (is_makeup,
-- substitute_teacher_id). As lesson_occurrences has grown — it's
-- pre-generated well into the future for every recurring series —
-- every one of those lookups had become a full table scan. Small
-- data hid this for a long time; it doesn't anymore.
--
-- This is additive and read-only in effect (just indexes) — safe to
-- run any time, but each CREATE INDEX briefly uses extra CPU/IO
-- while it builds. Using CONCURRENTLY so it doesn't lock the table
-- against reads/writes while that happens. CONCURRENTLY can't run
-- inside a transaction block, so — as always — run ONE STATEMENT AT
-- A TIME.
-- ============================================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS lesson_occurrences_date_idx
  ON lesson_occurrences (date);

CREATE INDEX CONCURRENTLY IF NOT EXISTS lesson_occurrences_lesson_id_idx
  ON lesson_occurrences (lesson_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS lessons_teacher_id_idx
  ON lessons (teacher_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS lessons_studio_id_idx
  ON lessons (studio_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS lesson_students_lesson_id_idx
  ON lesson_students (lesson_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS lesson_students_student_id_idx
  ON lesson_students (student_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS attendance_lesson_occurrence_id_idx
  ON attendance (lesson_occurrence_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS attendance_student_id_idx
  ON attendance (student_id);


-- ============================================================
-- VERIFY — run each separately
-- ============================================================

-- All eight should now show up:
SELECT tablename, indexname
  FROM pg_indexes
 WHERE schemaname = 'public'
   AND indexname IN (
     'lesson_occurrences_date_idx', 'lesson_occurrences_lesson_id_idx',
     'lessons_teacher_id_idx', 'lessons_studio_id_idx',
     'lesson_students_lesson_id_idx', 'lesson_students_student_id_idx',
     'attendance_lesson_occurrence_id_idx', 'attendance_student_id_idx'
   )
 ORDER BY tablename, indexname;

-- Sanity check the query that was timing out is now fast. Replace
-- the teacher_id with the affected teacher's id from `teachers`,
-- and the date with today.
-- EXPLAIN ANALYZE
-- SELECT occurrence_id FROM schedule_view
--  WHERE teacher_id = 'PASTE-TEACHER-ID-HERE'
--    AND date = CURRENT_DATE
--    AND occurrence_status <> 'cancelled';
-- ^ look at the total "Execution Time" at the bottom — should be
-- milliseconds, not seconds.
