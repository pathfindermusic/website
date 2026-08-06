-- ============================================================
-- PATHFINDER PORTAL — Phase 4c: Enrolment processes
--
-- Three fixed checklists, each an instance attached to a student:
--   trial_confirmation  — a trial has been booked
--   ongoing_enrolment   — enrolling in ongoing lessons
--   end_enrolment       — leaving
--
-- Items the portal can verify itself are evaluated LIVE rather
-- than stored, because they become true after the process starts
-- ("added a trial lesson" is not true at the moment of booking).
--
-- An item can be BLOCKED with a linked task, for the eWay case:
-- previously an admin would tick it anyway and track the real work
-- separately, which loses the one thing the checklist is for.
--
-- ⚠ Run one statement at a time and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Process instances
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_processes (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references students(id) on delete cascade,
  process_type  text not null
                  check (process_type in ('trial_confirmation','ongoing_enrolment','end_enrolment')),
  status        text not null default 'in_progress'
                  check (status in ('in_progress','complete','abandoned')),
  started_by    uuid,
  started_at    timestamptz not null default now(),
  completed_at  timestamptz
);

CREATE INDEX IF NOT EXISTS student_processes_student_idx
  ON student_processes (student_id, status);


-- ------------------------------------------------------------
-- 2. Items
--
--    label is stored per instance rather than referenced from a
--    template, so changing a checklist later does not rewrite
--    what an admin actually ticked months ago.
--
--    auto_key names a check the portal performs itself. NULL means
--    an admin must tick it.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS process_items (
  id              uuid primary key default gen_random_uuid(),
  process_id      uuid not null references student_processes(id) on delete cascade,
  item_order      int  not null,
  label           text not null,
  auto_key        text,
  is_done         boolean not null default false,
  done_by         uuid,
  done_at         timestamptz,
  blocked_task_id uuid references tasks(id) on delete set null,
  unique (process_id, item_order)
);

CREATE INDEX IF NOT EXISTS process_items_process_idx ON process_items (process_id, item_order);


-- ------------------------------------------------------------
-- 3. Row Level Security — same studio scoping as the student
-- ------------------------------------------------------------
ALTER TABLE student_processes ENABLE ROW LEVEL SECURITY;
ALTER TABLE process_items     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage student processes" ON student_processes;
CREATE POLICY "Admins manage student processes"
  ON student_processes FOR ALL
  USING (get_my_role() IN ('superuser','admin'))
  WITH CHECK (get_my_role() IN ('superuser','admin'));

-- Note: process_items references its parent, but deliberately does
-- NOT subquery student_processes here. A policy that reads another
-- RLS-protected table inherits that table's visibility, which has
-- caused silent failures before.
DROP POLICY IF EXISTS "Admins manage process items" ON process_items;
CREATE POLICY "Admins manage process items"
  ON process_items FOR ALL
  USING (get_my_role() IN ('superuser','admin'))
  WITH CHECK (get_my_role() IN ('superuser','admin'));


-- ------------------------------------------------------------
-- 4. PostgREST caches the schema
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT table_name FROM information_schema.tables
 WHERE table_name IN ('student_processes','process_items')
 ORDER BY table_name;

SELECT tablename, policyname, cmd
  FROM pg_policies
 WHERE tablename IN ('student_processes','process_items')
 ORDER BY tablename;
