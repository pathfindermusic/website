-- Run ONE STATEMENT AT A TIME and check each result.

-- ============================================================
-- STEP 1 — point Ario's student record at the existing, already-real
-- login found in auth.users, instead of creating a brand-new one.
-- Guarded so it only fires if his user_id hasn't changed since you ran
-- the lookup query.
-- ============================================================
UPDATE students
   SET user_id = '8003e169-9e68-4c6c-8a01-995608bda968'  -- existing real login for rajabian.tabesh@gmail.com
 WHERE id = '26368637-e3df-4ce0-a183-115f54122d66'        -- Ario Ameri
   AND user_id = '1db48c74-a0ff-484a-ab7d-40944ec5fd11'   -- his current placeholder user_id
RETURNING id, user_id;

-- CHECK: should return exactly 1 row. If 0, his user_id already changed —
-- stop and tell me before continuing.


-- ============================================================
-- STEP 2 — clean up the stale placeholder profile he used to point at,
-- confirmed unreferenced by any student/teacher/admin first.
-- ============================================================
DELETE FROM profiles pr
 WHERE pr.id = '1db48c74-a0ff-484a-ab7d-40944ec5fd11'
   AND NOT EXISTS (SELECT 1 FROM students s  WHERE s.user_id  = pr.id)
   AND NOT EXISTS (SELECT 1 FROM teachers t  WHERE t.user_id  = pr.id)
   AND NOT EXISTS (SELECT 1 FROM admins   ad WHERE ad.user_id = pr.id)
RETURNING id, first_name, last_name;

-- CHECK: should return exactly 1 row (Ario's old placeholder profile).
