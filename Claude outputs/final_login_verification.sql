-- Final check: every active student and whether their user_id resolves
-- to a real login. After today's fixes, the only has_login = false rows
-- should be:
--   - Simon Surrao      (enrolment ending next week, deliberately skipped)
--   - Ananya Anish      (has a separate teacher login instead)
--   - Vikatoa Topou     (has a separate teacher login instead)
-- Any OTHER row with has_login = false means something was missed.

SELECT
  p.first_name,
  p.last_name,
  s.email,
  s.parent_email,
  s.user_id,
  (au.id IS NOT NULL) AS has_login
FROM students s
LEFT JOIN profiles  p  ON p.id  = s.user_id
LEFT JOIN auth.users au ON au.id = s.user_id
WHERE s.status = 'active'
ORDER BY has_login ASC, p.last_name, p.first_name;
