-- Run ONE STATEMENT AT A TIME and check each result.

-- ============================================================
-- STEP 1 — link Bennett and Luellla to Thatcher's new real login.
-- Guarded on their current user_id so this only fires if nothing's
-- changed underneath since the check query ran.
-- ============================================================
WITH relink (student_id, expected_user_id, new_user_id) AS (
  VALUES
    ('ee851ff5-8ab8-4f94-92e9-997d4af2b7d7'::uuid, '4f535857-e747-4239-a042-9532e6af54e4'::uuid, 'c195f7ca-d1c8-4a8e-b33f-2ec1017475cb'::uuid), -- Bennett Taylor -> Thatcher Taylor
    ('7ccf6504-3ad3-4573-83d8-065432ef365b'::uuid, '587f9042-d6bd-4671-87f7-04066464f33b'::uuid, 'c195f7ca-d1c8-4a8e-b33f-2ec1017475cb'::uuid)  -- Luellla Taylor -> Thatcher Taylor
)
UPDATE students s
   SET user_id = r.new_user_id
  FROM relink r
 WHERE s.id = r.student_id
   AND s.user_id = r.expected_user_id
RETURNING s.id, r.expected_user_id AS old_user_id, s.user_id AS new_user_id;

-- CHECK: should return exactly 2 rows.


-- ============================================================
-- STEP 2 — clean up Bennett's and Luellla's now-orphaned placeholder
-- profiles, each reconfirmed unreferenced first.
-- ============================================================
DELETE FROM profiles pr
 WHERE pr.id IN (
   '4f535857-e747-4239-a042-9532e6af54e4',
   '587f9042-d6bd-4671-87f7-04066464f33b'
 )
 AND NOT EXISTS (SELECT 1 FROM students s  WHERE s.user_id  = pr.id)
 AND NOT EXISTS (SELECT 1 FROM teachers t  WHERE t.user_id  = pr.id)
 AND NOT EXISTS (SELECT 1 FROM admins   ad WHERE ad.user_id = pr.id)
RETURNING id, first_name, last_name;

-- CHECK: should return exactly 2 rows.
