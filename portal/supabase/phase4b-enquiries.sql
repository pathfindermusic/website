-- ============================================================
-- PATHFINDER PORTAL — Phase 4b: Enquiries
--
-- Adds two statuses either side of the existing lifecycle:
--   prospective → enquired, not yet committed
--   lapsed      → a genuine enquiry that came to nothing
--
-- Spam enquiries are DELETED rather than lapsed. Lapsed is for
-- real people who didn't enrol and are worth remembering.
--
-- ⚠ Run one statement at a time and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Widen the status constraint
-- ------------------------------------------------------------
ALTER TABLE students DROP CONSTRAINT IF EXISTS students_status_check;

ALTER TABLE students ADD CONSTRAINT students_status_check
  CHECK (status IN ('prospective','trial','active','inactive','lapsed'));


-- ------------------------------------------------------------
-- 2. Enquiry fields
--
--    enquiry_notes carries the "How can we help?" text from the
--    website form. It often holds the student's age, experience
--    and sometimes health or accessibility information. Teachers
--    can see it — comparable detail already reaches them in the
--    internal announcement, and families share it expecting that.
-- ------------------------------------------------------------
ALTER TABLE students ADD COLUMN IF NOT EXISTS enquiry_notes  text;
ALTER TABLE students ADD COLUMN IF NOT EXISTS enquiry_date   date;
ALTER TABLE students ADD COLUMN IF NOT EXISTS enquiry_source text
  CHECK (enquiry_source IS NULL OR enquiry_source IN ('website','phone','walk_in'));
ALTER TABLE students ADD COLUMN IF NOT EXISTS lapsed_reason  text;

CREATE INDEX IF NOT EXISTS students_status_idx ON students (status);


-- ------------------------------------------------------------
-- 3. PostgREST caches the schema; without this, writes including
--    the new columns fail until it refreshes on its own.
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT conname, pg_get_constraintdef(oid)
  FROM pg_constraint
 WHERE conrelid = 'students'::regclass AND conname = 'students_status_check';

SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'students'
   AND column_name IN ('enquiry_notes','enquiry_date','enquiry_source','lapsed_reason')
 ORDER BY column_name;

-- Nothing should be prospective or lapsed yet
SELECT status, COUNT(*) FROM students GROUP BY status ORDER BY status;
