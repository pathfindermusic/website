-- Find every student record (any status) using Ario's email/parent email,
-- and whether each one already has a real portal login.

SELECT
  s.id            AS student_id,
  p.first_name,
  p.last_name,
  s.status,
  s.email,
  s.parent_email,
  s.user_id,
  (au.id IS NOT NULL) AS has_login
FROM students s
LEFT JOIN profiles  p  ON p.id  = s.user_id
LEFT JOIN auth.users au ON au.id = s.user_id
WHERE LOWER(s.email)        = LOWER('rajabian.tabesh@gmail.com')
   OR LOWER(s.parent_email) = LOWER('rajabian.tabesh@gmail.com')
ORDER BY s.status, p.first_name;
