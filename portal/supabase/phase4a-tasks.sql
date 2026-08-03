-- ============================================================
-- PATHFINDER PORTAL — Phase 4a: Task management
--
-- Replaces Zoho tasks. Three tables:
--   tasks           — the work
--   task_notes      — the contact log; many notes per task
--   task_handovers  — who passed what to whom
--
-- Safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Helper: which studios does the current user administer?
--    Returns all studios for a super user, and for an admin
--    either their assigned studios or all if none are set
--    (an admin with an empty studio_ids has unrestricted access,
--    matching how the Admins page presents it).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_my_studio_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT CASE
    WHEN get_my_role() = 'superuser'
      THEN ARRAY(SELECT id FROM studios)
    WHEN get_my_role() = 'admin' THEN (
      SELECT CASE
        WHEN a.studio_ids IS NULL OR cardinality(a.studio_ids) = 0
          THEN ARRAY(SELECT id FROM studios)
        ELSE a.studio_ids
      END
      FROM admins a WHERE a.user_id = auth.uid()
    )
    ELSE ARRAY[]::uuid[]
  END;
$$;


-- ------------------------------------------------------------
-- 2. tasks
--    subject_type is 'student', 'teacher' or NULL (generic).
--    subject_id is deliberately not a foreign key: it points at
--    different tables depending on subject_type.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tasks (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  subject_type  text check (subject_type in ('student','teacher')),
  subject_id    uuid,
  studio_id     uuid references studios(id) on delete set null,
  assigned_to   uuid,                     -- profiles.id, NULL = studio queue
  due_date      date,
  status        text not null default 'open'
                  check (status in ('open','done','cancelled')),
  source        text not null default 'manual'
                  check (source in ('manual','process','system')),
  process_id    uuid,                     -- populated in stage 4c
  created_by    uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  completed_at  timestamptz,
  completed_by  uuid,

  constraint subject_pair_valid check (
    (subject_type is null and subject_id is null) or
    (subject_type is not null and subject_id is not null)
  )
);

CREATE INDEX IF NOT EXISTS tasks_studio_idx   ON tasks (studio_id);
CREATE INDEX IF NOT EXISTS tasks_assigned_idx ON tasks (assigned_to);
CREATE INDEX IF NOT EXISTS tasks_subject_idx  ON tasks (subject_type, subject_id);
CREATE INDEX IF NOT EXISTS tasks_open_due_idx ON tasks (status, due_date);


-- ------------------------------------------------------------
-- 3. task_notes — the contact log
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS task_notes (
  id             uuid primary key default gen_random_uuid(),
  task_id        uuid not null references tasks(id) on delete cascade,
  note_text      text not null,
  contact_method text check (contact_method in ('phone','email','sms','in_person')),
  outcome        text check (outcome in ('reached','unreachable','left_message')),
  logged_by      uuid,
  logged_at      timestamptz not null default now()
);

CREATE INDEX IF NOT EXISTS task_notes_task_idx ON task_notes (task_id, logged_at DESC);


-- ------------------------------------------------------------
-- 4. task_handovers
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS task_handovers (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references tasks(id) on delete cascade,
  from_user  uuid,
  to_user    uuid,
  to_studio  uuid references studios(id) on delete set null,
  note       text,
  moved_by   uuid,
  moved_at   timestamptz not null default now()
);

CREATE INDEX IF NOT EXISTS task_handovers_task_idx ON task_handovers (task_id, moved_at DESC);


-- ------------------------------------------------------------
-- 5. Keep updated_at current
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION touch_task_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tasks_touch_updated_at ON tasks;
CREATE TRIGGER tasks_touch_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION touch_task_updated_at();


-- ------------------------------------------------------------
-- 6. Row Level Security
-- ------------------------------------------------------------
ALTER TABLE tasks          ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_notes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_handovers ENABLE ROW LEVEL SECURITY;

-- Admins and the super user manage tasks in their studios.
-- Generic tasks (studio_id IS NULL) are visible to all admins.
DROP POLICY IF EXISTS "Admins manage tasks in their studios" ON tasks;
CREATE POLICY "Admins manage tasks in their studios"
  ON tasks FOR ALL
  USING (
    get_my_role() IN ('superuser','admin')
    AND (studio_id IS NULL OR studio_id = ANY(get_my_studio_ids()))
  )
  WITH CHECK (
    get_my_role() IN ('superuser','admin')
    AND (studio_id IS NULL OR studio_id = ANY(get_my_studio_ids()))
  );

-- Teachers may READ tasks about themselves. No write access.
DROP POLICY IF EXISTS "Teachers read own tasks" ON tasks;
CREATE POLICY "Teachers read own tasks"
  ON tasks FOR SELECT
  USING (
    subject_type = 'teacher'
    AND subject_id = get_my_teacher_id()
  );

-- Notes and handovers follow the visibility of their task.
DROP POLICY IF EXISTS "Admins manage task notes" ON task_notes;
CREATE POLICY "Admins manage task notes"
  ON task_notes FOR ALL
  USING (
    get_my_role() IN ('superuser','admin')
    AND task_id IN (SELECT id FROM tasks)
  )
  WITH CHECK (
    get_my_role() IN ('superuser','admin')
    AND task_id IN (SELECT id FROM tasks)
  );

DROP POLICY IF EXISTS "Teachers read own task notes" ON task_notes;
CREATE POLICY "Teachers read own task notes"
  ON task_notes FOR SELECT
  USING (
    task_id IN (
      SELECT id FROM tasks
       WHERE subject_type = 'teacher' AND subject_id = get_my_teacher_id()
    )
  );

DROP POLICY IF EXISTS "Admins manage task handovers" ON task_handovers;
CREATE POLICY "Admins manage task handovers"
  ON task_handovers FOR ALL
  USING (
    get_my_role() IN ('superuser','admin')
    AND task_id IN (SELECT id FROM tasks)
  )
  WITH CHECK (
    get_my_role() IN ('superuser','admin')
    AND task_id IN (SELECT id FROM tasks)
  );


-- ------------------------------------------------------------
-- 7. Verify
-- ------------------------------------------------------------
SELECT table_name
  FROM information_schema.tables
 WHERE table_name IN ('tasks','task_notes','task_handovers')
 ORDER BY table_name;

SELECT tablename, policyname, cmd
  FROM pg_policies
 WHERE tablename IN ('tasks','task_notes','task_handovers')
 ORDER BY tablename, policyname;
