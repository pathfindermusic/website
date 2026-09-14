-- ============================================================
-- PATHFINDER PORTAL — Phase 6c: teacher-added custom artefacts
--
-- Teachers asked: a student wants to learn a specific song, or work
-- on a technique, that isn't in the Artefact Library yet. Rather than
-- block them or make them type free text that never becomes a proper
-- record, a teacher can now add it themselves from the lesson-note
-- picker. It's saved as a real bok_artefacts row — same shape as
-- anything an admin adds — but:
--   * is_custom = true        marks where it came from
--   * is_active = false       keeps it OUT of every other teacher's
--                             picker until an admin has looked at it
-- It still shows correctly in THIS lesson's note, materials list,
-- and the "Last lesson" recap right away, same as any other artefact
-- — those all read by occurrence, not by is_active.
--
-- Admins see pending items on the Artefact Library page (flagged
-- "Pending review", not lumped in with retired items) and can edit,
-- reclassify and activate them like anything else — activation is
-- still admin-only.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. New column
-- ------------------------------------------------------------
ALTER TABLE bok_artefacts
  ADD COLUMN IF NOT EXISTS is_custom boolean NOT NULL DEFAULT false;


-- ------------------------------------------------------------
-- 2. SELECT — extend the existing policy so a teacher can read
--    their own just-created pending item back (needed for the
--    insert().select() the UI does immediately after creating it,
--    and for it to render in their own picker/history before an
--    admin ever touches it). Everything else about this policy is
--    unchanged from phase6b.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Anyone signed in reads active or own-history artefacts" ON bok_artefacts;

CREATE POLICY "Anyone signed in reads active, own-created, or own-history artefacts"
  ON bok_artefacts FOR SELECT
  USING (
    is_active
    OR get_my_role() IN ('superuser','admin')
    OR created_by = auth.uid()
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


-- ------------------------------------------------------------
-- 3. INSERT — a teacher may add a custom artefact for themself,
--    always landing inactive/pending. (Admins keep inserting via
--    the existing "Admins manage artefacts" ALL policy below —
--    unchanged.)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Teachers add custom artefacts" ON bok_artefacts;

CREATE POLICY "Teachers add custom artefacts"
  ON bok_artefacts FOR INSERT
  WITH CHECK (
    get_my_role() = 'teacher'
    AND is_custom = true
    AND is_active = false
    AND created_by = auth.uid()
  );


-- ------------------------------------------------------------
-- 4. UPDATE — a teacher may edit their own pending (not yet
--    activated) custom artefact, e.g. fix a typo before an admin
--    reviews it. They can't flip is_active themselves — only an
--    admin can promote it — and once it IS activated, editing
--    moves to admin-only (USING requires is_active = false too).
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Teachers update own pending custom artefacts" ON bok_artefacts;

CREATE POLICY "Teachers update own pending custom artefacts"
  ON bok_artefacts FOR UPDATE
  USING (
    get_my_role() = 'teacher'
    AND is_custom = true
    AND is_active = false
    AND created_by = auth.uid()
  )
  WITH CHECK (
    get_my_role() = 'teacher'
    AND is_custom = true
    AND is_active = false
    AND created_by = auth.uid()
  );

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY
-- ============================================================

-- a. Column exists
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'bok_artefacts' AND column_name = 'is_custom';

-- b. Policies on bok_artefacts — expect 5: the 4 above still listed
--    the same way, plus "Admins manage artefacts" (FOR ALL) unchanged
--    from phase6-bok-grading.sql
SELECT policyname, cmd
  FROM pg_policies
 WHERE tablename = 'bok_artefacts'
 ORDER BY policyname;
