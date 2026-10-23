-- ============================================================
-- PATHFINDER PORTAL — student flags ("watch" / "do not re-enrol")
--
-- Admins can flag a student (typically a bad payer) so a family that
-- comes back is spotted. The flag lives in its OWN table, readable only by
-- admins and superusers: a column on `students` would be visible to the
-- student's own family through the normal API.
--
--   level   'watch'  — e.g. ask for payment up front
--           'block'  — do not re-enrol
--   One ACTIVE flag per student; clearing keeps the row as history.
--
-- Two lookup functions find flagged people from contact details (same email,
-- phone or full name), across ALL studios — a family that left Kilsyth and
-- turns up at Ringwood is still caught. They return flags only.
--
-- ⚠ Run ONE STATEMENT AT A TIME in the Supabase SQL editor, in order.
-- Needs: get_my_role(), students, profiles, studios.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The table
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.student_flags (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id  uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  level       text NOT NULL CHECK (level IN ('watch','block')),
  reason      text NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 1 AND 1000),
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid,
  updated_at  timestamptz,
  cleared_at  timestamptz,
  cleared_by  uuid,
  clear_note  text CHECK (clear_note IS NULL OR char_length(clear_note) <= 500)
);


-- ------------------------------------------------------------
-- 2. At most one ACTIVE flag per student
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS student_flags_one_active
  ON public.student_flags (student_id) WHERE cleared_at IS NULL;


-- ------------------------------------------------------------
-- 3. Row Level Security: admins and superusers only
--    ("student_id IN (SELECT id FROM students)" keeps a studio-limited
--     admin to the students they can already see.)
-- ------------------------------------------------------------
ALTER TABLE public.student_flags ENABLE ROW LEVEL SECURITY;


-- 4. (separate statement)
DROP POLICY IF EXISTS "Admins manage student flags" ON public.student_flags;
CREATE POLICY "Admins manage student flags"
  ON public.student_flags FOR ALL
  USING (
    get_my_role() IN ('superuser','admin')
    AND student_id IN (SELECT id FROM public.students)
  )
  WITH CHECK (
    get_my_role() IN ('superuser','admin')
    AND student_id IN (SELECT id FROM public.students)
  );


-- ------------------------------------------------------------
-- 5. Privileges (Supabase no longer grants these automatically on new
--    tables). No access for anon.
-- ------------------------------------------------------------
REVOKE ALL ON public.student_flags FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.student_flags TO authenticated, service_role;


-- ------------------------------------------------------------
-- 6. Look up flagged people from contact details.
--    SECURITY DEFINER so it sees every studio; admins and superusers only.
--    Phones match on their last 9 digits, emails case-insensitively
--    (student's own email or the parent's), names on first + last.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.flag_check(
  p_email   text,
  p_phone   text,
  p_first   text,
  p_last    text,
  p_exclude uuid DEFAULT NULL
)
RETURNS TABLE (
  student_id     uuid,
  student_name   text,
  student_status text,
  studio_name    text,
  level          text,
  reason         text,
  flagged_at     timestamptz,
  why            text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  e  text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  ph text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 9);
  fn text := lower(btrim(coalesce(p_first, '')));
  ln text := lower(btrim(coalesce(p_last, '')));
BEGIN
  IF get_my_role() NOT IN ('superuser','admin') THEN RAISE EXCEPTION 'not_allowed'; END IF;
  IF char_length(ph) < 8 THEN ph := NULL; END IF;

  RETURN QUERY
  SELECT m.id, m.nm, m.status, m.studio, m.level, m.reason, m.created_at, m.why
    FROM (
      SELECT s.id,
             btrim(coalesce(s.first_name, pr.first_name, '') || ' ' || coalesce(s.last_name, pr.last_name, '')) AS nm,
             s.status, st.name AS studio, f.level, f.reason, f.created_at,
             concat_ws(', ',
               CASE WHEN e IS NOT NULL AND (lower(btrim(coalesce(s.email, ''))) = e
                                         OR lower(btrim(coalesce(s.parent_email, ''))) = e)
                    THEN 'same email' END,
               CASE WHEN ph IS NOT NULL AND (right(regexp_replace(coalesce(pr.phone, ''), '\D', '', 'g'), 9) = ph
                                          OR right(regexp_replace(coalesce(s.parent_phone, ''), '\D', '', 'g'), 9) = ph)
                    THEN 'same phone' END,
               CASE WHEN fn <> '' AND ln <> ''
                         AND lower(btrim(coalesce(s.first_name, pr.first_name, ''))) = fn
                         AND lower(btrim(coalesce(s.last_name,  pr.last_name,  ''))) = ln
                    THEN 'same name' END
             ) AS why
        FROM public.student_flags f
        JOIN public.students s     ON s.id = f.student_id
        LEFT JOIN public.profiles pr ON pr.id = s.user_id
        LEFT JOIN public.studios  st ON st.id = s.studio_id
       WHERE f.cleared_at IS NULL
         AND s.id IS DISTINCT FROM p_exclude
    ) m
   WHERE m.why <> ''
   ORDER BY (m.level = 'block') DESC, m.created_at DESC;
END;
$$;


-- ------------------------------------------------------------
-- 7. The same, for a list of students at once (list pages). Returns the
--    student's OWN active flag too (why = 'this record').
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.flag_check_students(p_ids uuid[])
RETURNS TABLE (
  for_student_id uuid,
  student_id     uuid,
  student_name   text,
  student_status text,
  studio_name    text,
  level          text,
  reason         text,
  flagged_at     timestamptz,
  why            text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF get_my_role() NOT IN ('superuser','admin') THEN RAISE EXCEPTION 'not_allowed'; END IF;

  RETURN QUERY
  WITH t AS (
    SELECT s.id,
           nullif(lower(btrim(coalesce(s.email, ''))), '')        AS email,
           nullif(lower(btrim(coalesce(s.parent_email, ''))), '') AS pemail,
           nullif(right(regexp_replace(coalesce(pr.phone, ''), '\D', '', 'g'), 9), '')        AS phone,
           nullif(right(regexp_replace(coalesce(s.parent_phone, ''), '\D', '', 'g'), 9), '') AS pphone,
           lower(btrim(coalesce(s.first_name, pr.first_name, ''))) AS fn,
           lower(btrim(coalesce(s.last_name,  pr.last_name,  ''))) AS ln
      FROM public.students s
      LEFT JOIN public.profiles pr ON pr.id = s.user_id
     WHERE s.id = ANY(p_ids)
  ),
  fl AS (
    SELECT s.id,
           btrim(coalesce(s.first_name, pr.first_name, '') || ' ' || coalesce(s.last_name, pr.last_name, '')) AS nm,
           s.status, st.name AS studio, f.level, f.reason, f.created_at,
           nullif(lower(btrim(coalesce(s.email, ''))), '')        AS email,
           nullif(lower(btrim(coalesce(s.parent_email, ''))), '') AS pemail,
           nullif(right(regexp_replace(coalesce(pr.phone, ''), '\D', '', 'g'), 9), '')        AS phone,
           nullif(right(regexp_replace(coalesce(s.parent_phone, ''), '\D', '', 'g'), 9), '') AS pphone,
           lower(btrim(coalesce(s.first_name, pr.first_name, ''))) AS fn,
           lower(btrim(coalesce(s.last_name,  pr.last_name,  ''))) AS ln
      FROM public.student_flags f
      JOIN public.students s     ON s.id = f.student_id
      LEFT JOIN public.profiles pr ON pr.id = s.user_id
      LEFT JOIN public.studios  st ON st.id = s.studio_id
     WHERE f.cleared_at IS NULL
  )
  SELECT x.tid, x.id, x.nm, x.status, x.studio, x.level, x.reason, x.created_at, x.why
    FROM (
      SELECT t.id AS tid, fl.id, fl.nm, fl.status, fl.studio, fl.level, fl.reason, fl.created_at,
             CASE WHEN t.id = fl.id THEN 'this record'
                  ELSE concat_ws(', ',
                    CASE WHEN (t.email IS NOT NULL AND t.email IN (fl.email, fl.pemail))
                           OR (t.pemail IS NOT NULL AND t.pemail IN (fl.email, fl.pemail))
                         THEN 'same email' END,
                    CASE WHEN char_length(coalesce(t.phone, '')) >= 8 AND t.phone IN (coalesce(fl.phone, '-'), coalesce(fl.pphone, '-'))
                           OR char_length(coalesce(t.pphone, '')) >= 8 AND t.pphone IN (coalesce(fl.phone, '-'), coalesce(fl.pphone, '-'))
                         THEN 'same phone' END,
                    CASE WHEN t.fn <> '' AND t.ln <> '' AND t.fn = fl.fn AND t.ln = fl.ln
                         THEN 'same name' END)
             END AS why
        FROM t CROSS JOIN fl
    ) x
   WHERE x.why <> ''
   ORDER BY x.tid, (x.level = 'block') DESC, x.created_at DESC;
END;
$$;


-- ------------------------------------------------------------
-- 8. Who may call the lookups (the functions also check the role)
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.flag_check(text, text, text, text, uuid) FROM PUBLIC, anon;


-- 9. (separate statement)
GRANT EXECUTE ON FUNCTION public.flag_check(text, text, text, text, uuid) TO authenticated;


-- 10. (separate statement)
REVOKE ALL ON FUNCTION public.flag_check_students(uuid[]) FROM PUBLIC, anon;


-- 11. (separate statement)
GRANT EXECUTE ON FUNCTION public.flag_check_students(uuid[]) TO authenticated;


-- ------------------------------------------------------------
-- 12. Verify — expect the table with relrowsecurity = true, one policy, and
--     both functions listed.
-- ------------------------------------------------------------
SELECT c.relname, c.relrowsecurity
  FROM pg_class c WHERE c.relname = 'student_flags';

SELECT policyname, cmd FROM pg_policies WHERE tablename = 'student_flags';

SELECT proname FROM pg_proc WHERE proname IN ('flag_check', 'flag_check_students');
