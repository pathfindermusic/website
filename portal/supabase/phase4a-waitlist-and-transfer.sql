-- ============================================================
-- PATHFINDER PORTAL — Phase 4a addendum
--   1. Waitlist entries, tracked as a kind of task
--   2. Tasks follow a student who moves studio
--
-- ⚠ Run one statement at a time and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. A waitlist entry is a task with an open-ended thread and no
--    due date. Without a distinct kind it would never appear in
--    the date-based buckets and would silently accumulate.
-- ------------------------------------------------------------
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'task';

ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_kind_valid;
ALTER TABLE tasks ADD CONSTRAINT tasks_kind_valid
  CHECK (kind IN ('task','waitlist'));

CREATE INDEX IF NOT EXISTS tasks_kind_idx ON tasks (kind, status);


-- ------------------------------------------------------------
-- 2. When a student moves studio, their open tasks move with
--    them. Otherwise the work stays with the old studio while
--    the student belongs to the new one.
--
--    Tasks are left UNASSIGNED so they land in the receiving
--    studio's queue rather than being pushed at one named admin
--    who may not be the right person.
--
--    Closed tasks stay put — they are history, and moving them
--    would rewrite where the work actually happened.
--
--    SECURITY DEFINER because the trigger writes to tasks on
--    behalf of whoever edited the student.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION move_student_tasks_on_studio_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.studio_id IS DISTINCT FROM OLD.studio_id THEN

    -- Trail first, so the reason survives even though the tasks
    -- are about to leave the editing admin's reach.
    INSERT INTO task_handovers (task_id, from_user, to_user, to_studio, note, moved_by)
    SELECT t.id, t.assigned_to, NULL, NEW.studio_id,
           'Student moved studio — task followed automatically',
           auth.uid()
      FROM tasks t
     WHERE t.subject_type = 'student'
       AND t.subject_id   = NEW.id
       AND t.status       = 'open';

    UPDATE tasks
       SET studio_id   = NEW.studio_id,
           assigned_to = NULL
     WHERE subject_type = 'student'
       AND subject_id   = NEW.id
       AND status       = 'open';

  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS students_studio_change_moves_tasks ON students;

CREATE TRIGGER students_studio_change_moves_tasks
  AFTER UPDATE OF studio_id ON students
  FOR EACH ROW
  EXECUTE FUNCTION move_student_tasks_on_studio_change();


-- ------------------------------------------------------------
-- 3. Tell PostgREST about the new column.
--    Supabase caches the schema, and until it refreshes, any write
--    including `kind` fails with:
--      "Could not find the 'kind' column of 'tasks' in the schema cache"
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY
-- ============================================================
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'tasks' AND column_name = 'kind';

SELECT tgname, tgenabled
  FROM pg_trigger
 WHERE tgrelid = 'students'::regclass AND NOT tgisinternal;

-- Optional: move a student and confirm their open tasks follow.
-- Wrapped in a rollback, so nothing is kept.
-- BEGIN;
--   UPDATE students SET studio_id = '<other-studio-id>' WHERE id = '<student-id>';
--   SELECT title, studio_id, assigned_to, status FROM tasks
--    WHERE subject_type = 'student' AND subject_id = '<student-id>';
-- ROLLBACK;
