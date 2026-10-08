-- ============================================================
-- Recurring tasks: optional description (migration #44)
--
-- A recurring rule can now carry a short description. When the
-- nightly generator (generate-recurring-tasks.js) creates a task from
-- the rule, it writes the description as the first entry in that
-- task's log (task_notes), so whoever picks the task up sees what it
-- is for.
--
-- Run each statement ONE AT A TIME in the Supabase SQL editor, BEFORE
-- deploying the new tasks.html — the editor saves a `description`
-- value with every rule, and saving fails until the column exists.
-- Safe to re-run.
-- ============================================================

-- STEP 1 — the column (nullable: existing rules simply have none)
ALTER TABLE recurring_tasks
  ADD COLUMN IF NOT EXISTS description text;

-- STEP 2 — keep it brief (the editor also limits the box to 1000)
ALTER TABLE recurring_tasks
  DROP CONSTRAINT IF EXISTS recurring_tasks_description_len;

ALTER TABLE recurring_tasks
  ADD CONSTRAINT recurring_tasks_description_len
  CHECK (description IS NULL OR char_length(description) <= 1000);

-- STEP 3 — tell PostgREST about the new column
NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- STEP 4 — verify (expect one row: description / text / YES)
-- SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--  WHERE table_name = 'recurring_tasks' AND column_name = 'description';

-- ------------------------------------------------------------
-- Revert (only if you ever need to remove it):
-- ALTER TABLE recurring_tasks DROP CONSTRAINT IF EXISTS recurring_tasks_description_len;
-- ALTER TABLE recurring_tasks DROP COLUMN IF EXISTS description;
-- ------------------------------------------------------------
