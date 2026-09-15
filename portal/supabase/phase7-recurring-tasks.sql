-- ============================================================
-- PATHFINDER PORTAL — Phase 7: Recurring tasks
--
-- Lets an admin define a repeating rule (e.g. "weekly manual
-- payment collection", "cancel lessons on the 1st Monday of each
-- month for these students") instead of re-creating the same task
-- by hand every cycle.
--
-- Three new tables:
--   recurring_tasks          — the rule itself (title, schedule,
--                               default studio/assignee)
--   recurring_task_subjects  — 0+ students/teachers the rule is
--                               about; 0 means a generic task
--   recurring_task_runs      — idempotency log, so a rule that has
--                               already fired for a given date (and
--                               subject) is never fired twice
--
-- Generation happens server-side (a scheduled Netlify function),
-- the morning a rule is due — see generate-recurring-tasks.js.
-- This migration only lays the schema and RLS down; it does not
-- generate anything itself.
--
-- ⚠ RUN ONE STATEMENT AT A TIME, and check each result before the
-- next. The RLS policies below follow the same subquery pattern as
-- task_notes/task_handovers (querying the DIFFERENT, already
-- RLS-protected parent table) — the established safe pattern in
-- this codebase. A policy that instead subqueries its own table has
-- previously applied partially with no error to show it.
--
-- Safe to re-run.
-- ============================================================


-- ------------------------------------------------------------
-- 1. recurring_tasks — the rule
--
--    recurrence_type drives which of the schedule fields matter:
--      daily            — none
--      weekly           — weekday
--      monthly_day      — day_of_month (1–31, or -1 for "last day
--                         of the month"; a day beyond the length of
--                         a shorter month also falls back to that
--                         month's last day, so 31 still fires in
--                         February)
--      monthly_weekday  — weekday + week_of_month (1–4 for the 1st
--                         .. 4th occurrence, or -1 for the last
--                         occurrence in the month)
--
--    weekday follows JS's Date.getDay() convention (0 = Sunday .. 6
--    = Saturday), matching DAY_NAMES already used elsewhere in this
--    codebase (send-lesson-reminders.js), so the same lookup table
--    reads correctly on both sides.
--
--    studio_id / assigned_to are the defaults copied onto every
--    task this rule generates — same semantics as tasks.studio_id /
--    tasks.assigned_to (NULL studio_id = shared queue across every
--    admin; NULL assigned_to = studio queue, unassigned).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recurring_tasks (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  studio_id        uuid references studios(id) on delete set null,
  assigned_to      uuid,                     -- profiles.id, NULL = studio queue

  recurrence_type  text not null
                     check (recurrence_type in ('daily','weekly','monthly_day','monthly_weekday')),
  weekday          int,                      -- 0=Sunday .. 6=Saturday
  day_of_month     int,                      -- 1..31, or -1 = last day of month
  week_of_month    int,                      -- 1..4, or -1 = last occurrence

  is_active        boolean not null default true,

  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint recurring_tasks_weekday_range
    check (weekday is null or weekday between 0 and 6),
  constraint recurring_tasks_day_of_month_range
    check (day_of_month is null or day_of_month = -1 or day_of_month between 1 and 31),
  constraint recurring_tasks_week_of_month_range
    check (week_of_month is null or week_of_month = -1 or week_of_month between 1 and 4),

  -- Each type carries exactly the fields it needs — catches a rule
  -- saved with the wrong sub-fields (or none at all) at write time
  -- rather than silently never firing.
  constraint recurring_tasks_fields_match_type check (
    (recurrence_type = 'daily'
      and weekday is null and day_of_month is null and week_of_month is null)
    or
    (recurrence_type = 'weekly'
      and weekday is not null and day_of_month is null and week_of_month is null)
    or
    (recurrence_type = 'monthly_day'
      and weekday is null and day_of_month is not null and week_of_month is null)
    or
    (recurrence_type = 'monthly_weekday'
      and weekday is not null and day_of_month is null and week_of_month is not null)
  )
);

CREATE INDEX IF NOT EXISTS recurring_tasks_studio_idx  ON recurring_tasks (studio_id);
CREATE INDEX IF NOT EXISTS recurring_tasks_active_idx  ON recurring_tasks (is_active);

CREATE OR REPLACE FUNCTION touch_recurring_task_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS recurring_tasks_touch_updated_at ON recurring_tasks;
CREATE TRIGGER recurring_tasks_touch_updated_at
  BEFORE UPDATE ON recurring_tasks
  FOR EACH ROW EXECUTE FUNCTION touch_recurring_task_updated_at();


-- ------------------------------------------------------------
-- 2. recurring_task_subjects — 0+ students/teachers a rule is about
--
--    No rows at all = a generic task (no subject), generated once
--    per firing. One or more rows = one task generated PER subject
--    per firing (the admin's chosen "one task per student" design),
--    each carrying that subject's subject_type/subject_id.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recurring_task_subjects (
  id                 uuid primary key default gen_random_uuid(),
  recurring_task_id  uuid not null references recurring_tasks(id) on delete cascade,
  subject_type       text not null check (subject_type in ('student','teacher')),
  subject_id         uuid not null,

  unique (recurring_task_id, subject_type, subject_id)
);

CREATE INDEX IF NOT EXISTS recurring_task_subjects_rule_idx
  ON recurring_task_subjects (recurring_task_id);


-- ------------------------------------------------------------
-- 3. recurring_task_runs — idempotency log
--
--    One row per (rule, date, subject) that has already generated
--    a task. Checked before every insert so a schedule that fires
--    twice, or is re-run manually, never duplicates a task.
--
--    subject_type/subject_id use non-null sentinel defaults rather
--    than NULL — Postgres never treats two NULLs as equal inside a
--    UNIQUE constraint, so a nullable pair here would silently let
--    the generic (no-subject) case duplicate on every re-run.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recurring_task_runs (
  id                 uuid primary key default gen_random_uuid(),
  recurring_task_id  uuid not null references recurring_tasks(id) on delete cascade,
  run_date           date not null,
  subject_type       text not null default 'none'
                       check (subject_type in ('student','teacher','none')),
  subject_id         uuid not null default '00000000-0000-0000-0000-000000000000',
  task_id            uuid references tasks(id) on delete set null,
  created_at         timestamptz not null default now(),

  unique (recurring_task_id, run_date, subject_type, subject_id)
);

CREATE INDEX IF NOT EXISTS recurring_task_runs_rule_idx ON recurring_task_runs (recurring_task_id, run_date);


-- ------------------------------------------------------------
-- 4. tasks — link back to the rule that generated it, and allow
--    'recurring' as a source alongside the existing values.
-- ------------------------------------------------------------
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS recurring_task_id uuid references recurring_tasks(id) on delete set null;

CREATE INDEX IF NOT EXISTS tasks_recurring_task_idx ON tasks (recurring_task_id);

ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_source_check;
ALTER TABLE tasks ADD CONSTRAINT tasks_source_check
  CHECK (source IN ('manual','process','system','recurring'));


-- ------------------------------------------------------------
-- 5. Row Level Security — admin/superuser only. Recurring rules
--    are a front-desk management concern; teachers never see or
--    manage them (the tasks they generate follow the existing
--    tasks RLS/visibility rules unchanged).
--
--    recurring_tasks reuses can_see_task(studio_id, assigned_to)
--    (from phase4a-task-visibility.sql) — the same studio/assignee
--    visibility a plain task already gets, so a rule scoped to one
--    studio is invisible to an admin who doesn't cover it.
-- ------------------------------------------------------------
ALTER TABLE recurring_tasks          ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_task_subjects  ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_task_runs      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "recurring_tasks_admin_read" ON recurring_tasks;
CREATE POLICY "recurring_tasks_admin_read" ON recurring_tasks FOR SELECT
  USING (can_see_task(studio_id, assigned_to));

DROP POLICY IF EXISTS "recurring_tasks_admin_insert" ON recurring_tasks;
CREATE POLICY "recurring_tasks_admin_insert" ON recurring_tasks FOR INSERT
  WITH CHECK (get_my_role() IN ('superuser','admin'));

DROP POLICY IF EXISTS "recurring_tasks_admin_update" ON recurring_tasks;
CREATE POLICY "recurring_tasks_admin_update" ON recurring_tasks FOR UPDATE
  USING (can_see_task(studio_id, assigned_to))
  WITH CHECK (get_my_role() IN ('superuser','admin'));

DROP POLICY IF EXISTS "recurring_tasks_admin_delete" ON recurring_tasks;
CREATE POLICY "recurring_tasks_admin_delete" ON recurring_tasks FOR DELETE
  USING (can_see_task(studio_id, assigned_to));

-- Subjects and runs follow the visibility of their parent rule —
-- subquerying recurring_tasks (a different, already RLS-protected
-- table), not themselves.
DROP POLICY IF EXISTS "recurring_task_subjects_admin_all" ON recurring_task_subjects;
CREATE POLICY "recurring_task_subjects_admin_all" ON recurring_task_subjects FOR ALL
  USING (
    get_my_role() IN ('superuser','admin')
    AND recurring_task_id IN (SELECT id FROM recurring_tasks)
  )
  WITH CHECK (
    get_my_role() IN ('superuser','admin')
    AND recurring_task_id IN (SELECT id FROM recurring_tasks)
  );

DROP POLICY IF EXISTS "recurring_task_runs_admin_read" ON recurring_task_runs;
CREATE POLICY "recurring_task_runs_admin_read" ON recurring_task_runs FOR SELECT
  USING (
    get_my_role() IN ('superuser','admin')
    AND recurring_task_id IN (SELECT id FROM recurring_tasks)
  );

-- No admin insert/update/delete policy on recurring_task_runs on
-- purpose — it is written only by the scheduled function, via the
-- service_role key, which bypasses RLS entirely. Admins only ever
-- need to read it (and normally won't — it's a log, not a UI).


-- ------------------------------------------------------------
-- 6. Tell PostgREST about the new table/column.
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — do not skip.
-- ============================================================
SELECT table_name
  FROM information_schema.tables
 WHERE table_name IN ('recurring_tasks','recurring_task_subjects','recurring_task_runs')
 ORDER BY table_name;

SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'tasks' AND column_name = 'recurring_task_id';

SELECT conname, pg_get_constraintdef(oid)
  FROM pg_constraint
 WHERE conrelid = 'tasks'::regclass AND conname = 'tasks_source_check';

SELECT tablename, policyname, cmd, qual, with_check
  FROM pg_policies
 WHERE tablename IN ('recurring_tasks','recurring_task_subjects','recurring_task_runs')
 ORDER BY tablename, policyname;

-- Expect exactly 4 policies on recurring_tasks (read/insert/update/delete),
-- 1 on recurring_task_subjects (ALL), 1 on recurring_task_runs (SELECT).
