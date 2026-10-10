-- ============================================================
-- Phase 14 — close a leaving student's tasks automatically
--
-- When a student's lessons are ended as part of an End enrolment
-- checklist, the Portal now quietly closes their other open tasks
-- (individual and recurring) and takes them off recurring rules,
-- logging "Task completed due to student stopping lessons" on each.
--
-- This column records that it has been done for a given checklist,
-- so it only ever happens once. Run it one statement at a time.
-- Until it has been run, the feature simply does nothing.
-- ============================================================

ALTER TABLE student_processes
  ADD COLUMN IF NOT EXISTS tasks_closed_at timestamptz;

-- Verify (expect one row):
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'student_processes' AND column_name = 'tasks_closed_at';
