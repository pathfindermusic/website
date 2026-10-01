-- PREVIEW ONLY — no changes made. Shows exactly which students would be
-- re-pointed to a sibling's existing login, and to which account, so you
-- can sanity-check the pairings before anything is updated for real.

WITH active AS (
  SELECT
    s.id, s.user_id,
    p.first_name, p.last_name,
    NULLIF(TRIM(s.email), '')        AS email,
    NULLIF(TRIM(s.parent_email), '') AS parent_email,
    (au.id IS NOT NULL)              AS has_login
  FROM students s
  LEFT JOIN profiles  p  ON p.id  = s.user_id
  LEFT JOIN auth.users au ON au.id = s.user_id
  WHERE s.status = 'active'
),
addr_map AS (
  SELECT id, LOWER(email) AS addr FROM active WHERE email IS NOT NULL
  UNION
  SELECT id, LOWER(parent_email) AS addr FROM active WHERE parent_email IS NOT NULL
),
holder AS (
  -- the one real-login student per shared address (DISTINCT ON picks one
  -- deterministically if more than one somehow qualifies)
  SELECT DISTINCT ON (am.addr)
    am.addr, a.id AS holder_student_id, a.user_id AS holder_user_id,
    a.first_name || ' ' || a.last_name AS holder_name
  FROM addr_map am
  JOIN active a ON a.id = am.id AND a.has_login
)
SELECT
  act.id          AS student_id,
  act.first_name, act.last_name,
  act.user_id     AS current_user_id,
  h.holder_user_id AS would_become_user_id,
  h.holder_name   AS linking_to
FROM active act
JOIN addr_map am ON am.id = act.id
JOIN holder h    ON h.addr = am.addr
WHERE act.has_login = false
ORDER BY h.holder_name, act.last_name, act.first_name;
