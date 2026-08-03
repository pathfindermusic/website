-- ============================================================
-- Task handover as an explicit operation
--
-- Moving a task to another studio was refused by RLS even with a
-- WITH CHECK that evaluated true in the same session — behaviour
-- we could not account for. Rather than keep working around it,
-- handover becomes a defined operation with its own rules, which
-- is a better fit anyway: it is not an arbitrary field edit.
--
-- SECURITY DEFINER means RLS does not apply inside the function,
-- so the checks below ARE the security boundary. They are
-- deliberately explicit.
-- ============================================================

CREATE OR REPLACE FUNCTION hand_over_task(
  p_task_id   uuid,
  p_to_studio uuid,
  p_to_user   uuid DEFAULT NULL,
  p_note      text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role        text;
  v_my_studios  uuid[];
  v_task        tasks%ROWTYPE;
BEGIN
  v_role := get_my_role();
  IF v_role NOT IN ('superuser','admin') THEN
    RAISE EXCEPTION 'Only admins can hand over a task';
  END IF;

  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task not found';
  END IF;

  -- The caller must currently hold the task. This reproduces the
  -- USING half of the policy, which RLS would normally enforce.
  v_my_studios := get_my_studio_ids();
  IF v_role <> 'superuser'
     AND v_task.studio_id IS NOT NULL
     AND NOT (v_task.studio_id = ANY(v_my_studios)) THEN
    RAISE EXCEPTION 'That task belongs to another studio';
  END IF;

  -- Destination must be a real, active studio (or NULL for generic)
  IF p_to_studio IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM studios WHERE id = p_to_studio AND status = 'active') THEN
    RAISE EXCEPTION 'Destination studio not found';
  END IF;

  -- Assignee, if given, must be an admin
  IF p_to_user IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM profiles WHERE id = p_to_user AND role IN ('admin','superuser')
     ) THEN
    RAISE EXCEPTION 'Tasks can only be assigned to an admin';
  END IF;

  -- Trail first: once the task moves it may be beyond the caller's reach
  INSERT INTO task_handovers (task_id, from_user, to_user, to_studio, note, moved_by)
  VALUES (p_task_id, v_task.assigned_to, p_to_user, p_to_studio, p_note, auth.uid());

  UPDATE tasks
     SET studio_id   = p_to_studio,
         assigned_to = p_to_user
   WHERE id = p_task_id;
END $$;

REVOKE ALL ON FUNCTION hand_over_task(uuid, uuid, uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION hand_over_task(uuid, uuid, uuid, text) TO authenticated;


-- ------------------------------------------------------------
-- Test as the Kilsyth admin — should succeed
-- ------------------------------------------------------------
BEGIN;
  SET LOCAL role TO authenticated;
  SET LOCAL request.jwt.claims TO
    '{"sub":"6d3e58da-8ef6-4f96-85f3-9e4da563a3a5","role":"authenticated"}';

  SELECT hand_over_task(
    'c6bc112b-5b82-414b-bdf3-8e0325e8d21d',
    'ad448a98-8ed5-4ecd-bed7-f00f9bfcfcff',
    '9ec86483-4e89-4d21-9eac-2b40922f92ef',
    'Test handover'
  );

  SELECT id, title, studio_id, assigned_to FROM tasks
   WHERE id = 'c6bc112b-5b82-414b-bdf3-8e0325e8d21d';
ROLLBACK;
