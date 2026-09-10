-- ============================================================
-- PATHFINDER PORTAL — fortnightly lessons
--
-- Recurring series were always weekly — plannedDates() in lessons.html
-- stepped by 7 days with nothing to say otherwise. This adds a second
-- frequency so a series can be generated every 14 days instead, for
-- studios now offering fortnightly lessons alongside weekly.
--
-- Per LESSON (the series), not per occurrence — a fortnightly lesson
-- is one series with a wider gap between occurrences, not a different
-- kind of occurrence. Existing lessons default to 'weekly', which is
-- what they already are.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The column
-- ------------------------------------------------------------
ALTER TABLE lessons
  ADD COLUMN IF NOT EXISTS frequency text NOT NULL DEFAULT 'weekly';

ALTER TABLE lessons
  ADD CONSTRAINT lessons_frequency_check
  CHECK (frequency IN ('weekly', 'fortnightly'));

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT column_name, column_default, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'lessons' AND column_name = 'frequency';

SELECT conname FROM pg_constraint
 WHERE conrelid = 'lessons'::regclass AND conname = 'lessons_frequency_check';

-- Every existing lesson should have come through as 'weekly' — nothing
-- should already say 'fortnightly' before the app ever wrote one.
SELECT frequency, COUNT(*) FROM lessons GROUP BY frequency;
