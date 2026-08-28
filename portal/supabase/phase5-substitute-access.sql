-- ============================================================
-- PATHFINDER PORTAL — what a substitute teacher can see
--
-- Confirmed with the admins: a substitute SHOULD see the lesson
-- notes. Someone walking into a guitar lesson needs to know the
-- student was working on barre chords last week — that is what
-- notes are for.
--
-- The earlier substitute policies granted the lesson and the
-- occurrence, which probably let notes through as a side effect
-- while leaving the student's NAME and skill level hidden. This
-- makes the whole set explicit rather than accidental.
--
-- A substitute can see, for the occurrences they are covering:
--   · the lesson and that occurrence
--   · the students in it, and their names
--   · the lesson notes, including earlier weeks
--   · their skill levels
--   · attendance, so they can mark it
--
-- They cannot see anything about the students' OTHER lessons, or
-- any contact details — same as any other teacher.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Which lessons am I covering, and which occurrences?
--
-- SECURITY DEFINER, so these read without RLS applying and no
-- policy can recurse into another. Same pattern as
-- my_lesson_ids() and get_my_teacher_id().
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_covered_occurrence_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY(
    SELECT lo.id FROM lesson_occurrences lo
     WHERE lo.substitute_teacher_id = get_my_teacher_id()
  ), ARRAY[]::uuid[]);
$$;

CREATE OR REPLACE FUNCTION my_covered_lesson_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY(
    SELECT DISTINCT lo.lesson_id FROM lesson_occurrences lo
     WHERE lo.substitute_teacher_id = get_my_teacher_id()
  ), ARRAY[]::uuid[]);
$$;

-- The students in those lessons
CREATE OR REPLACE FUNCTION my_covered_student_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY(
    SELECT DISTINCT ls.student_id
      FROM lesson_students ls
     WHERE ls.lesson_id = ANY(my_covered_lesson_ids())
  ), ARRAY[]::uuid[]);
$$;


-- ------------------------------------------------------------
-- 2. The lesson and its occurrences
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "teacher_reads_covered_lessons" ON lessons;
CREATE POLICY "teacher_reads_covered_lessons" ON lessons FOR SELECT
  USING (id = ANY(my_covered_lesson_ids()));

DROP POLICY IF EXISTS "teacher_reads_covered_occurrences" ON lesson_occurrences;
CREATE POLICY "teacher_reads_covered_occurrences" ON lesson_occurrences FOR SELECT
  USING (lesson_id = ANY(my_covered_lesson_ids()));


-- ------------------------------------------------------------
-- 3. Who is in the lesson, and their names
--
-- Without these the substitute sees a lesson with no student on
-- it — the schedule would show a blank where the name should be.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "teacher_reads_covered_lesson_students" ON lesson_students;
CREATE POLICY "teacher_reads_covered_lesson_students" ON lesson_students FOR SELECT
  USING (lesson_id = ANY(my_covered_lesson_ids()));

DROP POLICY IF EXISTS "teacher_reads_covered_students" ON students;
CREATE POLICY "teacher_reads_covered_students" ON students FOR SELECT
  USING (id = ANY(my_covered_student_ids()));

DROP POLICY IF EXISTS "teacher_reads_covered_profiles" ON profiles;
CREATE POLICY "teacher_reads_covered_profiles" ON profiles FOR SELECT
  USING (
    id IN (SELECT s.user_id FROM students s WHERE s.id = ANY(my_covered_student_ids()))
  );


-- ------------------------------------------------------------
-- 4. The notes — the point of the exercise
--
-- Scoped to the LESSON, not just the covered occurrence, so the
-- substitute can read what the regular teacher wrote in previous
-- weeks. That history is what makes the note useful.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "teacher_reads_covered_notes" ON lesson_notes;
CREATE POLICY "teacher_reads_covered_notes" ON lesson_notes FOR SELECT
  USING (
    lesson_occurrence_id IN (
      SELECT lo.id FROM lesson_occurrences lo
       WHERE lo.lesson_id = ANY(my_covered_lesson_ids())
    )
  );

-- And they should be able to write one for the lesson they took
DROP POLICY IF EXISTS "teacher_writes_covered_notes" ON lesson_notes;
CREATE POLICY "teacher_writes_covered_notes" ON lesson_notes FOR INSERT
  WITH CHECK (lesson_occurrence_id = ANY(my_covered_occurrence_ids()));

DROP POLICY IF EXISTS "teacher_updates_covered_notes" ON lesson_notes;
CREATE POLICY "teacher_updates_covered_notes" ON lesson_notes FOR UPDATE
  USING      (lesson_occurrence_id = ANY(my_covered_occurrence_ids()))
  WITH CHECK (lesson_occurrence_id = ANY(my_covered_occurrence_ids()));


-- ------------------------------------------------------------
-- 5. Skill levels — read only
--
-- Useful context for the lesson. Grading belongs to the regular
-- teacher, who knows the student's trajectory.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "teacher_reads_covered_skills" ON student_instruments;
CREATE POLICY "teacher_reads_covered_skills" ON student_instruments FOR SELECT
  USING (student_id = ANY(my_covered_student_ids()));


-- ------------------------------------------------------------
-- 6. Attendance for the lesson they are taking
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "teacher_marks_covered_attendance" ON attendance;
CREATE POLICY "teacher_marks_covered_attendance" ON attendance FOR ALL
  USING      (lesson_occurrence_id = ANY(my_covered_occurrence_ids()))
  WITH CHECK (lesson_occurrence_id = ANY(my_covered_occurrence_ids()));


NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — impersonate the covering teacher.
--
-- Every count should be greater than zero for a lesson they are
-- covering, and should NOT include anything else they teach.
-- ============================================================
-- BEGIN;
--   SET LOCAL role TO authenticated;
--   SET LOCAL request.jwt.claims TO '{"sub":"<substitute-user-id>","role":"authenticated"}';
--
--   SELECT my_covered_lesson_ids()     AS covered_lessons,
--          my_covered_occurrence_ids() AS covered_occurrences,
--          my_covered_student_ids()    AS covered_students;
--
--   SELECT 'lessons' AS t, COUNT(*) FROM lessons
--   UNION ALL SELECT 'lesson_occurrences', COUNT(*) FROM lesson_occurrences
--   UNION ALL SELECT 'lesson_students',    COUNT(*) FROM lesson_students
--   UNION ALL SELECT 'students',           COUNT(*) FROM students
--   UNION ALL SELECT 'profiles',           COUNT(*) FROM profiles
--   UNION ALL SELECT 'lesson_notes',       COUNT(*) FROM lesson_notes
--   UNION ALL SELECT 'student_instruments',COUNT(*) FROM student_instruments
--   UNION ALL SELECT 'attendance',         COUNT(*) FROM attendance;
-- ROLLBACK;
