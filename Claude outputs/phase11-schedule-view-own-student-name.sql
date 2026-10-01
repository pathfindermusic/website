-- Phase 11 — schedule_view.student_name (used by the admin Schedule page
-- for a private lesson's label) is computed inside the database view
-- itself, straight from the shared profiles row — same bug as everywhere
-- else fixed in phase 10, just baked into SQL instead of JS. Run this
-- AFTER phase10-student-own-name.sql, since it needs students.first_name/
-- last_name to exist.
--
-- Everything else in the view is byte-for-byte identical to the current
-- definition (phase5-schedule-view-optimize.sql) — only the `roster`
-- lateral join's name computation changes, to prefer the student's own
-- name over the shared login's profile.
--
-- ⚠ RUN ONE STATEMENT AT A TIME and check each result.

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
    -- Student's own name first (students.first_name/last_name, phase 10,
    -- Oct 2026) — falls back to the shared login's profile only for a
    -- student who somehow has neither.
    (ARRAY_AGG(
        COALESCE(s.first_name, p.first_name) || ' ' || COALESCE(s.last_name, p.last_name)
        ORDER BY COALESCE(s.first_name, p.first_name)
     )
       FILTER (WHERE COALESCE(s.first_name, p.first_name) IS NOT NULL))[1] AS student_name
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

ALTER VIEW schedule_view SET (security_invoker = on);

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================

-- a. Column list unchanged — same 31 columns as before.
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

-- c. Spot-check one of the relinked families' private lessons — pick an
--    occurrence_id for, say, one of the Anoop/Sinha family's guitar
--    lessons, and confirm student_name now shows the right individual,
--    not "Anoop Sinha" for all of them.
-- SELECT occurrence_id, student_name
--   FROM schedule_view
--  WHERE occurrence_id = 'PASTE-A-KNOWN-OCCURRENCE-ID-HERE';
