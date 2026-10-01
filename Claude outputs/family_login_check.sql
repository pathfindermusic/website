-- For every active student with no login of their own, show whether
-- someone else in their family (matched by shared email OR parent_email,
-- case-insensitively) already has a real login elsewhere, and who.
--
-- someone_has_login = true  -> link this student to login_holder's account,
--                               don't create a new one.
-- someone_has_login = false -> genuinely needs a brand-new "Add Login".

WITH active AS (
  SELECT
    s.id,
    s.user_id,
    p.first_name,
    p.last_name,
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
family_login AS (
  SELECT
    am.addr,
    BOOL_OR(a.has_login) AS someone_has_login,
    MAX(CASE WHEN a.has_login THEN a.first_name || ' ' || a.last_name END) AS login_holder
  FROM addr_map am
  JOIN active a ON a.id = am.id
  GROUP BY am.addr
)
SELECT DISTINCT
  a.first_name, a.last_name, a.email, a.parent_email,
  fl.someone_has_login, fl.login_holder
FROM active a
JOIN addr_map am ON am.id = a.id
JOIN family_login fl ON fl.addr = am.addr
WHERE a.has_login = false
ORDER BY fl.someone_has_login DESC, a.last_name, a.first_name;
