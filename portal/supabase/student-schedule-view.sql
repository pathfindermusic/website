-- ============================================================
-- PATHFINDER PORTAL — student_schedule_view
--
-- Why a separate view: schedule_view has one row per occurrence,
-- so it cannot carry a single student_id (a group lesson has
-- several students). This view fans out to one row per
-- (occurrence x student), which means:
--   * the student dashboard can filter by student_id as before
--   * group lessons correctly appear in every member's schedule
-- ============================================================

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
  l.teacher_id,
  l.studio_id,
  l.instrument,
  l.start_time,
  l.duration_mins,
  l.lesson_type,
  l.max_students,
  l.series_notes,
  l.status             AS lesson_status,

  -- how many students share this lesson (1 for private)
  (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id) AS student_count,

  (p_t.first_name || ' ' || p_t.last_name)  AS teacher_name,
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
LEFT JOIN lesson_notes n ON n.lesson_occurrence_id = lo.id;


-- ------------------------------------------------------------
-- Verify: should list student_id first, then the rest
-- ------------------------------------------------------------
SELECT column_name
  FROM information_schema.columns
 WHERE table_name = 'student_schedule_view'
 ORDER BY ordinal_position;
