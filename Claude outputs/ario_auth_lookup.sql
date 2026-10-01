-- Find the real auth account(s) using Ario's email, and whether they're
-- currently linked to any student/teacher/admin record.

SELECT
  au.id                AS auth_user_id,
  au.email              AS auth_email,
  au.created_at         AS auth_created_at,
  p.first_name,
  p.last_name,
  p.role,
  p.status,
  EXISTS (SELECT 1 FROM students s  WHERE s.user_id  = au.id) AS linked_to_student,
  EXISTS (SELECT 1 FROM teachers t  WHERE t.user_id  = au.id) AS linked_to_teacher,
  EXISTS (SELECT 1 FROM admins   ad WHERE ad.user_id = au.id) AS linked_to_admin
FROM auth.users au
LEFT JOIN profiles p ON p.id = au.id
WHERE LOWER(au.email) = LOWER('rajabian.tabesh@gmail.com');
