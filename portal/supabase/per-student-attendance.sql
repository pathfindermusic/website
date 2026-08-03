-- ============================================================
-- PATHFINDER PORTAL — per-student attendance
--
-- Attendance was one row per occurrence, so a group lesson could
-- only be marked as a whole. This migrates it to one row per
-- (occurrence x student) so an individual absence can be recorded.
--
-- Lesson NOTES deliberately stay per-occurrence: for band lessons
-- the note is shared across the group.
--
-- Run the whole file. It is safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Add the student_id column
-- ------------------------------------------------------------
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS student_id uuid REFERENCES students(id) ON DELETE CASCADE;

-- ------------------------------------------------------------
-- 2. Backfill existing rows — assign to one student of the lesson
-- ------------------------------------------------------------
UPDATE attendance a
   SET student_id = sub.student_id
  FROM (
    SELECT lo.id AS occ_id,
           (ARRAY_AGG(ls.student_id ORDER BY ls.student_id))[1] AS student_id
      FROM lesson_occurrences lo
      JOIN lesson_students ls ON ls.lesson_id = lo.lesson_id
     GROUP BY lo.id
  ) sub
 WHERE a.lesson_occurrence_id = sub.occ_id
   AND a.student_id IS NULL;

-- ------------------------------------------------------------
-- 3. Replace the old one-row-per-occurrence unique constraint
-- ------------------------------------------------------------
DO $$
DECLARE cname text;
BEGIN
  SELECT conname INTO cname
    FROM pg_constraint
   WHERE conrelid = 'attendance'::regclass
     AND contype  = 'u'
     AND array_length(conkey, 1) = 1
     AND conkey[1] = (
       SELECT attnum FROM pg_attribute
        WHERE attrelid = 'attendance'::regclass
          AND attname  = 'lesson_occurrence_id'
     );
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE attendance DROP CONSTRAINT %I', cname);
  END IF;
END $$;

ALTER TABLE attendance
  DROP CONSTRAINT IF EXISTS attendance_occurrence_student_key;
ALTER TABLE attendance
  ADD CONSTRAINT attendance_occurrence_student_key
  UNIQUE (lesson_occurrence_id, student_id);

-- ------------------------------------------------------------
-- 4. For group lessons, copy the old group-level mark to every
--    other student so no history is lost
-- ------------------------------------------------------------
INSERT INTO attendance (lesson_occurrence_id, student_id, status, marked_by, marked_at)
SELECT a.lesson_occurrence_id, ls.student_id, a.status, a.marked_by, a.marked_at
  FROM attendance a
  JOIN lesson_occurrences lo ON lo.id = a.lesson_occurrence_id
  JOIN lesson_students   ls ON ls.lesson_id = lo.lesson_id
 WHERE a.student_id IS NOT NULL
   AND ls.student_id <> a.student_id
ON CONFLICT (lesson_occurrence_id, student_id) DO NOTHING;

-- ------------------------------------------------------------
-- 5. Drop any row we still could not attribute, then require it
-- ------------------------------------------------------------
DELETE FROM attendance WHERE student_id IS NULL;
ALTER TABLE attendance ALTER COLUMN student_id SET NOT NULL;


-- ============================================================
-- 6. schedule_view — one row per OCCURRENCE
--    The attendance join is now a subquery: a plain LEFT JOIN
--    would fan the view out to one row per student.
-- ============================================================
DROP VIEW IF EXISTS schedule_view;

CREATE VIEW schedule_view AS
SELECT
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

  (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id) AS student_count,
  (SELECT COUNT(*) FROM attendance     x WHERE x.lesson_occurrence_id = lo.id) AS attendance_marked_count,

  -- true once every student on the lesson has been marked
  (
    (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id) > 0
    AND
    (SELECT COUNT(*) FROM attendance x WHERE x.lesson_occurrence_id = lo.id)
      >= (SELECT COUNT(*) FROM lesson_students x WHERE x.lesson_id = l.id)
  )                    AS fully_marked,

  -- only meaningful for a single-student lesson
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

  (p_t.first_name || ' ' || p_t.last_name) AS teacher_name,
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


-- ============================================================
-- 7. student_schedule_view — one row per (occurrence x student)
--    Attendance now joins on student too, so each student sees
--    their own status.
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
                        AND a.student_id = ls.student_id
LEFT JOIN lesson_notes n ON n.lesson_occurrence_id = lo.id;


-- ============================================================
-- 8. Verify
-- ============================================================
SELECT 'attendance rows'  AS check, COUNT(*)::text AS value FROM attendance
UNION ALL
SELECT 'without student', COUNT(*)::text FROM attendance WHERE student_id IS NULL
UNION ALL
SELECT 'unique constraint',
       COALESCE((SELECT conname FROM pg_constraint
                  WHERE conrelid='attendance'::regclass AND contype='u'
                    AND array_length(conkey,1)=2 LIMIT 1), 'MISSING');
