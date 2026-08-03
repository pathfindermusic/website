-- ============================================================
-- PATHFINDER PORTAL — Instrument value normalisation
--
-- Instrument labels are compared as exact strings by skill
-- grading, lesson instrument filtering and teacher-instrument
-- validation. Mismatches fail silently rather than erroring.
--
-- Three sources disagreed:
--   Zoho / website form : "Piano / Keyboard", "Voice"
--   Portal code         : "Piano",            "Voice / Singing"
--
-- Canonical set adopted (matches the customer-facing form):
--   Guitar, Bass, Drums, Piano / Keyboard, Voice / Singing,
--   Violin, Ukulele, Music Theory, Saxophone, Band, Other
--
-- Run AFTER deploying the updated lessons.html, students.html
-- and teachers.html, so the code and data agree.
-- Safe to re-run.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. student_instruments
--    Unique key is (student_id, instrument), so a student
--    holding both spellings must be merged rather than renamed.
--    Keep the higher skill level.
-- ------------------------------------------------------------

-- Piano → Piano / Keyboard
UPDATE student_instruments keep
   SET skill_level = GREATEST(keep.skill_level, dup.skill_level)
  FROM student_instruments dup
 WHERE keep.student_id = dup.student_id
   AND keep.instrument = 'Piano / Keyboard'
   AND dup.instrument  = 'Piano';

DELETE FROM student_instruments
 WHERE instrument = 'Piano'
   AND student_id IN (
     SELECT student_id FROM student_instruments
      WHERE instrument = 'Piano / Keyboard'
   );

UPDATE student_instruments
   SET instrument = 'Piano / Keyboard'
 WHERE instrument = 'Piano';

-- Voice → Voice / Singing
UPDATE student_instruments keep
   SET skill_level = GREATEST(keep.skill_level, dup.skill_level)
  FROM student_instruments dup
 WHERE keep.student_id = dup.student_id
   AND keep.instrument = 'Voice / Singing'
   AND dup.instrument  = 'Voice';

DELETE FROM student_instruments
 WHERE instrument = 'Voice'
   AND student_id IN (
     SELECT student_id FROM student_instruments
      WHERE instrument = 'Voice / Singing'
   );

UPDATE student_instruments
   SET instrument = 'Voice / Singing'
 WHERE instrument = 'Voice';


-- ------------------------------------------------------------
-- 2. lessons
-- ------------------------------------------------------------
UPDATE lessons SET instrument = 'Piano / Keyboard' WHERE instrument = 'Piano';
UPDATE lessons SET instrument = 'Voice / Singing'  WHERE instrument = 'Voice';


-- ------------------------------------------------------------
-- 3. teachers.instruments (text array)
--    array_replace would create a duplicate if a teacher somehow
--    held both spellings, so de-duplicate afterwards.
-- ------------------------------------------------------------
UPDATE teachers
   SET instruments = array_replace(instruments, 'Piano', 'Piano / Keyboard')
 WHERE 'Piano' = ANY(instruments);

UPDATE teachers
   SET instruments = array_replace(instruments, 'Voice', 'Voice / Singing')
 WHERE 'Voice' = ANY(instruments);

UPDATE teachers t
   SET instruments = sub.deduped
  FROM (
    SELECT id, ARRAY(SELECT DISTINCT unnest(instruments) ORDER BY 1) AS deduped
      FROM teachers
  ) sub
 WHERE t.id = sub.id
   AND cardinality(t.instruments) <> cardinality(sub.deduped);

COMMIT;


-- ============================================================
-- Verify — every query below should return no rows
-- ============================================================

-- Old spellings anywhere
SELECT 'student_instruments' AS table, instrument, COUNT(*)
  FROM student_instruments WHERE instrument IN ('Piano','Voice') GROUP BY instrument
UNION ALL
SELECT 'lessons', instrument, COUNT(*)
  FROM lessons WHERE instrument IN ('Piano','Voice') GROUP BY instrument
UNION ALL
SELECT 'teachers', i, COUNT(*)
  FROM teachers, unnest(instruments) i WHERE i IN ('Piano','Voice') GROUP BY i;

-- Students holding an instrument no teacher teaches
SELECT p.first_name, p.last_name, si.instrument
  FROM student_instruments si
  JOIN students s ON s.id = si.student_id
  JOIN profiles p ON p.id = s.user_id
 WHERE si.instrument NOT IN (SELECT DISTINCT unnest(instruments) FROM teachers)
 ORDER BY si.instrument;

-- Anything outside the canonical set — likely a typo
SELECT DISTINCT instrument FROM student_instruments
 WHERE instrument NOT IN (
   'Guitar','Bass','Drums','Piano / Keyboard','Voice / Singing',
   'Violin','Ukulele','Music Theory','Saxophone','Band','Other'
 );
