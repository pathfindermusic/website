-- ============================================================
-- Task visibility: assignment overrides a missing studio
--
-- An admin sees a task when ANY of these hold:
--   * it belongs to one of their studios
--   * it is assigned to them, whatever studio it sits in
--   * it has no studio AND no assignee — the shared queue
-- A super user sees everything.
--
-- WITH CHECK stays role-only, which is what allows handover to
-- another studio.
--
-- ⚠ RUN ONE STATEMENT AT A TIME.
-- Running several DDL statements together in the Supabase SQL
-- editor can apply partially — policy NAMES created while the
-- BODIES stay stale — with no error to show it. That cost a full
-- session to diagnose.
--
-- After each policy, re-read pg_policies and confirm `qual`
-- actually references can_see_task, not just that the name exists.
-- ============================================================


-- ------------------------------------------------------------
-- STEP 1 — the shared visibility expression
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION can_see_task(p_studio uuid, p_assignee uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    get_my_role() = 'superuser'
    OR (
      get_my_role() = 'admin' AND (
        p_studio = ANY(get_my_studio_ids())
        OR p_assignee = auth.uid()
        OR (p_studio IS NULL AND p_assignee IS NULL)
      )
    );
$$;


-- ------------------------------------------------------------
-- STEP 2 — remove the earlier FOR ALL policy if it survives.
-- Leftover permissive policies are additive and silent: an old
-- one will quietly widen access no matter what the new one says.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Admins manage tasks in their studios" ON tasks;


-- ------------------------------------------------------------
-- STEP 3 — SELECT
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "tasks_admin_read" ON tasks;

CREATE POLICY "tasks_admin_read" ON tasks FOR SELECT
  USING (can_see_task(studio_id, assigned_to));


-- ------------------------------------------------------------
-- STEP 4 — INSERT
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "tasks_admin_insert" ON tasks;

CREATE POLICY "tasks_admin_insert" ON tasks FOR INSERT
  WITH CHECK (get_my_role() IN ('superuser','admin'));


-- ------------------------------------------------------------
-- STEP 5 — UPDATE
--   USING      → the row as it stands (scoped)
--   WITH CHECK → the row afterwards (role only, so a task can be
--                handed OUT to another studio but not pulled IN)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "tasks_admin_update" ON tasks;

CREATE POLICY "tasks_admin_update" ON tasks FOR UPDATE
  USING (can_see_task(studio_id, assigned_to))
  WITH CHECK (get_my_role() IN ('superuser','admin'));


-- ------------------------------------------------------------
-- STEP 6 — DELETE
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "tasks_admin_delete" ON tasks;

CREATE POLICY "tasks_admin_delete" ON tasks FOR DELETE
  USING (can_see_task(studio_id, assigned_to));


-- ------------------------------------------------------------
-- STEP 7 — teacher read access, unchanged
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "tasks_teacher_read"      ON tasks;
DROP POLICY IF EXISTS "Teachers read own tasks" ON tasks;

CREATE POLICY "tasks_teacher_read" ON tasks FOR SELECT
  USING (subject_type = 'teacher' AND subject_id = get_my_teacher_id());


-- ============================================================
-- VERIFY — do not skip. Check the BODY, not just the name.
-- Every admin policy's qual must read can_see_task(...).
-- ============================================================
SELECT policyname, permissive, cmd, qual, with_check
  FROM pg_policies
 WHERE tablename = 'tasks'
 ORDER BY policyname;


-- What each admin can actually see. Substitute real user ids.
-- BEGIN;
--   SET LOCAL role TO authenticated;
--   SET LOCAL request.jwt.claims TO '{"sub":"<admin-user-id>","role":"authenticated"}';
--   SELECT title, studio_id, assigned_to FROM tasks ORDER BY created_at;
-- ROLLBACK;
