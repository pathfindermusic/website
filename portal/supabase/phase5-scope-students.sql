-- ============================================================
-- PATHFINDER PORTAL — scope students to the admin's studios
--
-- Tasks have been studio-scoped since Phase 4a, but students and
-- enquiries were not: the policy tested the role, not the studio.
-- A Kilsyth admin therefore saw a Ringwood enquiry while its
-- follow-up task stayed hidden, and the Enquiries page reported
-- "Needs a task" for a task that existed perfectly well.
--
-- Admins now see only their own studios' students. Changing a
-- student's studio hands them over — the existing trigger on
-- students already moves their open tasks to the receiving
-- studio's queue.
--
-- Teachers and students are unaffected: their access is by
-- relationship, not by studio.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ⚠ Verify with STEP 3 before trusting it.
-- ============================================================


-- ============================================================
-- STEP 1 — what exists now
-- ============================================================
SELECT policyname, cmd, qual
  FROM pg_policies
 WHERE tablename = 'students'
 ORDER BY policyname;


-- ============================================================
-- STEP 2 — replace the role-based admin policy
--
-- get_my_studio_ids() returns every studio for a super user, and
-- an admin's assigned studios — or all of them if none are set.
-- It is SECURITY DEFINER, so no recursion is possible.
--
-- A student with no studio stays visible to everyone: better that
-- an unassigned record is seen by all than by nobody.
-- ============================================================

DROP POLICY IF EXISTS "Admins and superuser manage all students" ON students;

CREATE POLICY "admins_manage_students_in_their_studios"
  ON students FOR ALL
  USING (
    get_my_role() = 'superuser'
    OR (
      get_my_role() = 'admin'
      AND (studio_id IS NULL OR studio_id = ANY(get_my_studio_ids()))
    )
  )
  WITH CHECK (
    -- Role only, so an admin can hand a student to another studio.
    -- The same asymmetry as tasks: you can pass one out, but you
    -- cannot reach into another studio and take one.
    get_my_role() IN ('superuser','admin')
  );


-- ============================================================
-- STEP 3 — verify before relying on it
--
-- Substitute the real ids. Each admin should see only their own
-- studio's students; the super user should see all.
-- ============================================================

-- Admin Kilsyth
-- BEGIN;
--   SET LOCAL role TO authenticated;
--   SET LOCAL request.jwt.claims TO '{"sub":"<kilsyth-admin-user-id>","role":"authenticated"}';
--   SELECT st.name AS studio, s.status, COUNT(*)
--     FROM students s LEFT JOIN studios st ON st.id = s.studio_id
--    GROUP BY st.name, s.status ORDER BY st.name;
-- ROLLBACK;

-- Admin Ringwood
-- BEGIN;
--   SET LOCAL role TO authenticated;
--   SET LOCAL request.jwt.claims TO '{"sub":"<ringwood-admin-user-id>","role":"authenticated"}';
--   SELECT st.name AS studio, s.status, COUNT(*)
--     FROM students s LEFT JOIN studios st ON st.id = s.studio_id
--    GROUP BY st.name, s.status ORDER BY st.name;
-- ROLLBACK;

-- Super user — should see everything
-- BEGIN;
--   SET LOCAL role TO authenticated;
--   SET LOCAL request.jwt.claims TO '{"sub":"<superuser-user-id>","role":"authenticated"}';
--   SELECT COUNT(*) FROM students;
-- ROLLBACK;


-- ============================================================
-- STEP 4 — then check in the browser
--
--   Kilsyth admin   Students, Enquiries, Tasks — Kilsyth only
--   Ringwood admin  likewise
--   Super user      everything
--
-- And the handover: change a prospective student's studio on the
-- Students page. They should leave your list, and their open
-- tasks should follow — the trigger on students does that
-- already, and writes a handover record explaining why.
--
-- Revert if something is wrong:
--   DROP POLICY IF EXISTS "admins_manage_students_in_their_studios" ON students;
--   CREATE POLICY "Admins and superuser manage all students"
--     ON students FOR ALL
--     USING (get_my_role() IN ('superuser','admin'))
--     WITH CHECK (get_my_role() IN ('superuser','admin'));
-- ============================================================
