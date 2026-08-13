-- ============================================================
-- PATHFINDER PORTAL — RLS on the two views
--
-- Closes two Supabase lints: schedule_view and
-- student_schedule_view ran as their owner, so RLS on the
-- underlying tables did not apply. Either could be queried
-- directly with the anon key — which ships in the browser — and
-- would return every lesson, student name and attendance record
-- across both studios.
--
-- This file records what actually worked. An earlier version
-- added nine broad policies at once and locked everyone out of
-- the portal; the method below finds the minimum needed instead.
--
-- ⚠ Run ONE STATEMENT AT A TIME and read each result.
-- ============================================================


-- ============================================================
-- METHOD
--
-- Do not guess which policies are needed. Impersonate each role
-- and count what they can actually read. Any table returning 0
-- is a table that role cannot see, and the views inner-join
-- lessons, teachers, profiles and studios — so a single zero on
-- any of those empties the whole view.
--
--   BEGIN;
--     SET LOCAL role TO authenticated;
--     SET LOCAL request.jwt.claims TO
--       '{"sub":"<user-id>","role":"authenticated"}';
--
--     SELECT 'lessons' AS t, COUNT(*) FROM lessons
--     UNION ALL SELECT 'lesson_occurrences', COUNT(*) FROM lesson_occurrences
--     UNION ALL SELECT 'lesson_students',    COUNT(*) FROM lesson_students
--     UNION ALL SELECT 'attendance',         COUNT(*) FROM attendance
--     UNION ALL SELECT 'lesson_notes',       COUNT(*) FROM lesson_notes
--     UNION ALL SELECT 'students',           COUNT(*) FROM students
--     UNION ALL SELECT 'profiles',           COUNT(*) FROM profiles
--     UNION ALL SELECT 'teachers',           COUNT(*) FROM teachers
--     UNION ALL SELECT 'studios',            COUNT(*) FROM studios;
--   ROLLBACK;
--
-- Use the user_id, not the student_id — that is what auth.uid()
-- returns.
--
-- Result when this was done:
--   Students  → lessons, lesson_occurrences, attendance,
--               lesson_notes all returned 0. Four policies needed.
--   Teachers  → no zeros. Nothing needed.
--   Admins    → no zeros. Nothing needed.
-- ============================================================


-- ============================================================
-- STEP 1 — a student's own lesson ids, without recursion
--
-- The obvious policy — "lessons I appear in via lesson_students"
-- — deadlocks: lessons reads lesson_students, whose own policy
-- reads lessons. Postgres reports:
--   42P17: infinite recursion detected in policy
--
-- SECURITY DEFINER breaks the cycle, because the function reads
-- lesson_students with RLS not applied. Same pattern as
-- get_my_teacher_id() and get_my_studio_ids(), which is why
-- those never had this problem.
-- ============================================================
CREATE OR REPLACE FUNCTION my_lesson_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY(
    SELECT ls.lesson_id
      FROM lesson_students ls
      JOIN students s ON s.id = ls.student_id
     WHERE s.user_id = auth.uid()
  ), ARRAY[]::uuid[]);
$$;

-- Check it before building on it — impersonate a student and
-- confirm the array matches their lesson_students rows:
--   SELECT my_lesson_ids();


-- ============================================================
-- STEP 2 — the four policies students were missing
--
-- Narrow by design: each reaches only the student's own records,
-- and none calls get_my_role(), so no recursion is possible.
-- ============================================================

CREATE POLICY "student_reads_own_lessons" ON lessons FOR SELECT
  USING (id = ANY(my_lesson_ids()));

CREATE POLICY "student_reads_own_occurrences" ON lesson_occurrences FOR SELECT
  USING (lesson_id = ANY(my_lesson_ids()));

CREATE POLICY "student_reads_own_attendance" ON attendance FOR SELECT
  USING (student_id IN (SELECT id FROM students WHERE user_id = auth.uid()));

CREATE POLICY "student_reads_own_notes" ON lesson_notes FOR SELECT
  USING (
    lesson_occurrence_id IN (
      SELECT id FROM lesson_occurrences WHERE lesson_id = ANY(my_lesson_ids())
    )
  );


-- ============================================================
-- STEP 3 — re-run the diagnostic as a student
--
-- Every table must be non-zero before going further. A zero here
-- becomes an empty dashboard in the next step.
--
-- lesson_notes returning 0 may be correct: it means no teacher
-- has written a note on that student's lessons. Confirm by
-- checking whether any note belongs to one of their lessons
-- before assuming the policy is wrong.
-- ============================================================


-- ============================================================
-- STEP 4 — only now, switch the views
-- ============================================================
ALTER VIEW student_schedule_view SET (security_invoker = on);

ALTER VIEW schedule_view SET (security_invoker = on);

-- Revert instantly if a dashboard goes blank:
--   ALTER VIEW <name> SET (security_invoker = off);


-- ============================================================
-- STEP 5 — check every role in the browser
--
--   Student    My Lessons, Practice Notes, Attendance, My Progress
--   Teacher    dashboard, attendance marking, My Students
--   Admin      Schedule, Lessons in all three views, Teacher detail
--   Superuser  Schedule, Studios, Admins
--
-- A missing policy shows as an empty list, not an error.
-- ============================================================
SELECT c.relname,
       COALESCE((SELECT option_value FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'security_invoker'), 'off') AS security_invoker
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'v'
 ORDER BY c.relname;


-- ============================================================
-- STILL OPEN — admins are not studio-scoped
--
-- A Kilsyth admin reads Ringwood's lessons and students: the
-- policies on those tables test the role, not the studio. Some
-- page queries filter by studio, so the dashboards look right,
-- but the database does not enforce it.
--
-- The requirement says admins should be restricted to their
-- assigned studios. get_my_studio_ids() already exists and the
-- tasks policies use it — the same could be applied here, but it
-- is a behavioural change and wants deciding, not assuming.
-- ============================================================
