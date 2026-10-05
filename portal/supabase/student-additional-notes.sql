-- ============================================================
-- PATHFINDER PORTAL — Additional Notes on the student record
--
-- A short free-text note (max 50 characters) shown at the bottom of
-- the Student modal on students.html. Run the statements ONE AT A
-- TIME, in order. Run these BEFORE deploying the updated students.html
-- — the page reads the new column when it loads the list.
-- ============================================================

-- 1. The column
ALTER TABLE students ADD COLUMN IF NOT EXISTS additional_notes text;

-- 2. The 50-character limit, enforced in the database as well as
--    in the form (NULL is allowed — most students will have no note).
ALTER TABLE students ADD CONSTRAINT students_additional_notes_len
  CHECK (additional_notes IS NULL OR char_length(additional_notes) <= 50);

-- 3. Check (optional) — should return one row: additional_notes | text
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'students' AND column_name = 'additional_notes';
