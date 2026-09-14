-- ============================================================
-- PATHFINDER PORTAL — Phase 6b: fix retired artefacts vanishing
-- from history
--
-- Bug in phase6-bok-grading.sql: "Anyone signed in reads active
-- artefacts" only allowed is_active=true rows through for anyone
-- but an admin. That was meant to stop a RETIRED artefact being
-- offered for a NEW lesson — it did that, but it also hid the row
-- entirely from a teacher or student looking at a PAST lesson that
-- already used it. The join in the materials list would silently
-- return nothing for that artefact once it was retired: an ex
-- reading their own history sees an artefact quietly disappear.
--
-- Fix: a signed-in teacher/student can also read a retired artefact
-- if it's linked (via lesson_occurrence_artefacts) to an occurrence
-- they can already see — their own lesson as student, or their own
-- taught lesson as teacher. Nothing new is offered for picking; only
-- what's already on the record stays readable.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================

DROP POLICY IF EXISTS "Anyone signed in reads active artefacts" ON bok_artefacts;

CREATE POLICY "Anyone signed in reads active or own-history artefacts"
  ON bok_artefacts FOR SELECT
  USING (
    is_active
    OR get_my_role() IN ('superuser','admin')
    OR id IN (
      SELECT loa.artefact_id
        FROM lesson_occurrence_artefacts loa
       WHERE loa.occurrence_id IN (
               SELECT id FROM lesson_occurrences WHERE lesson_id = ANY(my_lesson_ids())
             )
          OR loa.occurrence_id IN (
               SELECT lo.id FROM lesson_occurrences lo
                 JOIN lessons l ON l.id = lo.lesson_id
                WHERE l.teacher_id = get_my_teacher_id()
             )
    )
  );

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY
-- ============================================================
SELECT tablename, policyname, cmd
  FROM pg_policies
 WHERE tablename = 'bok_artefacts'
 ORDER BY policyname;
