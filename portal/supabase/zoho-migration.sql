-- ============================================================
-- PATHFINDER PORTAL — Zoho CRM Leads Migration Script
-- Version: Final
-- 
-- INSTRUCTIONS:
-- 1. Run Step 0 to drop the foreign key constraint temporarily
-- 2. Run Step 1 to create the staging table
-- 3. Go to Supabase Table Editor → zoho_leads_import → 
--    Insert → Import data from CSV to import your Zoho export
-- 4. Run Steps 2–6 in order
-- 5. Run Step 7 to clean up
-- ============================================================

-- Step 0: Drop foreign key constraint temporarily
-- (allows profiles to be created without auth.users accounts)
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;

-- ============================================================
-- Step 1: Create staging table matching Zoho CSV headers exactly
-- ============================================================
DROP TABLE IF EXISTS zoho_leads_import;

CREATE TABLE zoho_leads_import (
  "First Name"      text,
  "Last Name"       text,
  "Email"           text,
  "Phone"           text,
  "Enrolled Studio" text,
  "Instruments"     text,
  "Parent Name"     text,
  "Secondary Email" text,
  "Status"          text   -- optional: active / trial / inactive. Defaults to active.
);

-- ============================================================
-- Step 2: Clean up phone numbers (remove labels like "(Mobile)")
-- ============================================================
UPDATE zoho_leads_import
SET "Phone" = trim(regexp_replace("Phone", '\s*\([^)]*\)', '', 'g'));

-- ============================================================
-- Step 2b: PRE-FLIGHT CHECK — run this and read the output BEFORE
-- going any further. Every row listed here would import badly.
-- Fix them in the source CSV, re-import the staging table, and
-- re-run this until it returns nothing.
-- ============================================================
SELECT 'missing first name' AS problem, COUNT(*) AS rows
  FROM zoho_leads_import WHERE COALESCE(trim("First Name"), '') = ''
UNION ALL
SELECT 'missing last name', COUNT(*)
  FROM zoho_leads_import WHERE COALESCE(trim("Last Name"), '') = ''
UNION ALL
SELECT 'missing email', COUNT(*)
  FROM zoho_leads_import WHERE COALESCE(trim("Email"), '') = ''
UNION ALL
SELECT 'email looks malformed', COUNT(*)
  FROM zoho_leads_import
 WHERE COALESCE(trim("Email"), '') <> '' AND trim("Email") NOT LIKE '%_@_%._%'
UNION ALL
SELECT 'duplicate email in file', COUNT(*) FROM (
  SELECT lower(trim("Email")) e FROM zoho_leads_import
   WHERE COALESCE(trim("Email"), '') <> ''
   GROUP BY 1 HAVING COUNT(*) > 1
) d
UNION ALL
SELECT 'studio not recognised', COUNT(*)
  FROM zoho_leads_import z
  LEFT JOIN studios s ON lower(trim(s.name)) = lower(trim(z."Enrolled Studio"))
 WHERE s.id IS NULL
UNION ALL
SELECT 'status not recognised', COUNT(*)
  FROM zoho_leads_import
 WHERE COALESCE(trim("Status"), '') <> ''
   AND lower(trim("Status")) NOT IN ('active','trial','inactive')
UNION ALL
SELECT 'instrument not in canonical list', COUNT(*) FROM (
  SELECT trim(unnest(string_to_array("Instruments", ','))) i
    FROM zoho_leads_import WHERE COALESCE(trim("Instruments"), '') <> ''
) x WHERE i <> '' AND i NOT IN (
  'Guitar','Bass','Drums','Piano / Keyboard','Piano','Keyboard',
  'Voice / Singing','Voice','Singing','Violin','Ukulele',
  'Music Theory','Saxophone','Band','Other'
)
UNION ALL
SELECT 'duplicate name (import matches on name)', COUNT(*) FROM (
  SELECT lower(trim("First Name")) f, lower(trim("Last Name")) l
    FROM zoho_leads_import GROUP BY 1,2 HAVING COUNT(*) > 1
) n;


-- ============================================================
-- Step 3: Insert profiles for students
-- Duplicate check by first_name + last_name
-- (email lives in auth.users, not profiles)
-- ============================================================
INSERT INTO profiles (id, first_name, last_name, phone, role, status, must_change_password)
SELECT 
  gen_random_uuid(),
  trim(z."First Name"),
  trim(z."Last Name"),
  trim(z."Phone"),
  'student',
  'active',
  true
FROM zoho_leads_import z
WHERE trim(z."First Name") != ''
  AND trim(z."Last Name")  != ''
  AND NOT EXISTS (
    SELECT 1 FROM profiles p 
    WHERE lower(trim(p.first_name)) = lower(trim(z."First Name"))
      AND lower(trim(p.last_name))  = lower(trim(z."Last Name"))
      AND p.role = 'student'
  );

-- ============================================================
-- Step 4: Insert students linked to profiles
-- ============================================================
INSERT INTO students (id, user_id, status, studio_id, email, parent_name, parent_email)
SELECT
  gen_random_uuid(),
  p.id,
  CASE WHEN lower(trim(COALESCE(z."Status", ''))) IN ('active','trial','inactive')
       THEN lower(trim(z."Status"))
       ELSE 'active'
  END,
  s.id,
  NULLIF(trim(z."Email"), ''),
  NULLIF(trim(z."Parent Name"), ''),
  NULLIF(trim(z."Secondary Email"), '')
FROM zoho_leads_import z
JOIN profiles p 
  ON lower(trim(p.first_name)) = lower(trim(z."First Name"))
  AND lower(trim(p.last_name))  = lower(trim(z."Last Name"))
  AND p.role = 'student'
LEFT JOIN studios s 
  ON lower(trim(s.name)) = lower(trim(z."Enrolled Studio"))
WHERE NOT EXISTS (
  SELECT 1 FROM students st WHERE st.user_id = p.id
);

-- ============================================================
-- Step 5: Insert student instruments (skill level defaults to 0)
-- Handles comma-separated instruments e.g. "Guitar, Piano"
-- ============================================================
INSERT INTO student_instruments (student_id, instrument, skill_level)
SELECT DISTINCT
  st.id,
  trim(inst.instrument),
  0
FROM zoho_leads_import z
JOIN profiles p 
  ON lower(trim(p.first_name)) = lower(trim(z."First Name"))
  AND lower(trim(p.last_name))  = lower(trim(z."Last Name"))
  AND p.role = 'student'
JOIN students st ON st.user_id = p.id
CROSS JOIN LATERAL (
  SELECT unnest(string_to_array(z."Instruments", ',')) AS instrument
) inst
WHERE trim(inst.instrument) != ''
ON CONFLICT (student_id, instrument) DO NOTHING;

-- Normalise to the canonical labels. Zoho and the website form use
-- slightly different wording from the portal for two instruments, and
-- these values are compared as exact strings elsewhere.
UPDATE student_instruments
   SET instrument = 'Piano / Keyboard'
 WHERE instrument IN ('Piano', 'Keyboard');

UPDATE student_instruments
   SET instrument = 'Voice / Singing'
 WHERE instrument IN ('Voice', 'Singing');

-- ============================================================
-- Step 6: Verify the import
-- ============================================================
SELECT 
  p.first_name,
  p.last_name,
  s.email,
  p.phone,
  s.status,
  st.name AS studio,
  string_agg(si.instrument, ', ') AS instruments,
  s.parent_name,
  s.parent_email
FROM students s
JOIN profiles p ON p.id = s.user_id
LEFT JOIN studios st ON st.id = s.studio_id
LEFT JOIN student_instruments si ON si.student_id = s.id
WHERE p.role = 'student'
GROUP BY p.first_name, p.last_name, s.email, p.phone, s.status, st.name, s.parent_name, s.parent_email
ORDER BY p.last_name, p.first_name;

-- ============================================================
-- Step 7: Clean up staging table
-- ============================================================
DROP TABLE IF EXISTS zoho_leads_import;

-- ============================================================
-- NOTES:
-- 1. Imported students have no Supabase auth account by default.
--    Create auth accounts on demand when a student needs portal
--    access, via the Add Student form.
--    They ARE still contactable: notifications fall back to
--    students.email, which this import populates. Without that
--    email they would be silently skipped by every notification.
-- 2. Skill levels default to 0 (Beginner) — teachers can update
--    per instrument from the My Students page
-- 3. Students with duplicate first+last names may not import
--    correctly — check the verification query output carefully
-- 4. The foreign key constraint was dropped in Step 0 to allow
--    profiles without auth accounts — this is intentional for
--    bulk migration. The portal still works correctly.
-- ============================================================
