-- ============================================================
-- Band (group) performances for events (migration #46)
--
-- Until now a band was just several students each booking the
-- instrument "Band" on their own: separate slots, nothing linking
-- them, and no member could see the others. This adds:
--
--   1. event_bookings.band_name + event_booking_members — ONE booking
--      (one slot in the running order) with a list of member students.
--      booking.student_id stays the "lead" and is also a member.
--   2. combine_event_bookings() — admin tool: turns a booking into a
--      band booking, adds the members, and CANCELS the other members'
--      individual "Band" bookings for that event (freeing their slots).
--      Run it again on the same booking to change the members.
--   3. dissolve_event_band() — undo: back to the lead's solo booking.
--   4. get_event_grid() — a band booking is "own" (and shows full
--      detail) to EVERY member's family, and to every member's teacher;
--      other students see only the band name. Members' names go to
--      members, admins and teachers only.
--   5. list_events_for_me() — my_count counts bands I am a member of.
--   6. get_event_teacher_summary() — counts a band for each member's
--      teacher and names it by its band name.
--   7. A guard trigger — only admins may change or cancel a band
--      booking, and a member cannot book a second solo "Band"
--      performance for the same event.
--
-- Run each numbered STEP ONE STATEMENT AT A TIME in the Supabase SQL
-- editor, and run it BEFORE deploying the new events.html /
-- events-common.js / event-book.html / dashboard-student.html.
-- Safe to re-run.
--
-- Needs: events.sql, events-per-instrument.sql, events-teachers.sql.
-- ============================================================


-- ============================================================
-- STEP 1 — the band's name, on the booking
-- ============================================================
ALTER TABLE event_bookings
  ADD COLUMN IF NOT EXISTS band_name text
    CHECK (band_name IS NULL OR char_length(btrim(band_name)) BETWEEN 1 AND 80);


-- ============================================================
-- STEP 2 — who is in the band (the lead is a member too)
-- ============================================================
CREATE TABLE IF NOT EXISTS event_booking_members (
  booking_id uuid NOT NULL REFERENCES event_bookings(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES students(id),
  PRIMARY KEY (booking_id, student_id)
);


-- ============================================================
-- STEP 3 — index + row-level security. Like event_bookings, the
-- table is read-only to admins and written only by the functions
-- below; students and teachers reach it only through get_event_grid.
-- ============================================================
CREATE INDEX IF NOT EXISTS event_booking_members_student_idx ON event_booking_members (student_id);


ALTER TABLE event_booking_members ENABLE ROW LEVEL SECURITY;


DROP POLICY IF EXISTS "event_booking_members_admin_read" ON event_booking_members;


CREATE POLICY "event_booking_members_admin_read" ON event_booking_members FOR SELECT TO authenticated
  USING (get_my_role() IN ('superuser','admin'));


-- ============================================================
-- STEP 4 — combine_event_bookings(booking, members, band name, piece)
-- Admin only. p_booking is the booking whose SLOT the band keeps;
-- its student becomes the lead. p_members are the other members
-- (the lead is added automatically). Every other member's
-- individual "Band" booking for this event is cancelled. A member
-- already in a DIFFERENT band booking for this event is refused.
-- Returns {booking_id, members, cancelled}.
-- ============================================================
CREATE OR REPLACE FUNCTION combine_event_bookings(
  p_booking   uuid,
  p_members   uuid[],
  p_band_name text,
  p_piece     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bk       event_bookings%ROWTYPE;
  ev       events%ROWTYPE;
  v_name   text := btrim(coalesce(p_band_name, ''));
  v_piece  text := nullif(btrim(coalesce(p_piece, '')), '');
  ids      uuid[];
  sid      uuid;
  st       students%ROWTYPE;
  nm       text;
  n_cancel integer := 0;
BEGIN
  IF auth.uid() IS NULL OR get_my_role() NOT IN ('superuser','admin') THEN
    RAISE EXCEPTION 'not_allowed';
  END IF;
  IF v_name = '' OR char_length(v_name) > 80
     OR (v_piece IS NOT NULL AND char_length(v_piece) > 120) THEN
    RAISE EXCEPTION 'bad_input';
  END IF;

  SELECT * INTO bk FROM event_bookings WHERE id = p_booking AND status = 'booked';
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  SELECT * INTO ev FROM events WHERE id = bk.event_id FOR UPDATE;
  IF NOT _event_visible(ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;

  -- The lead first, then the others, without duplicates
  ids := ARRAY[bk.student_id] ||
         ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_members, ARRAY[]::uuid[])) x
                WHERE x IS NOT NULL AND x <> bk.student_id);
  IF cardinality(ids) < 2 OR cardinality(ids) > 12 THEN RAISE EXCEPTION 'band_members'; END IF;

  -- Each member is checked on their own, and a refusal NAMES the student
  -- (the page shows it), so "you don't have access" is never a mystery.
  FOREACH sid IN ARRAY ids LOOP
    SELECT * INTO st FROM students WHERE id = sid;
    nm := coalesce(nullif(btrim(coalesce(st.first_name, '') || ' ' || coalesce(st.last_name, '')), ''),
                   (SELECT btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))
                      FROM profiles p WHERE p.id = st.user_id),
                   'A student');
    IF NOT FOUND OR st.status NOT IN ('active','trial') THEN
      RAISE EXCEPTION 'member_inactive: %', nm;
    END IF;
    IF ev.studio_id IS NOT NULL AND st.studio_id IS NOT NULL AND st.studio_id <> ev.studio_id THEN
      RAISE EXCEPTION 'member_studio: %', nm;
    END IF;
    IF NOT _event_student_ok(sid, ev) THEN
      RAISE EXCEPTION 'member_studio: %', nm;
    END IF;
    IF EXISTS (SELECT 1
                 FROM event_booking_members m
                 JOIN event_bookings b ON b.id = m.booking_id
                WHERE m.student_id = sid AND b.event_id = bk.event_id
                  AND b.status = 'booked' AND b.id <> p_booking) THEN
      RAISE EXCEPTION 'already_in_band: %', nm;
    END IF;
  END LOOP;

  -- Members' own individual Band bookings are replaced by this one
  WITH gone AS (
    UPDATE event_bookings x
       SET status = 'cancelled', cancelled_at = now(), updated_at = now()
     WHERE x.event_id = bk.event_id AND x.status = 'booked'
       AND x.id <> p_booking AND x.band_name IS NULL
       AND x.student_id = ANY(ids)
       AND lower(btrim(x.instrument)) = 'band'
    RETURNING x.id)
  SELECT count(*) INTO n_cancel FROM gone;

  DELETE FROM event_booking_members WHERE booking_id = p_booking;
  INSERT INTO event_booking_members (booking_id, student_id)
    SELECT p_booking, x FROM unnest(ids) x;

  UPDATE event_bookings
     SET band_name = v_name, instrument = 'Band',
         piece = coalesce(v_piece, piece), updated_at = now()
   WHERE id = p_booking;

  RETURN jsonb_build_object('booking_id', p_booking, 'members', cardinality(ids), 'cancelled', n_cancel);
END;
$$;


-- ============================================================
-- STEP 5 — dissolve_event_band(booking)
-- Admin only. The booking goes back to being the lead's solo
-- performance; the members list is cleared. (The other members'
-- cancelled bookings are NOT brought back — they can book again.)
-- ============================================================
CREATE OR REPLACE FUNCTION dissolve_event_band(p_booking uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bk event_bookings%ROWTYPE;
  ev events%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR get_my_role() NOT IN ('superuser','admin') THEN
    RAISE EXCEPTION 'not_allowed';
  END IF;
  SELECT * INTO bk FROM event_bookings WHERE id = p_booking AND status = 'booked';
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  SELECT * INTO ev FROM events WHERE id = bk.event_id FOR UPDATE;
  IF NOT _event_visible(ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;

  DELETE FROM event_booking_members WHERE booking_id = p_booking;
  UPDATE event_bookings SET band_name = NULL, updated_at = now() WHERE id = p_booking;
  RETURN jsonb_build_object('booking_id', p_booking, 'dissolved', true);
END;
$$;


-- ============================================================
-- STEP 6 — guard: families cannot change or cancel a band booking
-- (admins and the SQL editor can), and a member cannot book a second
-- solo "Band" performance for the same event.
-- ============================================================
CREATE OR REPLACE FUNCTION _event_band_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR get_my_role() IN ('superuser','admin') THEN RETURN NEW; END IF;

  IF TG_OP = 'UPDATE' AND OLD.band_name IS NOT NULL THEN
    RAISE EXCEPTION 'band_locked';
  END IF;

  IF NEW.band_name IS NULL AND NEW.status = 'booked'
     AND lower(btrim(NEW.instrument)) = 'band'
     AND EXISTS (SELECT 1
                   FROM event_booking_members m
                   JOIN event_bookings b ON b.id = m.booking_id
                  WHERE m.student_id = NEW.student_id AND b.event_id = NEW.event_id
                    AND b.status = 'booked' AND b.id IS DISTINCT FROM NEW.id) THEN
    RAISE EXCEPTION 'instrument_booked';
  END IF;
  RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS event_bookings_band_guard_trg ON event_bookings;


CREATE TRIGGER event_bookings_band_guard_trg
  BEFORE INSERT OR UPDATE ON event_bookings
  FOR EACH ROW EXECUTE FUNCTION _event_band_guard();


-- ============================================================
-- STEP 7 — get_event_grid(): bands.
--
--   Everything from events-teachers.sql is kept. New, per booking:
--     band_name     the band's name (null for a solo performance)
--     member_count  how many students are in the band
--     members       [{student_id, name}] — only where `detail` is true
--                   (the band's own families, their teachers, admins)
--   student_name is the band name for a band, to everyone.
--   A band is `own` / `detail` for every member's family, and a
--   teacher sees it if they teach ANY member.
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
          'student_name', coalesce(q.band_name, CASE WHEN q.detail THEN q.full_name ELSE q.short_name END),
          'band_name', q.band_name,
          'member_count', CASE WHEN q.band_name IS NOT NULL THEN jsonb_array_length(q.members) END,
          'members', CASE WHEN q.band_name IS NOT NULL AND q.detail THEN q.members END,
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
               bm.members,
               (r IN ('superuser','admin')
                OR s.user_id = auth.uid()
                OR bm.mine
                OR tm.t_mine) AS detail,
               (CASE WHEN r IN ('superuser','admin') THEN false
                     WHEN r = 'teacher' THEN tm.t_mine
                     ELSE (s.user_id = auth.uid() OR bm.mine) END) AS own,
               tm.t_acc AS accompany
          FROM event_bookings b
          JOIN students s ON s.id = b.student_id
          LEFT JOIN profiles sp ON sp.id = s.user_id
          LEFT JOIN teachers t  ON t.id = b.teacher_id
          LEFT JOIN profiles tp ON tp.id = t.user_id
          CROSS JOIN LATERAL (SELECT coalesce(nullif(btrim(s.first_name),''), sp.first_name, '') AS fn,
                                     coalesce(nullif(btrim(s.last_name),''),  sp.last_name,  '') AS ln) f
          CROSS JOIN LATERAL (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'student_id', ms.id,
                     'name', btrim(coalesce(nullif(btrim(ms.first_name),''), mp.first_name, '') || ' ' ||
                                   coalesce(nullif(btrim(ms.last_name),''),  mp.last_name,  '')))
                   ORDER BY (ms.id = b.student_id) DESC, ms.first_name), '[]'::jsonb) AS members,
                   coalesce(bool_or(ms.user_id = auth.uid()), false) AS mine
              FROM event_booking_members m
              JOIN students ms ON ms.id = m.student_id
              LEFT JOIN profiles mp ON mp.id = ms.user_id
             WHERE m.booking_id = b.id
          ) bm
          CROSS JOIN LATERAL (
            SELECT
              (r = 'teacher' AND tid IS NOT NULL AND (
                 b.teacher_id = tid
                 OR EXISTS (SELECT 1 FROM _event_student_teachers(b.student_id) x
                             WHERE x.teacher_id = tid)
                 OR EXISTS (SELECT 1 FROM event_booking_members m2
                             WHERE m2.booking_id = b.id
                               AND EXISTS (SELECT 1 FROM _event_student_teachers(m2.student_id) x2
                                            WHERE x2.teacher_id = tid)))) AS t_mine,
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
-- STEP 8 — list_events_for_me(): my_count includes bands I am in
-- ============================================================
CREATE OR REPLACE FUNCTION list_events_for_me()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(
           _event_json(e) || jsonb_build_object('my_count',
             (SELECT count(*) FROM event_bookings b
               WHERE b.event_id = e.id AND b.status = 'booked'
                 AND (EXISTS (SELECT 1 FROM students s
                               WHERE s.id = b.student_id AND s.user_id = auth.uid())
                      OR EXISTS (SELECT 1 FROM event_booking_members m
                                   JOIN students ms ON ms.id = m.student_id
                                  WHERE m.booking_id = b.id AND ms.user_id = auth.uid()))))
           ORDER BY e.event_date, e.start_time, e.name), '[]'::jsonb)
    FROM events e
   WHERE auth.uid() IS NOT NULL AND _event_visible(e);
$$;


-- ============================================================
-- STEP 9 — get_event_teacher_summary(): bands count for each
-- member's teacher, and are listed by band name.
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
           coalesce(b.band_name, btrim(f.fn || ' ' || f.ln)) AS sname,
           (b.teacher_id = tid
            OR EXISTS (SELECT 1 FROM _event_student_teachers(b.student_id) x
                        WHERE x.teacher_id = tid)
            OR EXISTS (SELECT 1 FROM event_booking_members m2
                        WHERE m2.booking_id = b.id
                          AND EXISTS (SELECT 1 FROM _event_student_teachers(m2.student_id) x2
                                       WHERE x2.teacher_id = tid)))          AS mine,
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
-- STEP 10 — who may call what
-- ============================================================
REVOKE ALL ON FUNCTION _event_band_guard()                 FROM PUBLIC, anon, authenticated;


REVOKE ALL ON FUNCTION combine_event_bookings(uuid, uuid[], text, text) FROM PUBLIC, anon;


GRANT EXECUTE ON FUNCTION combine_event_bookings(uuid, uuid[], text, text) TO authenticated;


REVOKE ALL ON FUNCTION dissolve_event_band(uuid)           FROM PUBLIC, anon;


GRANT EXECUTE ON FUNCTION dissolve_event_band(uuid)        TO authenticated;


REVOKE ALL ON FUNCTION get_event_grid(uuid)                FROM PUBLIC, anon;


GRANT EXECUTE ON FUNCTION get_event_grid(uuid)             TO authenticated;


REVOKE ALL ON FUNCTION list_events_for_me()                FROM PUBLIC, anon;


GRANT EXECUTE ON FUNCTION list_events_for_me()             TO authenticated;


REVOKE ALL ON FUNCTION get_event_teacher_summary(uuid)     FROM PUBLIC, anon;


GRANT EXECUTE ON FUNCTION get_event_teacher_summary(uuid)  TO authenticated;


-- ============================================================
-- ROLLBACK (only if needed). Re-run the get_event_grid() from
-- events-teachers.sql STEP 6, list_events_for_me() from events.sql
-- STEP 8 and get_event_teacher_summary() from events-teachers.sql
-- STEP 7, then:
--   DROP TRIGGER IF EXISTS event_bookings_band_guard_trg ON event_bookings;
--   DROP FUNCTION IF EXISTS _event_band_guard();
--   DROP FUNCTION IF EXISTS combine_event_bookings(uuid, uuid[], text, text);
--   DROP FUNCTION IF EXISTS dissolve_event_band(uuid);
--   DROP TABLE IF EXISTS event_booking_members;
--   ALTER TABLE event_bookings DROP COLUMN IF EXISTS band_name;
-- ============================================================
