-- ============================================================
-- Admins must be able to see each other
--
-- The admins table previously had only a superuser policy, so an
-- admin could not read it at all. That made task assignment and
-- handover impossible — the Assigned-to list showed only the
-- current user.
--
-- Read access only. Creating, editing and deleting admins stays
-- with the super user.
-- ============================================================

DROP POLICY IF EXISTS "Admins read other admins" ON admins;
CREATE POLICY "Admins read other admins"
  ON admins FOR SELECT
  USING (get_my_role() IN ('superuser','admin'));

-- Verify
SELECT tablename, policyname, cmd
  FROM pg_policies
 WHERE tablename = 'admins'
 ORDER BY policyname;

-- What an admin session would now see (run as superuser — this is
-- just a sanity check that the underlying data is there)
SELECT a.id, p.first_name, p.last_name, p.status, a.studio_ids
  FROM admins a
  JOIN profiles p ON p.id = a.user_id
 ORDER BY p.first_name;
