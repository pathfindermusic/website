-- Scope check: every ACTIVE student whose user_id (login) is shared with
-- at least one other active student. Because a student's displayed name
-- comes entirely from `profiles` (keyed by user_id) and `students` has no
-- name field of its own, every row in a group below currently displays
-- (and edits) the SAME name, regardless of who the individual actually is.

WITH active AS (
  SELECT s.id, s.user_id, p.first_name, p.last_name
  FROM students s
  JOIN profiles p ON p.id = s.user_id
  WHERE s.status = 'active'
),
dupes AS (
  SELECT user_id FROM active GROUP BY user_id HAVING COUNT(*) > 1
)
SELECT
  a.user_id,
  a.first_name || ' ' || a.last_name AS shown_name,
  a.id AS student_id
FROM active a
JOIN dupes d ON d.user_id = a.user_id
ORDER BY a.user_id, a.id;
