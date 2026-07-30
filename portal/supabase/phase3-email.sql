-- ============================================================
-- PATHFINDER PORTAL — Phase 3 (Email notifications)
-- Run the whole file in the Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Email log — audit trail of every send
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS email_log (
  id              uuid primary key default gen_random_uuid(),
  sent_at         timestamptz not null default now(),
  sent_by         uuid,
  subject         text,
  body            text,
  recipient_mode  text,
  recipient_count int,
  recipients      jsonb,
  bcc             text,
  status          text,
  error           text
);

ALTER TABLE email_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read email log" ON email_log;
CREATE POLICY "Admins read email log"
  ON email_log FOR SELECT
  USING (get_my_role() IN ('superuser','admin'));

-- Note: inserts are made by the Netlify Function using the
-- service role key, which bypasses RLS. No insert policy needed.


-- ------------------------------------------------------------
-- 2. schedule_view — rebuilt to include EVERYTHING the
--    dashboards need. This supersedes the earlier version:
--    it restores attendance_status / note_text / drive_link
--    (which the teacher dashboard depends on) and adds
--    studio_email for the notification features.
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
  l.teacher_id,
  l.studio_id,
  l.instrument,
  l.start_time,
  l.duration_mins,
  l.lesson_type,
  l.max_students,
  l.series_notes,
  l.status             AS lesson_status,

  -- students on this lesson
  (SELECT COUNT(*) FROM lesson_students ls WHERE ls.lesson_id = l.id) AS student_count,
  (SELECT p.first_name || ' ' || p.last_name
     FROM lesson_students ls
     JOIN students s  ON s.id = ls.student_id
     JOIN profiles p  ON p.id = s.user_id
    WHERE ls.lesson_id = l.id
    ORDER BY p.first_name
    LIMIT 1)                                                          AS student_name,

  -- teacher + studio
  (p_t.first_name || ' ' || p_t.last_name)                            AS teacher_name,
  st.name                                                             AS studio_name,
  st.email                                                            AS studio_email,

  -- attendance (restored)
  a.status                                                            AS attendance_status,
  a.marked_at                                                         AS attendance_marked_at,

  -- lesson note (restored)
  n.note_text,
  n.drive_link

FROM lesson_occurrences lo
JOIN lessons  l    ON l.id   = lo.lesson_id
JOIN teachers t    ON t.id   = l.teacher_id
JOIN profiles p_t  ON p_t.id = t.user_id
JOIN studios  st   ON st.id  = l.studio_id
LEFT JOIN attendance   a ON a.lesson_occurrence_id = lo.id
LEFT JOIN lesson_notes n ON n.lesson_occurrence_id = lo.id;


-- ------------------------------------------------------------
-- 3. Verify
-- ------------------------------------------------------------
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'schedule_view'
ORDER BY ordinal_position;
