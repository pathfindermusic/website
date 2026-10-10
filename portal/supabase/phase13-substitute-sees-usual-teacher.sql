-- ============================================================
-- PATHFINDER PORTAL — a covering teacher must be able to read the
-- USUAL teacher's teacher record
--
-- Symptom (Oct 2026): Bailey Tenace was covering Vikatoa Tupou's
-- lessons on 14 Oct. The admin grid showed him as the cover, and he
-- could read the lessons, students and notes — but his schedule was
-- empty.
--
-- Cause: schedule_view does `JOIN teachers t ON t.id = l.teacher_id`
-- (the USUAL teacher's row, to build original_teacher_name). The view
-- is security_invoker, so that join runs as the covering teacher, and
-- no policy let him read another teacher's row. An inner join to a row
-- you cannot see drops the whole schedule row. Found by impersonating
-- Bailey: occurrences 5, usual teacher row 0, schedule_view rows 0.
--
-- Fix: let a covering teacher read ONLY the teacher row(s) of the
-- usual teacher(s) whose lessons they are covering. `teachers` holds
-- no pay or contact data (instruments, studio_ids, room, Zoom link).
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Whose lessons am I covering?  SECURITY DEFINER, same pattern
--    as my_covered_lesson_ids(), so the policy below cannot recurse.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_covered_original_teacher_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY(
    SELECT DISTINCT l.teacher_id
      FROM lesson_occurrences lo
      JOIN lessons l ON l.id = lo.lesson_id
     WHERE lo.substitute_teacher_id = get_my_teacher_id()
  ), ARRAY[]::uuid[]);
$$;


-- ------------------------------------------------------------
-- 2. The policy
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "teacher_reads_covered_original_teacher" ON teachers;
CREATE POLICY "teacher_reads_covered_original_teacher" ON teachers FOR SELECT
  USING (id = ANY(my_covered_original_teacher_ids()));


NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — impersonate the covering teacher (replace the ids).
-- Expect: usual_teacher_row = 1 and schedule_rows = the number of
-- lessons being covered that day.
-- ============================================================
-- BEGIN;
--   SET LOCAL role TO authenticated;
--   SELECT set_config('request.jwt.claims',
--     json_build_object('sub','<covering-teacher-user-id>','role','authenticated')::text, true);
--   SELECT
--     (SELECT COUNT(*) FROM teachers WHERE id = '<usual-teacher-id>')   AS usual_teacher_row,
--     (SELECT COUNT(*) FROM schedule_view WHERE date = '<yyyy-mm-dd>')  AS schedule_rows;
-- ROLLBACK;


-- ============================================================
-- UNDO (only if ever needed)
-- ============================================================
-- DROP POLICY IF EXISTS "teacher_reads_covered_original_teacher" ON teachers;
-- DROP FUNCTION IF EXISTS my_covered_original_teacher_ids();
