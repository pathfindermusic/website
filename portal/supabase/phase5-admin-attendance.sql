-- ============================================================
-- PATHFINDER PORTAL — admins may mark attendance
--
-- When a permanent teacher is away, a substitute takes the
-- lesson. The substitute has no portal access, so an admin marks
-- the attendance on their behalf.
--
-- marked_by already records who did it, so the substitution
-- leaves a trail without any extra field.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================

-- What exists now?
SELECT policyname, cmd, qual, with_check
  FROM pg_policies
 WHERE tablename = 'attendance'
 ORDER BY policyname;


-- ------------------------------------------------------------
-- Admins and the super user can record and correct attendance.
-- Teachers keep their own policies; students keep read-only
-- access to their own records.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "admins manage attendance" ON attendance;
CREATE POLICY "admins manage attendance"
  ON attendance FOR ALL
  USING      (get_my_role() IN ('superuser','admin'))
  WITH CHECK (get_my_role() IN ('superuser','admin'));


-- Verify
SELECT policyname, cmd, qual, with_check
  FROM pg_policies
 WHERE tablename = 'attendance'
 ORDER BY policyname;
