-- ============================================================
-- PATHFINDER PORTAL — contact email on the student record
--
-- Why: login emails live in auth.users, but students imported in
-- bulk deliberately have no auth account until they need portal
-- access. Those students were therefore unreachable by any
-- notification — the recipient count silently under-counted.
--
-- This adds a contact email to the student record itself, used as
-- a fallback when there is no auth account.
-- ============================================================

ALTER TABLE students ADD COLUMN IF NOT EXISTS email text;

-- Helpful for lookups and for spotting duplicates
CREATE INDEX IF NOT EXISTS students_email_idx ON students (lower(email));


-- ------------------------------------------------------------
-- Which students are currently unreachable?
-- Any row here would be silently skipped by notifications.
-- ------------------------------------------------------------
SELECT p.first_name,
       p.last_name,
       s.email        AS contact_email,
       s.parent_email,
       CASE WHEN au.id IS NULL THEN 'no login account' ELSE 'has login' END AS auth
  FROM students s
  JOIN profiles p    ON p.id  = s.user_id
  LEFT JOIN auth.users au ON au.id = s.user_id
 WHERE s.status IN ('active','trial')
   AND s.email        IS NULL
   AND s.parent_email IS NULL
   AND au.id          IS NULL
 ORDER BY p.last_name, p.first_name;


-- ------------------------------------------------------------
-- Backfill for students who DO have a login: copy the auth email
-- onto the student record so both stay in step.
-- ------------------------------------------------------------
UPDATE students s
   SET email = au.email
  FROM auth.users au
 WHERE au.id = s.user_id
   AND s.email IS DISTINCT FROM au.email;


-- ------------------------------------------------------------
-- Students imported from Zoho have no auth account and no email,
-- because the original import had nowhere to put it. Options:
--
--   1. Re-run zoho-migration.sql — it now populates students.email
--   2. Set them individually via the portal's Edit Student form
--   3. Bulk update from a staging table, e.g.
--
--      UPDATE students s
--         SET email = z."Email"
--        FROM zoho_leads_import z
--        JOIN profiles p ON p.id = s.user_id
--       WHERE lower(trim(p.first_name)) = lower(trim(z."First Name"))
--         AND lower(trim(p.last_name))  = lower(trim(z."Last Name"))
--         AND s.email IS NULL;
-- ------------------------------------------------------------

-- Final check — how many are reachable?
SELECT
  COUNT(*) FILTER (WHERE s.status IN ('active','trial'))                       AS active_or_trial,
  COUNT(*) FILTER (WHERE s.status IN ('active','trial')
                     AND (s.email IS NOT NULL
                       OR s.parent_email IS NOT NULL
                       OR au.id IS NOT NULL))                                  AS contactable
  FROM students s
  LEFT JOIN auth.users au ON au.id = s.user_id;
