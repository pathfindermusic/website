-- ============================================================
-- PATHFINDER PORTAL — schedule_view: stop re-running the same
-- subquery 5+ times per row
--
-- Reported: an admin's Schedule page failed to load a week with
-- "canceling statement due to statement timeout" — the same symptom
-- as the earlier teacher timeout (phase5-schedule-performance-
-- indexes.sql), but NOT the same cause. That fix added indexes on
-- the columns these subqueries filter by (lesson_id,
-- lesson_occurrence_id, teacher_id, ...) — and those indexes are
-- still doing their job; EXPLAIN would show them being used.
--
-- The actual problem: schedule_view computes "how many students does
-- this lesson have" via an inline scalar subquery, then repeats that
-- EXACT SAME subquery — independently, not reused — for
-- student_count, twice more inside fully_marked's boolean expression,
-- and again inside both attendance_status and attendance_marked_at's
-- CASE WHEN. That's five separate executions of one identical
-- subquery per row, plus a fully separate subquery for the roster
-- name, plus two more for attendance's status/marked_at values —
-- roughly ten subquery executions per occurrence row, none of it
-- reused across the columns that need the same number.
--
-- The teacher page that was originally fixed queries ONE teacher's
-- ONE day — a handful of rows, so the redundancy was invisible. The
-- admin's Schedule queries an unfiltered WEEK across every studio and
-- teacher by default — one to several hundred rows — and ten
-- subqueries each, on a table that keeps growing, is what's now
-- crossing the statement timeout. Indexing the columns further
-- wouldn't fix this: the cost is the repetition itself, not a missing
-- index.
--
-- Fix: LEFT JOIN LATERAL computes each group of values (the roster,
-- the attendance marks, the substitute's name) exactly ONCE per row,
-- and every column that needs a piece of it reads from that same
-- computed row instead of re-querying. Same columns, same names, same
-- values — schedule_view's shape to the app is unchanged. Only
-- student_schedule_view is untouched here: it doesn't have this
-- repeated-subquery pattern (it uses a single subquery for
-- student_count and a plain LEFT JOIN for attendance already), so
-- there is nothing to fix there.
--
-- ⚠ RUN ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Rebuild schedule_view
--
-- Full definition from phase5-occurrence-only-students.sql, with the
-- repeated scalar subqueries replaced by three LATERAL joins:
--   roster — student_count + student_name, from lesson_students
--            (still occurrence-aware: a permanent member always
--            counts, an ad-hoc guest only for the occurrence they
--            were added to)
--   att    — attendance_marked_count + the single mark's status/
--            marked_at, used only when there's exactly one student
--   sub    — the substitute's name, when one is set
-- Each is an aggregate query, which always returns exactly one row
-- (COUNT(*) = 0 counts as a row, not zero rows), so LEFT JOIN LATERAL
-- ... ON true behaves the same as the original scalar subqueries —
-- every occurrence still gets exactly one output row.
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

  roster.student_count,
  att.attendance_marked_count,

  (roster.student_count > 0
    AND att.attendance_marked_count >= roster.student_count
  )                    AS fully_marked,

  CASE WHEN roster.student_count = 1 THEN att.solo_status    ELSE NULL END AS attendance_status,
  CASE WHEN roster.student_count = 1 THEN att.solo_marked_at ELSE NULL END AS attendance_marked_at,

  roster.student_name,

  -- The name shown on the schedule: the substitute where there is
  -- one, whether they are on staff or not.
  COALESCE(
    sub.sub_name,
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
LEFT JOIN lesson_notes n ON n.lesson_occurrence_id = lo.id

LEFT JOIN LATERAL (
  SELECT
    COUNT(*) AS student_count,
    (ARRAY_AGG(p.first_name || ' ' || p.last_name ORDER BY p.first_name)
       FILTER (WHERE p.first_name IS NOT NULL))[1] AS student_name
  FROM lesson_students x
  LEFT JOIN students s ON s.id = x.student_id
  LEFT JOIN profiles p ON p.id = s.user_id
  WHERE x.lesson_id = l.id
    AND (x.added_for_occurrence_id IS NULL OR x.added_for_occurrence_id = lo.id)
) roster ON true

LEFT JOIN LATERAL (
  SELECT
    COUNT(*) AS attendance_marked_count,
    (ARRAY_AGG(a.status    ORDER BY a.marked_at))[1] AS solo_status,
    (ARRAY_AGG(a.marked_at ORDER BY a.marked_at))[1] AS solo_marked_at
  FROM attendance a
  WHERE a.lesson_occurrence_id = lo.id
) att ON true

LEFT JOIN LATERAL (
  SELECT ps.first_name || ' ' || ps.last_name AS sub_name
  FROM teachers ts JOIN profiles ps ON ps.id = ts.user_id
  WHERE ts.id = lo.substitute_teacher_id
) sub ON true;


-- ------------------------------------------------------------
-- 2. Recreating a view resets security_invoker, which closes a
--    Supabase lint. Set it again or the lint silently reopens.
-- ------------------------------------------------------------
ALTER VIEW schedule_view SET (security_invoker = on);

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================

-- a. Column list unchanged — should be the same 31 columns as
--    before (occurrence_id .. drive_link), no additions/removals.
SELECT column_name
  FROM information_schema.columns
 WHERE table_name = 'schedule_view'
 ORDER BY ordinal_position;

-- b. security_invoker is back on
SELECT c.relname,
       COALESCE((SELECT option_value FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'security_invoker'), 'off') AS security_invoker
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'schedule_view';

-- c. The query that was timing out, run as it would from the admin
--    dashboard's default (unfiltered) view — a whole week, every
--    studio, every teacher. Substitute this week's actual Monday and
--    Saturday. Look at the "Execution Time" at the bottom — should be
--    well under a second, not multiple seconds.
-- EXPLAIN ANALYZE
-- SELECT * FROM schedule_view
--  WHERE date >= 'YYYY-MM-DD' AND date <= 'YYYY-MM-DD'
--  ORDER BY date, start_time;

-- d. Spot-check the numbers are still right for a lesson you know —
--    student_count, fully_marked and attendance_status should match
--    what the Lessons page shows for the same occurrence.
-- SELECT occurrence_id, student_count, attendance_marked_count,
--        fully_marked, attendance_status, student_name
--   FROM schedule_view
--  WHERE occurrence_id = 'PASTE-A-KNOWN-OCCURRENCE-ID-HERE';
