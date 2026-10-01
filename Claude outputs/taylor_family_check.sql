-- Shows the current state of all three Taylor siblings sharing
-- hailee.taylor@curebraincancer.org.au, so we can confirm Thatcher's new
-- real login and get the exact ids needed to link Bennett and Luellla to it.

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
WHERE LOWER(COALESCE(s.email, ''))        = LOWER('hailee.taylor@curebraincancer.org.au')
   OR LOWER(COALESCE(s.parent_email, '')) = LOWER('hailee.taylor@curebraincancer.org.au')
ORDER BY p.first_name;
