-- ============================================================
-- PATHFINDER PORTAL — makeup lessons
--
-- A makeup was only ever recorded in the occurrence note text
-- ("Makeup for 20 July"), which cannot be styled, filtered or
-- counted. A flag makes it visible on the schedule at a glance,
-- and the monthly view — which reads schedule_view rather than the
-- table — needs the views rebuilt to see it.
--
-- Per occurrence, since a makeup is a single lesson.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The flag
-- ------------------------------------------------------------
ALTER TABLE lesson_occurrences
  ADD COLUMN IF NOT EXISTS is_makeup boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS lesson_occurrences_makeup_idx
  ON lesson_occurrences (is_makeup) WHERE is_makeup;

-- Anything already noted as a makeup picks up the flag, so existing
-- lessons get the new styling without being re-entered.
UPDATE lesson_occurrences
   SET is_makeup = true
 WHERE is_makeup = false
   AND occurrence_notes ILIKE '%makeup%';


-- ------------------------------------------------------------
-- 2. Both views, rebuilt to expose it
--
-- A view's column list cannot be extended in place, so these are
-- the full definitions from phase5-substitute-teachers.sql with
-- lo.is_makeup added.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS schedule_view;

CREATE VIEW schedule_view AS
SELECT
  lo.id                AS occurrence_id,
  lo.date,
  lo.status            AS occurrence_status,
  lo.is_online,
  lo.occurrence_notes,
  lo.is_makeup,

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
  lo.is_makeup,

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
-- 3. Recreating a view resets security_invoker, which closes a
--    Supabase lint. Set it again or the lint silently reopens.
-- ------------------------------------------------------------
ALTER VIEW schedule_view         SET (security_invoker = on);
ALTER VIEW student_schedule_view SET (security_invoker = on);

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT column_name FROM information_schema.columns
 WHERE table_name = 'lesson_occurrences' AND column_name = 'is_makeup';

SELECT column_name FROM information_schema.columns
 WHERE table_name = 'schedule_view' AND column_name = 'is_makeup';

SELECT c.relname,
       COALESCE((SELECT option_value FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'security_invoker'), 'off') AS security_invoker
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'v'
 ORDER BY c.relname;

SELECT COUNT(*) AS flagged_from_notes FROM lesson_occurrences WHERE is_makeup;
