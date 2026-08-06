-- ============================================================
-- Checklist items must reflect what THIS process produced
--
-- "Trial lesson added to the Portal" ticked itself for a student
-- who already had lessons — an active student trying a new
-- instrument, for instance. The check asked "does a lesson
-- exist", when it should ask "was one added for this process".
--
-- That needs to know when a lesson was created.
-- ============================================================

ALTER TABLE lessons ADD COLUMN IF NOT EXISTS created_at timestamptz;

-- Existing lessons predate every process. Backdating them keeps
-- them from satisfying a checklist started today.
UPDATE lessons SET created_at = '2000-01-01T00:00:00Z' WHERE created_at IS NULL;

ALTER TABLE lessons ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE lessons ALTER COLUMN created_at SET NOT NULL;

NOTIFY pgrst, 'reload schema';

-- Verify
SELECT column_name, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_name = 'lessons' AND column_name = 'created_at';

SELECT COUNT(*) AS lessons, MIN(created_at) AS oldest, MAX(created_at) AS newest
  FROM lessons;
