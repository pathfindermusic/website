-- ============================================================
-- Events for teachers, fix 1 (migration #46)
--
-- Backing-track tasks were created with no studio and nobody
-- assigned, so (a) the admin Tasks page, which opens on the
-- admin's own studio, did not list them and (b) the task showed
-- blank "Studio" / "Assigned to".
--
-- From now on a backing-track task gets
--   studio      = the event's studio; if the event is for all
--                 studios, the student's studio; failing that the
--                 teacher's first studio
--   assigned to = an admin of that studio (one who is set up for
--                 exactly that studio is preferred over an admin
--                 who covers every studio; oldest first). If the
--                 studio has no admin the task stays in the
--                 studio queue, which its admins can all see.
--
-- ⚠ RUN ONE STATEMENT AT A TIME in the Supabase SQL editor
--   (SQL first, THEN deploy the matching pages).
-- ============================================================


-- ------------------------------------------------------------
-- STEP 1 — who owns the task for a given booking
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _event_backing_task_owner(p_event_studio uuid, p_student uuid, p_teacher uuid)
RETURNS TABLE (studio_id uuid, admin_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  st uuid;
  ad uuid;
BEGIN
  st := coalesce(
    p_event_studio,
    (SELECT s.studio_id FROM students s WHERE s.id = p_student),
    (SELECT t.studio_ids[1] FROM teachers t WHERE t.id = p_teacher)
  );

  IF st IS NOT NULL THEN
    SELECT a.user_id INTO ad
      FROM admins a
      JOIN profiles p ON p.id = a.user_id AND p.status = 'active'
     WHERE st = ANY(a.studio_ids) OR cardinality(a.studio_ids) = 0
     ORDER BY (st = ANY(a.studio_ids)) DESC, a.created_at, a.user_id
     LIMIT 1;
  END IF;

  RETURN QUERY SELECT st, ad;
END;
$$;


-- ------------------------------------------------------------
-- STEP 2 — the booking trigger function, now filling those in
-- ------------------------------------------------------------
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
  own_studio uuid;
  own_admin  uuid;
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
  SELECT o.studio_id, o.admin_id INTO own_studio, own_admin
    FROM _event_backing_task_owner(ev.studio_id, NEW.student_id, NEW.teacher_id) o;
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
    VALUES (ttl, 'teacher', NEW.teacher_id, own_studio, own_admin,
            due, 'system', NEW.id)
    RETURNING id INTO new_id;
    INSERT INTO task_notes (task_id, note_text) VALUES (new_id, details);
    RETURN NULL;
  END IF;

  -- ---- asked for again after being dropped: reopen
  IF t.status = 'cancelled' THEN
    UPDATE tasks
       SET status = 'open', completed_at = NULL, completed_by = NULL,
           title = ttl, subject_id = NEW.teacher_id, due_date = due,
           studio_id = coalesce(t.studio_id, own_studio),
           assigned_to = coalesce(t.assigned_to, own_admin)
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
         SET title = ttl, subject_id = NEW.teacher_id, studio_id = coalesce(t.studio_id, own_studio)
       WHERE id = t.id;
      INSERT INTO task_notes (task_id, note_text)
        VALUES (t.id, 'The booking was updated.' || E'\n' || details);

    ELSIF t.status = 'done' THEN
      -- A new piece or a new teacher means the finished track no
      -- longer fits; a changed note alone only gets mentioned.
      IF (NEW.piece, NEW.teacher_id) IS DISTINCT FROM (OLD.piece, OLD.teacher_id) THEN
        UPDATE tasks
           SET status = 'open', completed_at = NULL, completed_by = NULL,
               title = ttl, subject_id = NEW.teacher_id, studio_id = coalesce(t.studio_id, own_studio)
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


-- ------------------------------------------------------------
-- STEP 3 — lock the helpers down (internal only)
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION _event_backing_task_owner(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;


-- ------------------------------------------------------------
-- STEP 4 — repair the tasks already created. Only blanks are
-- filled: a studio someone has set is kept (and its admin is the
-- one chosen), and an assignee someone has set is kept. Every
-- backing-track task was created unassigned, so an unassigned one
-- is simply waiting for this.
-- ------------------------------------------------------------
WITH todo AS (
  SELECT t.id, o.studio_id AS new_studio, o.admin_id AS new_admin
    FROM tasks t
    JOIN event_bookings b ON b.id = t.event_booking_id
    JOIN events e         ON e.id = b.event_id
   CROSS JOIN LATERAL _event_backing_task_owner(coalesce(t.studio_id, e.studio_id), b.student_id, t.subject_id) o
   WHERE t.source = 'system'
     AND (t.studio_id IS NULL OR (t.assigned_to IS NULL AND t.status = 'open'))
)
UPDATE tasks t
   SET studio_id   = coalesce(t.studio_id, todo.new_studio),
       assigned_to = coalesce(t.assigned_to, CASE WHEN t.status = 'open' THEN todo.new_admin END)
  FROM todo
 WHERE t.id = todo.id;


-- ------------------------------------------------------------
-- STEP 5
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
