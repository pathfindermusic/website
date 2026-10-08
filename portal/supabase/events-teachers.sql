-- ============================================================
-- Events for teachers (migration #45)
--
--   1. A teacher's grid / running order shows only THEIR students and
--      the performances they are accompanying (and marks the latter).
--   2. When a student books with "Backing track", a task is created
--      for the teacher's performance: subject = the teacher, visible
--      to admins like any task about a teacher, due 2 weeks before the
--      event (or today, if the booking is made inside that window).
--      The task follows the booking: change the piece or teacher and
--      it updates; cancel the booking or switch accompaniment and it
--      is cancelled; switch back and it reopens.
--   3. get_event_teacher_summary(): the numbers and the backing-track
--      list for the summary card on the teacher's event page.
--
-- Run each numbered STEP ONE STATEMENT AT A TIME in the Supabase SQL
-- editor (the policy-name-without-body problem noted in earlier
-- migrations applies to anything run in bulk), and run it BEFORE
-- deploying the new events.html / events-common.js. Safe to re-run.
--
-- Needs: events.sql, events-per-instrument.sql, phase4a-tasks.sql and
-- phase7-recurring-tasks.sql (tasks_source_check includes 'system').
-- ============================================================


-- ============================================================
-- STEP 1 — link a task to the booking it came from
-- ============================================================
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS event_booking_id uuid
    REFERENCES event_bookings(id) ON DELETE SET NULL;


-- ============================================================
-- STEP 2 — at most one task per booking, ever. A booking that
-- drops the backing track and later asks for it again reopens its
-- task rather than creating a second one.
-- ============================================================
CREATE UNIQUE INDEX IF NOT EXISTS tasks_event_booking_uniq
  ON tasks (event_booking_id) WHERE event_booking_id IS NOT NULL;


-- ============================================================
-- STEP 3 — keep the backing-track task in step with its booking.
--
-- Fires after every insert / update of a booking, whichever door it
-- came through (student form, admin edit, cancel, move).
--   wanted  = booked + backing track + a teacher chosen from the list
--             (a free-text "Someone else / not sure" teacher has no
--             login to give a task to, so no task)
--   due     = the later of (event date - 14 days) and today
--   The student's own notes go into the task's log, so the teacher
--   reads them where they already look.
-- ============================================================
CREATE OR REPLACE FUNCTION _event_backing_task_trg()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ev        events%ROWTYPE;
  t         tasks%ROWTYPE;
  has_task  boolean;
  sname     text;
  ttl       text;
  due       date;
  today     date := (now() AT TIME ZONE 'Australia/Melbourne')::date;
  wanted    boolean := NEW.status = 'booked'
                       AND NEW.accompaniment = 'backing_track'
                       AND NEW.teacher_id IS NOT NULL;
  details   text;
  new_id    uuid;
BEGIN
  SELECT * INTO t FROM tasks WHERE event_booking_id = NEW.id;
  has_task := FOUND;

  -- ---- no longer wanted: close the open task, with the reason
  IF NOT wanted THEN
    IF has_task AND t.status = 'open' THEN
      UPDATE tasks SET status = 'cancelled' WHERE id = t.id;
      INSERT INTO task_notes (task_id, note_text) VALUES (t.id,
        CASE
          WHEN NEW.status <> 'booked'              THEN 'Cancelled automatically: the performance was cancelled.'
          WHEN NEW.accompaniment <> 'backing_track' THEN 'Cancelled automatically: the student no longer wants a backing track.'
          ELSE 'Cancelled automatically: the booking no longer names a teacher from the list.'
        END);
    END IF;
    RETURN NULL;
  END IF;

  SELECT * INTO ev FROM events WHERE id = NEW.event_id;
  SELECT btrim(coalesce(nullif(btrim(s.first_name), ''), p.first_name, '') || ' ' ||
               coalesce(nullif(btrim(s.last_name),  ''), p.last_name,  ''))
    INTO sname
    FROM students s LEFT JOIN profiles p ON p.id = s.user_id
   WHERE s.id = NEW.student_id;

  ttl := 'Backing track for ' || NEW.piece || ' — ' || coalesce(nullif(sname, ''), 'student') ||
         ' (' || ev.name || ')';
  due := greatest(ev.event_date - 14, today);

  details := coalesce(nullif(sname, ''), 'The student') || ' will perform "' || NEW.piece || '" (' ||
             NEW.instrument || ') at ' || ev.name || ' on ' ||
             to_char(ev.event_date, 'FMDay FMDD FMMonth YYYY') || ' and would like a backing track.' ||
             CASE WHEN NEW.notes IS NOT NULL AND btrim(NEW.notes) <> ''
                  THEN E'\nStudent''s notes: ' || NEW.notes ELSE '' END;

  -- ---- first time: create it
  IF NOT has_task THEN
    INSERT INTO tasks (title, subject_type, subject_id, studio_id, assigned_to,
                       due_date, source, event_booking_id)
    VALUES (ttl, 'teacher', NEW.teacher_id, ev.studio_id, NULL,
            due, 'system', NEW.id)
    RETURNING id INTO new_id;
    INSERT INTO task_notes (task_id, note_text) VALUES (new_id, details);
    RETURN NULL;
  END IF;

  -- ---- asked for again after being dropped: reopen
  IF t.status = 'cancelled' THEN
    UPDATE tasks
       SET status = 'open', completed_at = NULL, completed_by = NULL,
           title = ttl, subject_id = NEW.teacher_id, studio_id = ev.studio_id, due_date = due
     WHERE id = t.id;
    INSERT INTO task_notes (task_id, note_text)
      VALUES (t.id, 'Reopened: the backing track was requested again.' || E'\n' || details);
    RETURN NULL;
  END IF;

  -- ---- still wanted: carry across anything that changed
  IF TG_OP = 'UPDATE' AND
     (NEW.piece, NEW.instrument, NEW.notes, NEW.teacher_id)
       IS DISTINCT FROM (OLD.piece, OLD.instrument, OLD.notes, OLD.teacher_id) THEN

    IF t.status = 'open' THEN
      UPDATE tasks
         SET title = ttl, subject_id = NEW.teacher_id, studio_id = ev.studio_id
       WHERE id = t.id;
      INSERT INTO task_notes (task_id, note_text)
        VALUES (t.id, 'The booking was updated.' || E'\n' || details);

    ELSIF t.status = 'done' THEN
      -- A new piece or a new teacher means the finished track no
      -- longer fits; a changed note alone only gets mentioned.
      IF (NEW.piece, NEW.teacher_id) IS DISTINCT FROM (OLD.piece, OLD.teacher_id) THEN
        UPDATE tasks
           SET status = 'open', completed_at = NULL, completed_by = NULL,
               title = ttl, subject_id = NEW.teacher_id, studio_id = ev.studio_id
         WHERE id = t.id;
        INSERT INTO task_notes (task_id, note_text)
          VALUES (t.id, 'Reopened: the piece or teacher changed after this was completed.' || E'\n' || details);
      ELSE
        INSERT INTO task_notes (task_id, note_text)
          VALUES (t.id, 'The booking notes were updated.' || E'\n' || details);
      END IF;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;


-- ============================================================
-- STEP 4 — attach it
-- ============================================================
DROP TRIGGER IF EXISTS event_bookings_backing_task_trg ON event_bookings;

CREATE TRIGGER event_bookings_backing_task_trg
  AFTER INSERT OR UPDATE ON event_bookings
  FOR EACH ROW EXECUTE FUNCTION _event_backing_task_trg();


-- ============================================================
-- STEP 5 — if the event is moved to another date, move the open
-- backing-track tasks with it. Only tasks still on the date the
-- rules gave them are touched, so an admin's manual change stands.
-- ============================================================
CREATE OR REPLACE FUNCTION _event_backing_task_redate_trg()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today date := (now() AT TIME ZONE 'Australia/Melbourne')::date;
BEGIN
  IF NEW.event_date IS DISTINCT FROM OLD.event_date THEN
    UPDATE tasks t
       SET due_date = greatest(NEW.event_date - 14, today)
     WHERE t.status = 'open'
       AND t.event_booking_id IN (SELECT id FROM event_bookings WHERE event_id = NEW.id)
       AND (t.due_date = OLD.event_date - 14
            OR t.due_date = (t.created_at AT TIME ZONE 'Australia/Melbourne')::date);
  END IF;
  RETURN NULL;
END;
$$;


DROP TRIGGER IF EXISTS events_backing_task_redate_trg ON events;

CREATE TRIGGER events_backing_task_redate_trg
  AFTER UPDATE OF event_date ON events
  FOR EACH ROW EXECUTE FUNCTION _event_backing_task_redate_trg();


-- ============================================================
-- STEP 6 — get_event_grid(): teachers see only their own.
--
--   admin    → every field of every performance (unchanged)
--   student  → own family in full, others masked (unchanged)
--   teacher  → ONLY performances by their students, or that they
--              accompany. Others are not returned at all.
--
--   "their students" = the teacher is on the booking, or teaches the
--   student (student_teachers, or an active lesson series).
--   accompany = true when the student chose "My teacher" and that
--   teacher is this one.
--   own = the teacher's student (highlight);  accompany = the stronger
--   highlight for the ones they play for.
-- ============================================================
CREATE OR REPLACE FUNCTION get_event_grid(p_event uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ev   events%ROWTYPE;
  r    text := get_my_role();
  tid  uuid := get_my_teacher_id();
BEGIN
  SELECT * INTO ev FROM events WHERE id = p_event;
  IF NOT FOUND OR NOT _event_visible(ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;

  RETURN jsonb_build_object(
    'event', _event_json(ev),
    'role',  r,
    'fetched_at', now(),
    'bookings', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', q.id, 'block', q.assigned_block, 'position', q.assigned_position,
          'student_id', q.student_id,
          'student_name', CASE WHEN q.detail THEN q.full_name ELSE q.short_name END,
          'instrument', q.instrument, 'piece', q.piece,
          'accompaniment', q.accompaniment,
          'own', q.own, 'detail', q.detail,
          'accompany', q.accompany,
          'accompanist_name', CASE WHEN q.detail THEN q.accompanist_name END,
          'teacher_id',       CASE WHEN q.detail THEN q.teacher_id END,
          'teacher_name',     CASE WHEN q.detail THEN q.teacher_label END,
          'notes',            CASE WHEN q.detail THEN q.notes END,
          'preferred_blocks', CASE WHEN q.detail THEN to_jsonb(q.preferred_blocks) END,
          'created_at',       CASE WHEN q.detail THEN q.created_at END
        ) ORDER BY q.assigned_block, q.assigned_position)
      FROM (
        SELECT b.*,
               btrim(f.fn || ' ' || f.ln) AS full_name,
               btrim(f.fn || ' ' || CASE WHEN f.ln <> '' THEN left(f.ln, 1) || '.' ELSE '' END) AS short_name,
               coalesce(nullif(btrim(tp.first_name || ' ' || tp.last_name), ''), b.teacher_name) AS teacher_label,
               (r IN ('superuser','admin')
                OR s.user_id = auth.uid()
                OR tm.t_mine) AS detail,
               (CASE WHEN r IN ('superuser','admin') THEN false
                     WHEN r = 'teacher' THEN tm.t_mine
                     ELSE s.user_id = auth.uid() END) AS own,
               tm.t_acc AS accompany
          FROM event_bookings b
          JOIN students s ON s.id = b.student_id
          LEFT JOIN profiles sp ON sp.id = s.user_id
          LEFT JOIN teachers t  ON t.id = b.teacher_id
          LEFT JOIN profiles tp ON tp.id = t.user_id
          CROSS JOIN LATERAL (SELECT coalesce(nullif(btrim(s.first_name),''), sp.first_name, '') AS fn,
                                     coalesce(nullif(btrim(s.last_name),''),  sp.last_name,  '') AS ln) f
          CROSS JOIN LATERAL (
            SELECT
              (r = 'teacher' AND tid IS NOT NULL AND (
                 b.teacher_id = tid
                 OR EXISTS (SELECT 1 FROM _event_student_teachers(b.student_id) x
                             WHERE x.teacher_id = tid))) AS t_mine,
              (r = 'teacher' AND tid IS NOT NULL
                 AND b.accompaniment = 'teacher' AND b.teacher_id = tid) AS t_acc
          ) tm
         WHERE b.event_id = p_event AND b.status = 'booked'
           AND (r <> 'teacher' OR tm.t_mine OR tm.t_acc)
      ) q), '[]'::jsonb)
  );
END;
$$;


-- ============================================================
-- STEP 7 — get_event_teacher_summary(event)
-- The numbers behind the summary card on a teacher's event page.
-- Teachers only (it describes the caller's own students).
--   students_performing   distinct students of this teacher performing
--   accompany_students    distinct students who chose this teacher to
--                         accompany them
--   backing_tracks        performances this teacher must prepare a
--                         track for, with the student's notes and the
--                         task's status / due date
-- ============================================================
CREATE OR REPLACE FUNCTION get_event_teacher_summary(p_event uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ev   events%ROWTYPE;
  tid  uuid := get_my_teacher_id();
  res  jsonb;
BEGIN
  IF get_my_role() <> 'teacher' OR tid IS NULL THEN RAISE EXCEPTION 'not_allowed'; END IF;
  SELECT * INTO ev FROM events WHERE id = p_event;
  IF NOT FOUND OR NOT _event_visible(ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;

  WITH bk AS (
    SELECT b.id, b.student_id, b.instrument, b.piece, b.accompaniment, b.notes,
           b.assigned_block AS blk, b.assigned_position AS pos,
           btrim(f.fn || ' ' || f.ln) AS sname,
           (b.teacher_id = tid
            OR EXISTS (SELECT 1 FROM _event_student_teachers(b.student_id) x
                        WHERE x.teacher_id = tid))                       AS mine,
           (b.accompaniment = 'teacher'       AND b.teacher_id = tid)    AS acc,
           (b.accompaniment = 'backing_track' AND b.teacher_id = tid)    AS bt
      FROM event_bookings b
      JOIN students s ON s.id = b.student_id
      LEFT JOIN profiles sp ON sp.id = s.user_id
      CROSS JOIN LATERAL (SELECT coalesce(nullif(btrim(s.first_name),''), sp.first_name, '') AS fn,
                                 coalesce(nullif(btrim(s.last_name),''),  sp.last_name,  '') AS ln) f
     WHERE b.event_id = p_event AND b.status = 'booked'
  )
  SELECT jsonb_build_object(
    'students_performing',    (SELECT count(DISTINCT student_id) FROM bk WHERE mine OR acc),
    'performances',           (SELECT count(*)                   FROM bk WHERE mine OR acc),
    'accompany_students',     (SELECT count(DISTINCT student_id) FROM bk WHERE acc),
    'accompany_performances', (SELECT count(*)                   FROM bk WHERE acc),
    'accompany', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
                 'student_name', sname, 'piece', piece, 'instrument', instrument,
                 'block', blk, 'position', pos) ORDER BY blk, pos)
          FROM bk WHERE acc), '[]'::jsonb),
    'backing_tracks', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
                 'booking_id', bk.id, 'student_name', bk.sname, 'piece', bk.piece,
                 'instrument', bk.instrument, 'notes', bk.notes,
                 'block', bk.blk, 'position', bk.pos,
                 'task_status', t.status, 'due_date', t.due_date) ORDER BY bk.blk, bk.pos)
          FROM bk LEFT JOIN tasks t ON t.event_booking_id = bk.id
         WHERE bk.bt), '[]'::jsonb)
  ) INTO res;

  RETURN res;
END;
$$;


-- ============================================================
-- STEP 8 — who may call what
-- ============================================================
REVOKE ALL ON FUNCTION _event_backing_task_trg()         FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION _event_backing_task_redate_trg()  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION get_event_teacher_summary(uuid)   FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION get_event_teacher_summary(uuid) TO authenticated;

REVOKE ALL ON FUNCTION get_event_grid(uuid)              FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION get_event_grid(uuid)           TO authenticated;


-- ============================================================
-- STEP 9 — tasks for performances ALREADY booked with a backing
-- track (no-op updates fire the trigger). Safe to run twice: a
-- booking that already has its task is left alone.
-- ============================================================
UPDATE event_bookings
   SET accompaniment = accompaniment
 WHERE status = 'booked' AND accompaniment = 'backing_track' AND teacher_id IS NOT NULL;


-- STEP 10 — tell PostgREST about the new column
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY (optional)
-- ============================================================
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'tasks' AND column_name = 'event_booking_id';            -- 1 row
-- SELECT tgname FROM pg_trigger WHERE tgname IN
--   ('event_bookings_backing_task_trg','events_backing_task_redate_trg');       -- 2 rows
-- SELECT title, status, due_date FROM tasks WHERE event_booking_id IS NOT NULL;  -- the backfilled tasks

-- ------------------------------------------------------------
-- TO REVERSE:
-- DROP TRIGGER IF EXISTS event_bookings_backing_task_trg ON event_bookings;
-- DROP TRIGGER IF EXISTS events_backing_task_redate_trg ON events;
-- DROP FUNCTION IF EXISTS _event_backing_task_trg();
-- DROP FUNCTION IF EXISTS _event_backing_task_redate_trg();
-- DROP FUNCTION IF EXISTS get_event_teacher_summary(uuid);
-- (get_event_grid: re-run events.sql STEP 11 to restore the old version)
-- ------------------------------------------------------------
