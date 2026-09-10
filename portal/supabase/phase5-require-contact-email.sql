-- ============================================================
-- PATHFINDER PORTAL — require a contact email per student
--
-- Why: students.email is often left blank for a sibling who shares
-- a parent's login/email. That's fine — but every student record
-- still needs SOME way to reach the family, so we now require
-- students.email OR students.parent_email (or both) to be set.
--
-- This is enforced client-side in students.html (saveStudent()) on
-- both create and edit. This migration backs that up at the
-- database level.
--
-- Uses NOT VALID so it does NOT retroactively check/break any
-- existing rows that may currently have neither field set — it only
-- applies to new inserts and updates going forward. Run the VERIFY
-- query below first to see if any existing students need cleanup.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================

ALTER TABLE students
  ADD CONSTRAINT students_contact_email_required
  CHECK (email IS NOT NULL OR parent_email IS NOT NULL)
  NOT VALID;

-- ============================================================
-- VERIFY — run each separately
-- ============================================================

-- Confirm the constraint now exists
SELECT conname, convalidated
  FROM pg_constraint
 WHERE conrelid = 'students'::regclass
   AND conname = 'students_contact_email_required';

-- Find existing students that currently violate the rule (neither
-- email nor parent_email set) so admins can follow up with them.
-- These rows are NOT blocked by the constraint (it's NOT VALID),
-- but they're worth cleaning up.
-- (names/studio live on profiles/studios, joined in — LEFT JOIN
-- because a student with no login of their own has no profiles row)
SELECT s.id, p.first_name, p.last_name, st.name AS studio_name, s.status
  FROM students s
  LEFT JOIN profiles p ON p.id = s.user_id
  LEFT JOIN studios  st ON st.id = s.studio_id
 WHERE s.email IS NULL AND s.parent_email IS NULL
 ORDER BY p.last_name, p.first_name;

-- Optional, once the list above is empty/cleaned up: validate the
-- constraint so Postgres confirms every row complies. This scans
-- the whole table but still doesn't block existing rows if any
-- remain non-compliant — it will simply fail with an error naming
-- the violating row, in which case just leave the constraint as
-- NOT VALID for now.
-- ALTER TABLE students VALIDATE CONSTRAINT students_contact_email_required;
