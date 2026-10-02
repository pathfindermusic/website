-- ============================================================
-- PATHFINDER PORTAL — Phase 12: Waiting list
--
-- Closing an enquiry's follow-up task already had three outcomes
-- (trial / enrolling / not proceeding). This adds a fourth: the
-- student is ready to enrol, but there's no suitable lesson slot
-- yet. Rather than inventing a new concept, this reuses the
-- 'waitlist' task kind that phase4a-waitlist-and-transfer.sql
-- already built (an open-ended task with no due date) — it was
-- only ever wired up for an admin to create one by hand; nothing
-- in the app has driven it from the enquiry-closing flow until now.
--
-- The enquiry's student record stays status='prospective' — it is
-- still, fundamentally, an undecided enquiry; what changed is only
-- what's gating it. This keeps every existing 'prospective' rule
-- (excluded from Students, from notification recipients, from the
-- task subject picker, from bulk sends) correctly applying with no
-- further changes anywhere else in the app.
--
-- Five new columns on tasks, used only when kind='waitlist':
--   waitlist_teacher_id   — preferred teacher, NULL = any
--   waitlist_day_of_week  — preferred day, NULL = any (0=Sun..6=Sat,
--                           same convention as teacher_availability
--                           and recurring_tasks.weekday)
--   waitlist_time_from/to — preferred time window, either or both
--                           may be NULL
--   waitlisted_at         — when the entry was added to the waiting
--                           list; drives the 3-month auto-lapse in
--                           lapse-waiting-list.js. Deliberately NOT
--                           tasks.created_at — the follow-up task may
--                           have existed for weeks before the family
--                           decided to wait, and the 3-month clock
--                           should start from that decision.
--
-- "Preferred studio" is deliberately NOT a new column — it's just
-- the task's existing studio_id, which the admin already sets.
--
-- ⚠ Run one statement at a time and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The columns
-- ------------------------------------------------------------
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS waitlist_teacher_id uuid
  REFERENCES teachers(id) ON DELETE SET NULL;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS waitlist_day_of_week int;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS waitlist_time_from  time;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS waitlist_time_to    time;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS waitlisted_at       timestamptz;

ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_waitlist_day_range;
ALTER TABLE tasks ADD CONSTRAINT tasks_waitlist_day_range
  CHECK (waitlist_day_of_week IS NULL OR waitlist_day_of_week BETWEEN 0 AND 6);

ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_waitlist_time_range;
ALTER TABLE tasks ADD CONSTRAINT tasks_waitlist_time_range
  CHECK (waitlist_time_from IS NULL OR waitlist_time_to IS NULL
         OR waitlist_time_to > waitlist_time_from);


-- ------------------------------------------------------------
-- 2. Partial index for the nightly 3-month lapse sweep — only
--    open waitlist entries are ever scanned for it, so the index
--    only needs to cover that slice.
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS tasks_waitlist_lapse_idx
  ON tasks (waitlisted_at)
  WHERE kind = 'waitlist' AND status = 'open';


-- ------------------------------------------------------------
-- 3. No RLS changes — these are plain columns on the existing
--    tasks table, already covered by its table-level policies
--    (phase4a-tasks.sql: admins/superuser FOR ALL within their
--    studios, teachers SELECT their own). Nothing here needs a
--    narrower rule than the task itself already has.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 4. Tell PostgREST about the new columns.
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'tasks'
   AND column_name IN ('waitlist_teacher_id','waitlist_day_of_week',
                        'waitlist_time_from','waitlist_time_to','waitlisted_at')
 ORDER BY column_name;

SELECT conname, pg_get_constraintdef(oid)
  FROM pg_constraint
 WHERE conrelid = 'tasks'::regclass
   AND conname IN ('tasks_waitlist_day_range','tasks_waitlist_time_range');

SELECT indexname FROM pg_indexes
 WHERE tablename = 'tasks' AND indexname = 'tasks_waitlist_lapse_idx';

-- Nothing should already be on the waiting list under this scheme
SELECT count(*) FROM tasks WHERE kind = 'waitlist' AND waitlisted_at IS NOT NULL;
