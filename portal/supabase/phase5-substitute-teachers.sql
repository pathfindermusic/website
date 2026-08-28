-- ============================================================
-- PATHFINDER PORTAL — substitute teachers
--
-- Two scenarios, and they need different things:
--
--   1. Another permanent teacher covers the lesson. They are
--      recorded against the occurrence, and it appears in their
--      calendar rather than the usual teacher's.
--
--   2. Someone from outside covers it. They have no portal
--      account, so their name is simply recorded and an admin
--      marks the attendance they report.
--
-- Both are per OCCURRENCE, not per series — a substitution is
-- one lesson, not a change of teacher.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The columns
-- ------------------------------------------------------------
ALTER TABLE lesson_occurrences
  ADD COLUMN IF NOT EXISTS substitute_teacher_id uuid REFERENCES teachers(id) ON DELETE SET NULL;

ALTER TABLE lesson_occurrences
  ADD COLUMN IF NOT EXISTS substitute_name text;

CREATE INDEX IF NOT EXISTS lesson_occurrences_substitute_idx
  ON lesson_occurrences (substitute_teacher_id) WHERE substitute_teacher_id IS NOT NULL;


-- ------------------------------------------------------------
-- 2. schedule_view — teacher_id and teacher_name become the
--    EFFECTIVE teacher, so a covered lesson appears in the
--    substitute's schedule and not the usual teacher's.
--
--    The original is still exposed, so the grid can show who it
--    would normally be.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS schedule_view;

CREATE VIEW schedule_view AS
SELECT
  lo.id                AS occurrence_id,
  lo.date,
  lo.status            AS occurrence_status,
  lo.is_online,
  lo.occurrence_notes,

  l.id                 AS lesson_id,

  -- Whoever is actually teaching this one
  COALESCE(lo.substitute_teacher_id, l.teacher_id) AS teacher_id,
  l.teacher_id         AS original_teacher_id,
  lo.substitute_teacher_id,
  lo.substitute_name,

  l.studio_id,
  l.instrument,
  l.start_time,
  l.duration_mins,
  l.lesson_type,
  l.max_students,
  l.series_notes,
  l.status             AS lesson_status,

  (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id) AS student_count,
  (SELECT COUNT(*) FROM attendance     x WHERE x.lesson_occurrence_id = lo.id) AS attendance_marked_count,

  (
    (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id) > 0
    AND
    (SELECT COUNT(*) FROM attendance x WHERE x.lesson_occurrence_id = lo.id)
      >= (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id)
  )                    AS fully_marked,

  CASE WHEN (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id) = 1
       THEN (SELECT x.status FROM attendance x WHERE x.lesson_occurrence_id = lo.id LIMIT 1)
       ELSE NULL
  END                  AS attendance_status,
  CASE WHEN (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id) = 1
       THEN (SELECT x.marked_at FROM attendance x WHERE x.lesson_occurrence_id = lo.id LIMIT 1)
       ELSE NULL
  END                  AS attendance_marked_at,

  (SELECT p.first_name || ' ' || p.last_name
     FROM lesson_students ls
     JOIN students s ON s.id = ls.student_id
     JOIN profiles p ON p.id = s.user_id
    WHERE ls.lesson_id = l.id
    ORDER BY p.first_name
    LIMIT 1)           AS student_name,

  -- The name shown on the schedule: the substitute where there is
  -- one, whether they are on staff or not.
  COALESCE(
    (SELECT ps.first_name || ' ' || ps.last_name
       FROM teachers ts JOIN profiles ps ON ps.id = ts.user_id
      WHERE ts.id = lo.substitute_teacher_id),
    NULLIF(lo.substitute_name, ''),
    p_t.first_name || ' ' || p_t.last_name
  )                    AS teacher_name,

  (p_t.first_name || ' ' || p_t.last_name) AS original_teacher_name,

  st.name              AS studio_name,
  st.email             AS studio_email,

  n.note_text,
  n.drive_link

FROM lesson_occurrences lo
JOIN lessons  l    ON l.id   = lo.lesson_id
JOIN teachers t    ON t.id   = l.teacher_id
JOIN profiles p_t  ON p_t.id = t.user_id
JOIN studios  st   ON st.id  = l.studio_id
LEFT JOIN lesson_notes n ON n.lesson_occurrence_id = lo.id;


-- ------------------------------------------------------------
-- 3. student_schedule_view — students should see who is actually
--    taking their lesson.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS student_schedule_view;

CREATE VIEW student_schedule_view AS
SELECT
  ls.student_id,

  lo.id                AS occurrence_id,
  lo.date,
  lo.status            AS occurrence_status,
  lo.is_online,
  lo.occurrence_notes,

  l.id                 AS lesson_id,
  COALESCE(lo.substitute_teacher_id, l.teacher_id) AS teacher_id,
  lo.substitute_teacher_id,
  lo.substitute_name,

  l.studio_id,
  l.instrument,
  l.start_time,
  l.duration_mins,
  l.lesson_type,
  l.max_students,
  l.series_notes,
  l.status             AS lesson_status,

  (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id) AS student_count,

  COALESCE(
    (SELECT ps.first_name || ' ' || ps.last_name
       FROM teachers ts JOIN profiles ps ON ps.id = ts.user_id
      WHERE ts.id = lo.substitute_teacher_id),
    NULLIF(lo.substitute_name, ''),
    p_t.first_name || ' ' || p_t.last_name
  )                    AS teacher_name,

  (p_t.first_name || ' ' || p_t.last_name) AS original_teacher_name,

  t.virtual_room_link,
  t.teaching_room,
  st.name              AS studio_name,
  st.email             AS studio_email,

  a.status             AS attendance_status,
  a.marked_at          AS attendance_marked_at,

  n.note_text,
  n.drive_link

FROM lesson_occurrences lo
JOIN lessons        l   ON l.id   = lo.lesson_id
JOIN lesson_students ls ON ls.lesson_id = l.id
JOIN teachers       t   ON t.id   = l.teacher_id
JOIN profiles       p_t ON p_t.id = t.user_id
JOIN studios        st  ON st.id  = l.studio_id
LEFT JOIN attendance   a ON a.lesson_occurrence_id = lo.id
                        AND a.student_id = ls.student_id
LEFT JOIN lesson_notes n ON n.lesson_occurrence_id = lo.id;


-- ------------------------------------------------------------
-- 4. The views were switched to security_invoker to close a
--    Supabase lint. Recreating them resets that, so set it again.
-- ------------------------------------------------------------
ALTER VIEW schedule_view         SET (security_invoker = on);
ALTER VIEW student_schedule_view SET (security_invoker = on);


-- ------------------------------------------------------------
-- 5. A substitute needs to read the lesson they are covering,
--    which is not theirs by lessons.teacher_id.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_substitute_lesson_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY(
    SELECT DISTINCT lo.lesson_id
      FROM lesson_occurrences lo
     WHERE lo.substitute_teacher_id = get_my_teacher_id()
  ), ARRAY[]::uuid[]);
$$;

DROP POLICY IF EXISTS "teacher_reads_covered_lessons" ON lessons;
CREATE POLICY "teacher_reads_covered_lessons" ON lessons FOR SELECT
  USING (id = ANY(my_substitute_lesson_ids()));

DROP POLICY IF EXISTS "teacher_reads_covered_occurrences" ON lesson_occurrences;
CREATE POLICY "teacher_reads_covered_occurrences" ON lesson_occurrences FOR SELECT
  USING (substitute_teacher_id = get_my_teacher_id());

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT column_name FROM information_schema.columns
 WHERE table_name = 'lesson_occurrences'
   AND column_name IN ('substitute_teacher_id','substitute_name');

SELECT c.relname,
       COALESCE((SELECT option_value FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'security_invoker'), 'off') AS security_invoker
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'v'
 ORDER BY c.relname;

SELECT COUNT(*) AS occurrences_with_a_substitute
  FROM lesson_occurrences
 WHERE substitute_teacher_id IS NOT NULL OR COALESCE(substitute_name,'') <> '';
