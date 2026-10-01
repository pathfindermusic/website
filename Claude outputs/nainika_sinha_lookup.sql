-- Direct lookup: find exactly which student record(s) this name currently
-- belongs to, any status, so we can see why it didn't show up in the
-- shared-login scope query (e.g. non-active status, or genuinely distinct
-- logins that happen to share a name/typo rather than sharing a user_id).

SELECT
  s.id            AS student_id,
  s.status,
  s.user_id,
  p.first_name,
  p.last_name,
  s.email,
  s.parent_email,
  (SELECT COUNT(*) FROM students s2 WHERE s2.user_id = s.user_id) AS students_sharing_this_login
FROM students s
JOIN profiles p ON p.id = s.user_id
WHERE p.first_name ILIKE '%nainika%'
   OR p.last_name  ILIKE '%sinha%'
ORDER BY s.user_id, s.id;
