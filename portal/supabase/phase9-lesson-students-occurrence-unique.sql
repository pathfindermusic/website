-- ============================================================
-- PATHFINDER PORTAL — let a student be added as an ad-hoc guest
-- to more than one occurrence of the same group series
--
-- Reported: adding a student to one occurrence of a group lesson
-- worked, but adding the SAME student to a different occurrence
-- of the SAME series failed with a unique constraint violation
-- (lesson_students_lesson_id_student_id_key or similarly named).
--
-- Cause: lesson_students has (or had) a UNIQUE(lesson_id,
-- student_id) constraint from before occurrence-only guests
-- existed (phase5-occurrence-only-students.sql added the nullable
-- added_for_occurrence_id column but never revisited this older
-- constraint). That constraint only knows about lesson_id and
-- student_id — it can't tell "permanent member" apart from
-- "guest for occurrence A" apart from "guest for occurrence B",
-- so the second ad-hoc row for the same student ever tripped it,
-- occurrence-scoped or not. The app's insert code itself is
-- already correct (portal/lessons.html's addStudentToOccurrence
-- inserts a fresh row per occurrence, exactly as intended) — this
-- is purely a leftover constraint that predates the feature.
--
-- Fix: drop that constraint (found by column signature, not by a
-- possibly-guessed name — the exact name in the error you saw may
-- not match what's actually in this database), and replace it
-- with two narrower ones that still forbid what should never
-- happen, while allowing what should:
--   - a student can only be a PERMANENT member of a series once
--     (added_for_occurrence_id IS NULL) — unchanged from before
--   - a student can only be added as a guest to the SAME
--     occurrence once — new, prevents an accidental double-add
--   - a student CAN be a guest of the same series on more than
--     one occurrence, each a separate row — the thing that was
--     wrongly blocked
--
-- No RLS change — lesson_students' write policies are role-based,
-- not column-based, so they already cover this.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Drop the old constraint, found by its actual columns rather
--    than an assumed name.
-- ------------------------------------------------------------
DO $$
DECLARE cname text;
BEGIN
  SELECT conname INTO cname
    FROM pg_constraint
   WHERE conrelid = 'lesson_students'::regclass
     AND contype  = 'u'
     AND array_length(conkey, 1) = 2
     AND conkey::int[] @> ARRAY[
           (SELECT attnum FROM pg_attribute
             WHERE attrelid = 'lesson_students'::regclass AND attname = 'lesson_id'),
           (SELECT attnum FROM pg_attribute
             WHERE attrelid = 'lesson_students'::regclass AND attname = 'student_id')
         ]::int[];
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE lesson_students DROP CONSTRAINT %I', cname);
  END IF;
END $$;


-- ------------------------------------------------------------
-- 2. Replace it with two narrower ones
-- ------------------------------------------------------------

-- At most one PERMANENT membership per (series, student)
CREATE UNIQUE INDEX IF NOT EXISTS lesson_students_permanent_key
  ON lesson_students (lesson_id, student_id)
  WHERE added_for_occurrence_id IS NULL;

-- At most one guest row per (series, student, occurrence) — but
-- any number of occurrences for the same student in the same series
CREATE UNIQUE INDEX IF NOT EXISTS lesson_students_occurrence_key
  ON lesson_students (lesson_id, student_id, added_for_occurrence_id)
  WHERE added_for_occurrence_id IS NOT NULL;


-- ============================================================
-- VERIFY — run each separately
-- ============================================================

-- a. The old two-column constraint is gone
SELECT conname, pg_get_constraintdef(oid) AS def
  FROM pg_constraint
 WHERE conrelid = 'lesson_students'::regclass AND contype = 'u';

-- b. Both new indexes exist
SELECT indexname, indexdef
  FROM pg_indexes
 WHERE tablename = 'lesson_students'
   AND indexname IN ('lesson_students_permanent_key', 'lesson_students_occurrence_key');

-- c. Sanity check — this should now succeed: adding the same
--    student as a guest to a second occurrence of a series they're
--    already a guest of once. Replace the two IDs with a real
--    lesson_id and student_id, and a second occurrence_id of that
--    same lesson that the student isn't already on.
-- INSERT INTO lesson_students (lesson_id, student_id, added_for_occurrence_id)
-- VALUES ('PASTE-LESSON-ID', 'PASTE-STUDENT-ID', 'PASTE-A-DIFFERENT-OCCURRENCE-ID');
-- -- then clean it up if it was just a test:
-- -- DELETE FROM lesson_students WHERE lesson_id='...' AND student_id='...' AND added_for_occurrence_id='...';
