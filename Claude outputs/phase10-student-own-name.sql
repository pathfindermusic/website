-- Phase 10 — give each student their own display name, independent of
-- the login (profiles) they happen to share with siblings.
--
-- Root cause: `students` has never had its own name field — every page
-- reads first_name/last_name from `profiles` via students.user_id. That's
-- harmless while every student has their own login, but breaks the moment
-- two or three students share one login (the sibling-consolidation work
-- done 1 Oct 2026): they all show the same name, and editing one changes
-- all of them, because there's only one shared profiles row.
--
-- This migration adds students.first_name / students.last_name, backfills
-- every student from their current (correct, for a solo login) profile
-- name, then corrects the 22 students whose individual name was lost when
-- their placeholder profile got deleted during today's sibling relinking —
-- recovered from the relink script's own record of who was who.
--
-- Run ONE STATEMENT AT A TIME and check each result, per usual practice.

-- ============================================================
-- STEP 1 — add the columns.
-- ============================================================
ALTER TABLE students
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name  text;

-- ============================================================
-- STEP 2 — backfill everyone from their current login's profile. This is
-- correct for every student with their own login, and for the 17 "holder"
-- siblings whose own name is still the one on the shared profile. It's
-- WRONG for the other 22 (see Step 3), who get corrected immediately after.
-- ============================================================
UPDATE students s
   SET first_name = p.first_name,
       last_name  = p.last_name
  FROM profiles p
 WHERE p.id = s.user_id
   AND s.first_name IS NULL;

-- CHECK: row count should equal your total student count.


-- ============================================================
-- STEP 3 — correct the 22 students whose individual name is no longer
-- stored anywhere live (their placeholder profile was deleted when they
-- were relinked to a sibling's login). Recovered from the relink script's
-- own inline comments.
-- ============================================================
UPDATE students s
   SET first_name = v.first_name,
       last_name  = v.last_name
  FROM (VALUES
    ('14497ef1-477e-4304-947e-7295274ef2c1'::uuid, 'Ravi',     'Vanselow'),
    ('d1555e62-1121-4f3a-9dff-eccd94ab3691'::uuid, 'Nainika',  'Anoop'),
    ('f844f72b-5924-4140-9914-a0ea1c5026cc'::uuid, 'Nakul',    'Anoop'),
    ('ec2916f9-4c6f-40e2-aac1-e283f26766de'::uuid, 'Amrita',   'Chahal'),
    ('6606dc46-78b1-4e2b-8696-05e109f789f9'::uuid, 'Adrian',   'Pook'),
    ('95195b1a-1867-40be-9d26-21f7d330bdb9'::uuid, 'Kyle',     'De Jesus'),
    ('27c5876c-7c4a-4044-9b98-8a2ad1f8162c'::uuid, 'Justine',  'Pearson'),
    ('3f473834-f233-475b-8d40-830fc010e0fa'::uuid, 'Sonny',    'Pearson'),
    ('3bf58e22-a49a-4151-8a9c-02d4613f294a'::uuid, 'Quentin',  'Assimo'),
    ('02857832-ca51-4580-b0d0-b4daad125066'::uuid, 'Sangpi',   'Tawng'),
    ('7c4512e0-1b83-4ea7-a551-7d569ebd3a98'::uuid, 'Sianhoi',  'Tawng'),
    ('8b982e15-a2f9-404d-9f79-ca2967acafc4'::uuid, 'Logan',    'Thomas'),
    ('e2cb78c2-bc6c-4c78-8871-56757c3270d4'::uuid, 'Hugo',     'Smith'),
    ('f2d861f6-a570-406b-b15b-853437d30e61'::uuid, 'Mona',     'Fan'),
    ('b524491a-ab1d-4549-9afd-446c4ea64565'::uuid, 'Alby',     'Walters'),
    ('20228c3e-ec76-4b20-9c35-55ebe28fcebd'::uuid, 'Sepanta',  'Samvi'),
    ('b41c1dba-487f-414d-9988-f5defcaf3111'::uuid, 'Teddy',    'McGregor'),
    ('5e736844-99a4-47ca-a2b0-d5dd39dee8db'::uuid, 'Ellemiek', 'Missen'),
    ('9600de69-1804-45a6-a3e1-06f9d029d54c'::uuid, 'Liam',     'Missen'),
    ('6384c806-b705-4b3b-8255-c3a8efbb715a'::uuid, 'Scarlett', 'Hammel'),
    ('ee851ff5-8ab8-4f94-92e9-997d4af2b7d7'::uuid, 'Bennett',  'Taylor'),
    ('7ccf6504-3ad3-4573-83d8-065432ef365b'::uuid, 'Luellla',  'Taylor')
  ) AS v(student_id, first_name, last_name)
 WHERE s.id = v.student_id
RETURNING s.id, s.first_name, s.last_name;

-- CHECK: should return exactly 22 rows, each with the recovered name.


-- ============================================================
-- STEP 4 — verify no active student was left without a name.
-- ============================================================
SELECT s.id, s.user_id
FROM students s
WHERE s.status = 'active'
  AND (s.first_name IS NULL OR s.last_name IS NULL);

-- CHECK: should return 0 rows.
