-- ============================================================
-- Instrument value consistency check
--
-- The website enquiry form and the portal use different labels
-- for the same instrument ("Piano / Keyboard" vs "Piano"). These
-- are compared as exact strings by skill grading, lesson
-- instrument filtering and teacher-instrument validation, so a
-- mismatch fails silently rather than erroring.
--
-- The Zoho import brought in form-style values, so both
-- spellings may already exist.
-- ============================================================

-- 1. Every instrument value currently on a student, with counts
SELECT instrument, COUNT(*) AS students
  FROM student_instruments
 GROUP BY instrument
 ORDER BY instrument;

-- 2. Every instrument value currently on a teacher
SELECT DISTINCT unnest(instruments) AS instrument
  FROM teachers
 ORDER BY 1;

-- 3. Every instrument value currently on a lesson
SELECT instrument, COUNT(*) AS lessons
  FROM lessons
 GROUP BY instrument
 ORDER BY instrument;

-- 4. Students holding a value no teacher teaches — these can
--    never be matched to a lesson or graded consistently
SELECT p.first_name, p.last_name, si.instrument
  FROM student_instruments si
  JOIN students s ON s.id = si.student_id
  JOIN profiles p ON p.id = s.user_id
 WHERE si.instrument NOT IN (
   SELECT DISTINCT unnest(instruments) FROM teachers
 )
 ORDER BY si.instrument, p.last_name;

-- 5. Students with BOTH spellings — a duplicate skill record
SELECT p.first_name, p.last_name,
       string_agg(si.instrument, ' + ' ORDER BY si.instrument) AS both
  FROM student_instruments si
  JOIN students s ON s.id = si.student_id
  JOIN profiles p ON p.id = s.user_id
 WHERE si.instrument IN ('Piano', 'Piano / Keyboard')
 GROUP BY p.first_name, p.last_name
HAVING COUNT(DISTINCT si.instrument) > 1;


-- ============================================================
-- NORMALISATION — review the output above before running.
-- Adjust the mapping to whichever label you settle on.
-- ============================================================

-- BEGIN;
--
-- -- Merge "Piano / Keyboard" into "Piano", keeping the higher
-- -- skill level where a student somehow holds both.
-- UPDATE student_instruments a
--    SET skill_level = GREATEST(a.skill_level, b.skill_level)
--   FROM student_instruments b
--  WHERE a.student_id = b.student_id
--    AND a.instrument = 'Piano'
--    AND b.instrument = 'Piano / Keyboard';
--
-- DELETE FROM student_instruments
--  WHERE instrument = 'Piano / Keyboard'
--    AND student_id IN (
--      SELECT student_id FROM student_instruments WHERE instrument = 'Piano'
--    );
--
-- UPDATE student_instruments
--    SET instrument = 'Piano'
--  WHERE instrument = 'Piano / Keyboard';
--
-- UPDATE lessons SET instrument = 'Piano' WHERE instrument = 'Piano / Keyboard';
--
-- UPDATE teachers
--    SET instruments = array_replace(instruments, 'Piano / Keyboard', 'Piano')
--  WHERE 'Piano / Keyboard' = ANY(instruments);
--
-- COMMIT;
