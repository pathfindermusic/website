-- ============================================================
-- PATHFINDER PORTAL — occurrence-only (ad-hoc) students
--
-- Why: the Lessons dashboard only let an admin add a student to a
-- lesson permanently (every past/future occurrence of that series).
-- There was no way to add a one-off guest to a single occurrence of
-- a group lesson — e.g. a sibling sitting in on one class — without
-- either permanently enrolling them in the whole series or not
-- recording them at all.
--
-- This adds one nullable column to lesson_students:
--   NULL                    → permanent series member (today's only
--                              behaviour, completely unchanged)
--   a lesson_occurrences.id → this student is on the roster for
--                              THAT occurrence only
--
-- schedule_view and student_schedule_view are rebuilt so their
-- per-occurrence figures (student_count, attendance columns,
-- student_name) count/see a student on a given occurrence only when
-- the row applies to it — either permanent, or scoped to that exact
-- occurrence. Everything else about the views is unchanged from
-- phase5-makeup-lessons.sql.
--
-- No RLS policy changes: lesson_students' write policies are role-
-- based (admin/superuser), not column-based, so they already cover
-- inserts with this column set.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The column
-- ------------------------------------------------------------
ALTER TABLE lesson_students
  ADD COLUMN IF NOT EXISTS added_for_occurrence_id uuid
    REFERENCES lesson_occurrences(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS lesson_students_occurrence_idx
  ON lesson_students (added_for_occurrence_id)
  WHERE added_for_occurrence_id IS NOT NULL;


-- ------------------------------------------------------------
-- 2. Both views, rebuilt to be occurrence-aware
--
-- A view's column list cannot be extended in place, so these are
-- the full definitions from phase5-makeup-lessons.sql, with every
-- lesson_students join/subquery now also matching an occurrence-
-- scoped row when it belongs to THIS occurrence (lo.id), on top of
-- always matching a permanent row (added_for_occurrence_id IS NULL).
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

  (SELECT COUNT(*) FROM lesson_students x
    WHERE x.lesson_id = l.id
      AND (x.added_for_occurrence_id IS NULL OR x.added_for_occurrence_id = lo.id)
  ) AS student_count,
  (SELECT COUNT(*) FROM attendance x WHERE x.lesson_occurrence_id = lo.id) AS attendance_marked_count,

  (
    (SELECT COUNT(*) FROM lesson_students x
      WHERE x.lesson_id = l.id
        AND (x.added_for_occurrence_id IS NULL OR x.added_for_occurrence_id = lo.id)) > 0
    AND
    (SELECT COUNT(*) FROM attendance x WHERE x.lesson_occurrence_id = lo.id)
      >= (SELECT COUNT(*) FROM lesson_students x
           WHERE x.lesson_id = l.id
             AND (x.added_for_occurrence_id IS NULL OR x.added_for_occurrence_id = lo.id))
  )                    AS fully_marked,

  CASE WHEN (SELECT COUNT(*) FROM lesson_students x
              WHERE x.lesson_id = l.id
                AND (x.added_for_occurrence_id IS NULL OR x.added_for_occurrence_id = lo.id)) = 1
       THEN (SELECT x.status FROM attendance x WHERE x.lesson_occurrence_id = lo.id LIMIT 1)
       ELSE NULL
  END                  AS attendance_status,
  CASE WHEN (SELECT COUNT(*) FROM lesson_students x
              WHERE x.lesson_id = l.id
                AND (x.added_for_occurrence_id IS NULL OR x.added_for_occurrence_id = lo.id)) = 1
       THEN (SELECT x.marked_at FROM attendance x WHERE x.lesson_occurrence_id = lo.id LIMIT 1)
       ELSE NULL
  END                  AS attendance_marked_at,

  (SELECT p.first_name || ' ' || p.last_name
     FROM lesson_students ls
     JOIN students s ON s.id = ls.student_id
     JOIN profiles p ON p.id = s.user_id
    WHERE ls.lesson_id = l.id
      AND (ls.added_for_occurrence_id IS NULL OR ls.added_for_occurrence_id = lo.id)
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
-- 3. student_schedule_view — an occurrence-only student sees just
--    that occurrence, not every date of the lesson.
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

  (SELECT COUNT(*) FROM lesson_students x
    WHERE x.lesson_id = l.id
      AND (x.added_for_occurrence_id IS NULL OR x.added_for_occurrence_id = lo.id)
  ) AS student_count,

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
                        AND (ls.added_for_occurrence_id IS NULL OR ls.added_for_occurrence_id = lo.id)
JOIN teachers       t   ON t.id   = l.teacher_id
JOIN profiles       p_t ON p_t.id = t.user_id
JOIN studios        st  ON st.id  = l.studio_id
LEFT JOIN attendance   a ON a.lesson_occurrence_id = lo.id
                        AND a.student_id = ls.student_id
LEFT JOIN lesson_notes n ON n.lesson_occurrence_id = lo.id;


-- ------------------------------------------------------------
-- 4. Recreating a view resets security_invoker, which closes a
--    Supabase lint. Set it again or the lint silently reopens.
-- ------------------------------------------------------------
ALTER VIEW schedule_view         SET (security_invoker = on);
ALTER VIEW student_schedule_view SET (security_invoker = on);

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT column_name, is_nullable FROM information_schema.columns
 WHERE table_name = 'lesson_students' AND column_name = 'added_for_occurrence_id';

SELECT indexname FROM pg_indexes
 WHERE tablename = 'lesson_students' AND indexname = 'lesson_students_occurrence_idx';

SELECT c.relname,
       COALESCE((SELECT option_value FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'security_invoker'), 'off') AS security_invoker
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'v'
 ORDER BY c.relname;

-- Should be 0 until the portal starts using it
SELECT COUNT(*) FROM lesson_students WHERE added_for_occurrence_id IS NOT NULL;
