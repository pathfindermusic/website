-- Run ONE STATEMENT AT A TIME and check each result, per usual practice.

-- ============================================================
-- STEP 1 — the actual relink, built from exactly the 20 pairs you
-- confirmed in the preview. The `s.user_id = r.expected_user_id` guard
-- means a row is only touched if nothing has changed underneath since
-- that preview ran; otherwise it's silently skipped (check the
-- RETURNING count below equals 20).
-- ============================================================
WITH relink (student_id, expected_user_id, new_user_id) AS (
  VALUES
    ('14497ef1-477e-4304-947e-7295274ef2c1'::uuid, '42222cad-926c-40cb-ab58-721659db1cb4'::uuid, '07c5be6d-48ec-40f7-829c-e44b3abe8dfa'::uuid), -- Ravi Vanselow -> Al Vanselow
    ('d1555e62-1121-4f3a-9dff-eccd94ab3691'::uuid, '6ca31519-4f59-477f-877f-4c6a0bda4903'::uuid, '41169b0f-29db-4e39-8259-38427e9b25ec'::uuid), -- Nainika Anoop -> Anoop Sinha
    ('f844f72b-5924-4140-9914-a0ea1c5026cc'::uuid, 'f466dbae-a496-45b4-8ff3-7ba14068fed9'::uuid, '41169b0f-29db-4e39-8259-38427e9b25ec'::uuid), -- Nakul Anoop -> Anoop Sinha
    ('ec2916f9-4c6f-40e2-aac1-e283f26766de'::uuid, 'f850d1ff-fa06-4e71-8540-81a698e8e224'::uuid, '1ae45221-48c3-457e-b7c9-480f184e9f90'::uuid), -- Amrita Chahal -> Arjun Chahal
    ('6606dc46-78b1-4e2b-8696-05e109f789f9'::uuid, '6cd041d6-f3cc-4010-9070-359350e18b09'::uuid, '0d167ea7-bca2-40b2-8849-34ac9a9e7234'::uuid), -- Adrian Pook -> Armaan Pook
    ('95195b1a-1867-40be-9d26-21f7d330bdb9'::uuid, '1bf3ef37-e780-4760-9a56-94bbc39f7c31'::uuid, '9f6b71ed-ecc7-43ba-a49f-8471e1413b7e'::uuid), -- Kyle De Jesus -> Ashleigh De Jesus
    ('27c5876c-7c4a-4044-9b98-8a2ad1f8162c'::uuid, '7a1fc668-ec68-436e-9e82-bfad2c9fe3b5'::uuid, '3f8b8d41-7c9f-43a8-9af4-21671aee96fc'::uuid), -- Justine Pearson -> Finley Pearson
    ('3f473834-f233-475b-8d40-830fc010e0fa'::uuid, '0aa3e922-9fb6-44f7-9d81-49c95d334c37'::uuid, '3f8b8d41-7c9f-43a8-9af4-21671aee96fc'::uuid), -- Sonny Pearson -> Finley Pearson
    ('3bf58e22-a49a-4151-8a9c-02d4613f294a'::uuid, 'f0845b9f-71e8-4a76-b81e-8b4a1ec7aea8'::uuid, 'b44f967a-e46e-409c-b096-e61fac9f20a9'::uuid), -- Quentin Assimo -> Julian Assimo
    ('02857832-ca51-4580-b0d0-b4daad125066'::uuid, 'e963d8dd-75c4-4283-aa22-58130f98534e'::uuid, '8940b626-e44e-4070-9c22-7e389c833db0'::uuid), -- Sangpi Tawng -> Lianpi Tawng
    ('7c4512e0-1b83-4ea7-a551-7d569ebd3a98'::uuid, '31cc7c3f-41b1-4f0e-adf2-53ee63025492'::uuid, '8940b626-e44e-4070-9c22-7e389c833db0'::uuid), -- Sianhoi Tawng -> Lianpi Tawng
    ('8b982e15-a2f9-404d-9f79-ca2967acafc4'::uuid, '97ac5df6-f19b-4304-b0f5-38ee5ec3d23e'::uuid, '2a3a8079-4409-4af9-8ac2-210fa8ac90ac'::uuid), -- Logan Thomas -> Mason Thomas
    ('e2cb78c2-bc6c-4c78-8871-56757c3270d4'::uuid, '71df189d-b45d-45da-b295-ea449a5c6982'::uuid, 'de4b8d34-75d7-47b4-8b59-f81a158736f6'::uuid), -- Hugo Smith -> Max Smith
    ('f2d861f6-a570-406b-b15b-853437d30e61'::uuid, '350ae6f9-19fd-4bb7-859b-4cf889716981'::uuid, '261e93c1-699d-417e-a98d-e64af6bff1c0'::uuid), -- Mona Fan -> Ming Fan
    ('b524491a-ab1d-4549-9afd-446c4ea64565'::uuid, '7cccebf1-b7f3-44f9-a75f-58d5f49d0699'::uuid, '80cb1711-6b5e-4835-9006-1cc6835a30e9'::uuid), -- Alby Walters -> Morgan Walters
    ('20228c3e-ec76-4b20-9c35-55ebe28fcebd'::uuid, '99e6a407-0359-490f-aa1e-4ad7921fcacf'::uuid, '149ad663-eb15-48ea-b2d6-c6b16ed22cab'::uuid), -- Sepanta Samvi -> Parsa Samvi
    ('b41c1dba-487f-414d-9988-f5defcaf3111'::uuid, 'b6fc9631-9d02-4cf5-8ea0-7b3ea8f7b6eb'::uuid, '42c40dc3-1a68-4878-a86c-fb3b8b9fbef1'::uuid), -- Teddy McGregor -> Thomas McGregor
    ('5e736844-99a4-47ca-a2b0-d5dd39dee8db'::uuid, 'c3a67832-87f0-43a1-ab00-3e74cecf385a'::uuid, '9f873342-7aff-455b-b9b9-8420ede9bef0'::uuid), -- Ellemiek Missen -> Toby Missen
    ('9600de69-1804-45a6-a3e1-06f9d029d54c'::uuid, '92eeebbc-58db-4146-85fe-09371bcaafad'::uuid, '9f873342-7aff-455b-b9b9-8420ede9bef0'::uuid), -- Liam Missen -> Toby Missen
    ('6384c806-b705-4b3b-8255-c3a8efbb715a'::uuid, '82a7d696-dcb3-419b-af20-fa3db3e7cb3a'::uuid, '11d35f6c-cf4e-4010-87b2-70533573ce65'::uuid)  -- Scarlett Hammel -> Willow Hammel
)
UPDATE students s
   SET user_id = r.new_user_id
  FROM relink r
 WHERE s.id = r.student_id
   AND s.user_id = r.expected_user_id
RETURNING s.id, r.expected_user_id AS old_user_id, s.user_id AS new_user_id;

-- CHECK: the result above should be exactly 20 rows. If it's fewer,
-- stop here and tell me which student_ids are missing before running
-- Step 2 — something changed since the preview and it needs a look.


-- ============================================================
-- STEP 2 — clean up the 20 placeholder profile rows those students no
-- longer point at. Each one is reconfirmed unreferenced by students,
-- teachers or admins before being removed, so this is safe to run even
-- if Step 1 updated fewer than 20 rows (it will simply remove fewer).
-- ============================================================
DELETE FROM profiles pr
 WHERE pr.id IN (
   '42222cad-926c-40cb-ab58-721659db1cb4', '6ca31519-4f59-477f-877f-4c6a0bda4903',
   'f466dbae-a496-45b4-8ff3-7ba14068fed9', 'f850d1ff-fa06-4e71-8540-81a698e8e224',
   '6cd041d6-f3cc-4010-9070-359350e18b09', '1bf3ef37-e780-4760-9a56-94bbc39f7c31',
   '7a1fc668-ec68-436e-9e82-bfad2c9fe3b5', '0aa3e922-9fb6-44f7-9d81-49c95d334c37',
   'f0845b9f-71e8-4a76-b81e-8b4a1ec7aea8', 'e963d8dd-75c4-4283-aa22-58130f98534e',
   '31cc7c3f-41b1-4f0e-adf2-53ee63025492', '97ac5df6-f19b-4304-b0f5-38ee5ec3d23e',
   '71df189d-b45d-45da-b295-ea449a5c6982', '350ae6f9-19fd-4bb7-859b-4cf889716981',
   '7cccebf1-b7f3-44f9-a75f-58d5f49d0699', '99e6a407-0359-490f-aa1e-4ad7921fcacf',
   'b6fc9631-9d02-4cf5-8ea0-7b3ea8f7b6eb', 'c3a67832-87f0-43a1-ab00-3e74cecf385a',
   '92eeebbc-58db-4146-85fe-09371bcaafad', '82a7d696-dcb3-419b-af20-fa3db3e7cb3a'
 )
 AND NOT EXISTS (SELECT 1 FROM students s WHERE s.user_id = pr.id)
 AND NOT EXISTS (SELECT 1 FROM teachers t WHERE t.user_id = pr.id)
 AND NOT EXISTS (SELECT 1 FROM admins   ad WHERE ad.user_id = pr.id)
RETURNING id, first_name, last_name;

-- CHECK: should return up to 20 rows (fewer only if Step 1 skipped some).


-- ============================================================
-- STEP 3 — verify. Re-running the original family-check query (from
-- family_login_check.sql) should now return ONLY the 7 students who
-- genuinely need a brand-new login: Ario Ameri, Ananya Anish,
-- Jacob Baldacchino, Alecia Lei, Simon Surrao, Thatcher Taylor,
-- Vikatoa Topou. Bennett and Luellla Taylor will still show up until
-- Thatcher's new login exists, then disappear once you link them the
-- same way after his Add Login.
-- ============================================================
