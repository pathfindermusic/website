-- ============================================================
-- PATHFINDER PORTAL — fix a slow attendance-write RLS check
--
-- Why: teachers were getting "canceling statement due to
-- statement timeout" errors when saving attendance. Traced with
-- EXPLAIN ANALYZE (impersonating the affected teacher): the
-- "Teacher marks attendance for own lessons" policy on
-- attendance runs
--
--   SELECT lo.id FROM lesson_occurrences lo
--   JOIN lessons l ON l.id = lo.lesson_id
--   WHERE l.teacher_id = get_my_teacher_id()
--
-- as an ordinary subquery, which means it reads lesson_occurrences
-- and lessons through their OWN row-level security. Both tables
-- now carry several permissive SELECT policies each (teacher-own,
-- teacher-covering-as-substitute, student, admin), so every row
-- this subquery touches forces Postgres to also evaluate
-- my_covered_lesson_ids(), my_lesson_ids() and a second pass over
-- lessons for the student-ownership check — none of which have
-- anything to do with a teacher marking their own attendance.
--
-- For one teacher with 26 lesson series and ~2,900 historical
-- occurrences, that came out to 1.3 seconds and ~24,000 buffer
-- reads for a single check — measured directly, not estimated.
-- Every teacher pays some version of this cost, and it only grows
-- as lesson_occurrences accumulates more history; hers was just
-- the first to tip over the statement timeout.
--
-- The fix follows the same pattern already used for substitute
-- coverage (my_covered_occurrence_ids(), phase5-substitute-
-- access.sql) and for students (my_lesson_ids(), phase5-view-
-- rls.sql): a small SECURITY DEFINER function reads the
-- underlying tables WITHOUT row-level security re-applying, so
-- the join is a plain, cheap lookup instead of a five-policy-OR
-- per row. STABLE means it is only evaluated once per statement.
--
-- No data changes. No visibility changes — a teacher can still
-- see and mark attendance for exactly the same lessons as before,
-- just via a much cheaper check.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The occurrences a teacher owns as the REGULAR (not
--    substitute) teacher — same pattern as my_covered_occurrence_ids().
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_owned_occurrence_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY(
    SELECT lo.id FROM lesson_occurrences lo
     JOIN lessons l ON l.id = lo.lesson_id
     WHERE l.teacher_id = get_my_teacher_id()
  ), ARRAY[]::uuid[]);
$$;


-- ------------------------------------------------------------
-- 2. Swap the attendance policy to use it. Same access, cheaper
--    check — USING and WITH CHECK both scoped identically, same
--    as before (this policy never had an explicit WITH CHECK;
--    give it one explicitly this time rather than relying on
--    Postgres defaulting to USING, to keep write and read scope
--    visibly in sync).
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Teacher marks attendance for own lessons" ON attendance;
CREATE POLICY "Teacher marks attendance for own lessons"
  ON attendance FOR ALL
  USING      (lesson_occurrence_id = ANY(my_owned_occurrence_ids()))
  WITH CHECK (lesson_occurrence_id = ANY(my_owned_occurrence_ids()));


-- ============================================================
-- VERIFY — impersonate the previously-affected teacher and time it.
--
-- Should now return in well under 100ms (compare to 1333ms
-- before), and rows should match her actual occurrence count.
-- ============================================================
-- BEGIN;
--   SET LOCAL role TO authenticated;
--   SET LOCAL request.jwt.claims TO '{"sub":"<her-user-id>","role":"authenticated"}';
--   EXPLAIN (ANALYZE, BUFFERS) SELECT unnest(my_owned_occurrence_ids());
-- ROLLBACK;

-- Then have her actually try marking attendance again in the portal.

-- Policy is in place and matches expectations:
SELECT policyname, cmd, qual, with_check
  FROM pg_policies
 WHERE tablename = 'attendance'
 ORDER BY policyname;


-- ============================================================
-- REVERT — if anything looks wrong
-- ============================================================
-- DROP POLICY IF EXISTS "Teacher marks attendance for own lessons" ON attendance;
-- CREATE POLICY "Teacher marks attendance for own lessons"
--   ON attendance FOR ALL
--   USING (
--     lesson_occurrence_id IN (
--       SELECT lo.id FROM lesson_occurrences lo
--       JOIN lessons l ON l.id = lo.lesson_id
--       WHERE l.teacher_id = get_my_teacher_id()
--     )
--   );
