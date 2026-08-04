-- ============================================================
-- Teacher replies on tasks
--
-- A teacher could see a task about them but not respond, so the
-- admin had to chase by other means — exactly what the portal is
-- meant to remove.
--
-- Teachers can now add a note. They cannot close a task: the
-- admin keeps ownership and decides whether the reply settles it.
--
-- ⚠ Run one statement at a time and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Flag a task that a teacher has replied to.
--    Cleared when an admin responds or closes it.
-- ------------------------------------------------------------
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS awaiting_admin boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS tasks_awaiting_idx
  ON tasks (awaiting_admin) WHERE awaiting_admin;


-- ------------------------------------------------------------
-- 2. The reply itself.
--
--    SECURITY DEFINER because teachers deliberately have no write
--    access to tasks or task_notes. The checks below ARE the
--    boundary: a teacher may only reply to a task that is about
--    them, and may only add a note — nothing else changes.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION teacher_reply_to_task(
  p_task_id uuid,
  p_note    text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_teacher_id uuid;
BEGIN
  IF get_my_role() <> 'teacher' THEN
    RAISE EXCEPTION 'Only a teacher can reply this way';
  END IF;

  IF COALESCE(trim(p_note), '') = '' THEN
    RAISE EXCEPTION 'A reply cannot be empty';
  END IF;

  v_teacher_id := get_my_teacher_id();

  IF NOT EXISTS (
    SELECT 1 FROM tasks
     WHERE id = p_task_id
       AND subject_type = 'teacher'
       AND subject_id   = v_teacher_id
  ) THEN
    RAISE EXCEPTION 'That task is not about you';
  END IF;

  INSERT INTO task_notes (task_id, note_text, logged_by)
  VALUES (p_task_id, trim(p_note), auth.uid());

  UPDATE tasks SET awaiting_admin = true WHERE id = p_task_id;
END $$;

REVOKE ALL ON FUNCTION teacher_reply_to_task(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION teacher_reply_to_task(uuid, text) TO authenticated;


-- ------------------------------------------------------------
-- 3. Teachers must be able to read the names of whoever wrote
--    each note, or a reply thread reads as anonymous.
--    Limited to admins and super users — not other teachers or
--    students.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Teachers read admin names" ON profiles;
CREATE POLICY "Teachers read admin names"
  ON profiles FOR SELECT
  USING (
    get_my_role() = 'teacher'
    AND role IN ('admin','superuser')
  );


-- ------------------------------------------------------------
-- 4. PostgREST caches the schema; without this, writes including
--    the new column fail until it refreshes on its own.
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'tasks' AND column_name = 'awaiting_admin';

SELECT proname, prosecdef AS security_definer
  FROM pg_proc WHERE proname = 'teacher_reply_to_task';
