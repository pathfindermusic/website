-- ============================================================
-- PATHFINDER PORTAL — lesson reminders
--
-- A courtesy email on the morning of a lesson.
--
-- OFF by default. The admins' experience is that more families
-- decline these than want them, so it is opt-in: nobody receives
-- one until someone asks.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The flag, and a token for the unsubscribe link
--
-- The token is what makes the opt-out link work without a login:
-- an email client follows a plain URL with no session. It is
-- random per student and reveals nothing about them.
-- ------------------------------------------------------------
ALTER TABLE students
  ADD COLUMN IF NOT EXISTS lesson_reminders boolean NOT NULL DEFAULT false;

ALTER TABLE students
  ADD COLUMN IF NOT EXISTS reminder_token uuid NOT NULL DEFAULT gen_random_uuid();

CREATE UNIQUE INDEX IF NOT EXISTS students_reminder_token_idx
  ON students (reminder_token);

-- Only worth indexing the ones that are on, since that is all the
-- scheduled job ever looks for.
CREATE INDEX IF NOT EXISTS students_reminders_on_idx
  ON students (lesson_reminders) WHERE lesson_reminders;


-- ------------------------------------------------------------
-- 2. A record of what was sent
--
-- Guards against a double send if the schedule fires twice, and
-- answers "did they get told?" when a family says they weren't.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reminder_log (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid references students(id) on delete cascade,
  occurrence_id uuid references lesson_occurrences(id) on delete cascade,
  sent_to       text,
  sent_at       timestamptz not null default now(),
  status        text not null default 'sent',
  unique (student_id, occurrence_id)
);

ALTER TABLE reminder_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins read reminder log" ON reminder_log;
CREATE POLICY "admins read reminder log"
  ON reminder_log FOR SELECT
  USING (get_my_role() IN ('superuser','admin'));

-- Writes come from the scheduled job, which uses the service role
-- and bypasses RLS entirely.


-- ------------------------------------------------------------
-- 3. PostgREST caches the schema
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY
-- ============================================================
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'students'
   AND column_name IN ('lesson_reminders','reminder_token')
 ORDER BY column_name;

SELECT COUNT(*) FILTER (WHERE lesson_reminders)     AS opted_in,
       COUNT(*) FILTER (WHERE NOT lesson_reminders) AS opted_out
  FROM students;
