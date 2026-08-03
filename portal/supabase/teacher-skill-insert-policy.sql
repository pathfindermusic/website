-- ============================================================
-- Teachers need INSERT on student_instruments
--
-- Why: saving a skill level now upserts rather than updates,
-- because a student can be enrolled in a lesson for an instrument
-- that has no student_instruments row yet. An UPDATE matched zero
-- rows in that case and silently saved nothing.
--
-- Run teacher-rls-fix.sql before this one.
-- ============================================================

DROP POLICY IF EXISTS "Teacher adds own student instruments" ON student_instruments;
CREATE POLICY "Teacher adds own student instruments"
  ON student_instruments FOR INSERT
  WITH CHECK (
    student_id IN (
      SELECT ls.student_id
        FROM lesson_students ls
        JOIN lessons l ON l.id = ls.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

-- The upsert needs a unique constraint on (student_id, instrument)
-- to resolve conflicts. It should already exist — this confirms it.
SELECT conname, pg_get_constraintdef(oid) AS definition
  FROM pg_constraint
 WHERE conrelid = 'student_instruments'::regclass
   AND contype IN ('u','p');

-- All teacher policies, for reference
SELECT tablename, policyname, cmd
  FROM pg_policies
 WHERE policyname LIKE 'Teacher %'
 ORDER BY tablename, cmd;
