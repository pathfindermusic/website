-- ============================================================
-- PATHFINDER PORTAL — Events (e.g. the year-end students' concert)
--
-- An EVENT has a date, a start and end time, a venue, a block length
-- (default 60 min) and a number of performance slots per block
-- (default 12). Students book a performance by naming up to three
-- preferred BLOCKS; the system gives them the first preferred block
-- that still has room (lowest free slot number in that block).
--
--   events          one row per event          (admins only, via RLS)
--   event_bookings  one row per performance    (admins read; ALL
--                                               writes go through the
--                                               functions below)
--
-- Everything students and teachers see or do goes through
-- SECURITY DEFINER functions, so:
--   * capacity is enforced in the database (no double-booking, even
--     when two families press Submit at the same moment — the event
--     row is locked while a booking is placed);
--   * other students' details are masked on the server (first name +
--     last initial only; the teacher and comments stay private to the
--     student's family, the teacher and admins).
--
-- Block i runs from  start_time + (i-1) × block_minutes. The number of
-- blocks is  ceil((end_time - start_time) / block_minutes).
--
-- ⚠ Run ONE STATEMENT AT A TIME, in order, and check each result.
-- ⚠ Run ALL of these BEFORE deploying events.html / event-book.html /
--   the updated dashboard-student.html.
-- ⚠ Needs: get_my_role(), get_my_studio_ids(), get_my_teacher_id()
--   (all from earlier migrations).
-- ============================================================


-- ============================================================
-- STEP 1 — events table
-- ============================================================
CREATE TABLE IF NOT EXISTS events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  studio_id        uuid REFERENCES studios(id),            -- NULL = all studios
  name             text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
  description      text CHECK (description IS NULL OR char_length(description) <= 1000),
  event_date       date NOT NULL,
  start_time       time NOT NULL,                          -- local wall-clock time
  end_time         time NOT NULL,
  venue_name       text CHECK (venue_name IS NULL OR char_length(venue_name) <= 150),
  venue_address    text CHECK (venue_address IS NULL OR char_length(venue_address) <= 300),
  block_minutes    integer NOT NULL DEFAULT 60  CHECK (block_minutes BETWEEN 10 AND 480),
  slots_per_block  integer NOT NULL DEFAULT 12  CHECK (slots_per_block BETWEEN 1 AND 60),
  max_per_student  integer NOT NULL DEFAULT 5   CHECK (max_per_student BETWEEN 1 AND 10),
  booking_deadline date,                                   -- last day students may book/change
  status           text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','open','closed')),
  created_by       uuid DEFAULT auth.uid(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT events_end_after_start CHECK (end_time > start_time)
);


-- ============================================================
-- STEP 2 — event_bookings table
--   accompaniment: teacher | peer | backing_track | none
--   assigned_position 1000 is reserved as a temporary parking slot
--   used while two performances swap places.
-- ============================================================
CREATE TABLE IF NOT EXISTS event_bookings (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id          uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  student_id        uuid NOT NULL REFERENCES students(id),
  instrument        text NOT NULL CHECK (char_length(btrim(instrument)) BETWEEN 1 AND 60),
  teacher_id        uuid REFERENCES teachers(id),
  teacher_name      text CHECK (teacher_name IS NULL OR char_length(teacher_name) <= 80),
  piece             text NOT NULL CHECK (char_length(btrim(piece)) BETWEEN 1 AND 120),
  accompaniment     text NOT NULL DEFAULT 'none'
                    CHECK (accompaniment IN ('teacher','peer','backing_track','none')),
  accompanist_name  text CHECK (accompanist_name IS NULL OR char_length(accompanist_name) <= 80),
  preferred_blocks  integer[] NOT NULL
                    CHECK (cardinality(preferred_blocks) BETWEEN 1 AND 3),
  assigned_block    integer NOT NULL CHECK (assigned_block >= 1),
  assigned_position integer NOT NULL CHECK (assigned_position BETWEEN 1 AND 1000),
  notes             text CHECK (notes IS NULL OR char_length(notes) <= 500),
  status            text NOT NULL DEFAULT 'booked' CHECK (status IN ('booked','cancelled')),
  booked_by         uuid DEFAULT auth.uid(),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  cancelled_at      timestamptz
);


-- ============================================================
-- STEP 3 — indexes. The unique index is the last line of defence
-- against two performances in one slot (cancelled rows don't count).
-- ============================================================
CREATE UNIQUE INDEX IF NOT EXISTS event_bookings_one_per_slot
  ON event_bookings (event_id, assigned_block, assigned_position)
  WHERE status = 'booked';

CREATE INDEX IF NOT EXISTS event_bookings_event_idx   ON event_bookings (event_id) WHERE status = 'booked';

CREATE INDEX IF NOT EXISTS event_bookings_student_idx ON event_bookings (student_id);

CREATE INDEX IF NOT EXISTS events_date_idx            ON events (event_date);


-- ============================================================
-- STEP 4 — block-count helper (immutable, usable anywhere)
-- ============================================================
CREATE OR REPLACE FUNCTION event_block_count(p_start time, p_end time, p_minutes integer)
RETURNS integer
LANGUAGE sql IMMUTABLE
AS $$
  SELECT GREATEST(1, ceil(extract(epoch FROM (p_end - p_start)) / 60.0 / p_minutes)::integer);
$$;


-- ============================================================
-- STEP 5 — guard: an edit may not strand booked performances
-- outside the new layout (fewer blocks / fewer slots per block).
-- Move or cancel those performances first. Also stamps updated_at.
-- ============================================================
CREATE OR REPLACE FUNCTION events_guard_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  nb integer;
BEGIN
  NEW.updated_at := now();
  nb := event_block_count(NEW.start_time, NEW.end_time, NEW.block_minutes);
  IF EXISTS (
    SELECT 1 FROM event_bookings b
     WHERE b.event_id = NEW.id AND b.status = 'booked'
       AND (b.assigned_block > nb OR b.assigned_position > NEW.slots_per_block)
  ) THEN
    RAISE EXCEPTION 'layout_conflict: some booked performances sit outside the new blocks/slots. Move or cancel them first.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS events_guard_update_trg ON events;

CREATE TRIGGER events_guard_update_trg
  BEFORE UPDATE ON events
  FOR EACH ROW EXECUTE FUNCTION events_guard_update();


-- ============================================================
-- STEP 6 — row-level security.
-- Admins manage events within their studios (NULL studio = everyone).
-- Admins can READ bookings; they WRITE them only through the
-- functions (which enforce capacity).
-- Students and teachers get NO direct table access at all.
-- ============================================================
ALTER TABLE events         ENABLE ROW LEVEL SECURITY;

ALTER TABLE event_bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "events_admin_all" ON events;

CREATE POLICY "events_admin_all" ON events FOR ALL TO authenticated
  USING (
    get_my_role() = 'superuser'
    OR (get_my_role() = 'admin' AND (studio_id IS NULL OR studio_id = ANY(get_my_studio_ids())))
  )
  WITH CHECK (
    get_my_role() = 'superuser'
    OR (get_my_role() = 'admin' AND (studio_id IS NULL OR studio_id = ANY(get_my_studio_ids())))
  );

DROP POLICY IF EXISTS "event_bookings_admin_read" ON event_bookings;

CREATE POLICY "event_bookings_admin_read" ON event_bookings FOR SELECT TO authenticated
  USING (
    get_my_role() IN ('superuser','admin')
    AND EXISTS (
      SELECT 1 FROM events e
       WHERE e.id = event_bookings.event_id
         AND (get_my_role() = 'superuser' OR e.studio_id IS NULL OR e.studio_id = ANY(get_my_studio_ids()))
    )
  );


-- ============================================================
-- STEP 7 — internal helpers (not callable by the browser)
-- ============================================================

-- Can the caller see this event at all?
--   admins: their studios' events (any status)
--   teachers / students: open or closed events of their studio
CREATE OR REPLACE FUNCTION _event_visible(ev events)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r text := get_my_role();
BEGIN
  IF r = 'superuser' THEN RETURN true; END IF;
  IF r = 'admin' THEN
    RETURN ev.studio_id IS NULL OR ev.studio_id = ANY(get_my_studio_ids());
  END IF;
  IF ev.status NOT IN ('open','closed') THEN RETURN false; END IF;
  IF r = 'teacher' THEN
    RETURN ev.studio_id IS NULL OR EXISTS (
      SELECT 1 FROM teachers t
       WHERE t.user_id = auth.uid()
         AND (cardinality(t.studio_ids) = 0 OR ev.studio_id = ANY(t.studio_ids)));
  END IF;
  IF r = 'student' THEN
    RETURN ev.studio_id IS NULL OR EXISTS (
      SELECT 1 FROM students s
       WHERE s.user_id = auth.uid()
         AND (s.studio_id IS NULL OR s.studio_id = ev.studio_id));
  END IF;
  RETURN false;
END;
$$;

-- May the caller book / edit / cancel on behalf of this student?
--   admins: students in their studios
--   students: their own login's active or trial students
CREATE OR REPLACE FUNCTION _event_student_ok(p_student uuid, ev events)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r  text := get_my_role();
  st students%ROWTYPE;
BEGIN
  IF p_student IS NULL OR NOT _event_visible(ev) THEN RETURN false; END IF;
  SELECT * INTO st FROM students WHERE id = p_student;
  IF NOT FOUND THEN RETURN false; END IF;
  IF ev.studio_id IS NOT NULL AND st.studio_id IS NOT NULL AND st.studio_id <> ev.studio_id THEN
    RETURN false;
  END IF;
  IF r IN ('superuser','admin') THEN
    RETURN r = 'superuser' OR st.studio_id IS NULL OR st.studio_id = ANY(get_my_studio_ids());
  END IF;
  RETURN r = 'student' AND st.user_id = auth.uid() AND st.status IN ('active','trial');
END;
$$;

-- Students may only act while the event is open and before the deadline.
CREATE OR REPLACE FUNCTION _event_check_window(ev events)
RETURNS void
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
BEGIN
  IF get_my_role() IN ('superuser','admin') THEN RETURN; END IF;
  IF ev.status <> 'open' THEN RAISE EXCEPTION 'event_closed'; END IF;
  IF ev.booking_deadline IS NOT NULL
     AND ev.booking_deadline < (now() AT TIME ZONE 'Australia/Melbourne')::date THEN
    RAISE EXCEPTION 'deadline_passed';
  END IF;
END;
$$;

-- A student's teachers: the ones recorded on the student (student_teachers)
-- PLUS whoever teaches them in an active lesson series (private lessons
-- via lessons.student_id, group lessons via lesson_students). Many
-- students only have the lesson series, so student_teachers alone misses them.
CREATE OR REPLACE FUNCTION _event_student_teachers(p_student uuid)
RETURNS TABLE (teacher_id uuid, instrument text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT st.teacher_id, st.instrument FROM student_teachers st WHERE st.student_id = p_student
  UNION
  SELECT l.teacher_id, l.instrument
    FROM lessons l
   WHERE l.status = 'active'
     AND (l.student_id = p_student
          OR EXISTS (SELECT 1 FROM lesson_students ls WHERE ls.lesson_id = l.id AND ls.student_id = p_student));
$$;


-- The event as JSON, plus how many performances are booked.
CREATE OR REPLACE FUNCTION _event_json(ev events)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', ev.id, 'studio_id', ev.studio_id, 'name', ev.name,
    'description', ev.description, 'event_date', ev.event_date,
    'start_time', to_char(ev.start_time, 'HH24:MI'),
    'end_time',   to_char(ev.end_time,   'HH24:MI'),
    'venue_name', ev.venue_name, 'venue_address', ev.venue_address,
    'block_minutes', ev.block_minutes, 'slots_per_block', ev.slots_per_block,
    'max_per_student', ev.max_per_student, 'booking_deadline', ev.booking_deadline,
    'status', ev.status,
    'block_count', event_block_count(ev.start_time, ev.end_time, ev.block_minutes),
    'booked_count', (SELECT count(*) FROM event_bookings b
                      WHERE b.event_id = ev.id AND b.status = 'booked')
  );
$$;


-- ============================================================
-- STEP 8 — list_events_for_me()
-- Every event the caller may see, soonest first. For a student,
-- my_count = performances already booked by their family.
-- ============================================================
CREATE OR REPLACE FUNCTION list_events_for_me()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(
           _event_json(e) || jsonb_build_object('my_count',
             (SELECT count(*) FROM event_bookings b JOIN students s ON s.id = b.student_id
               WHERE b.event_id = e.id AND b.status = 'booked' AND s.user_id = auth.uid()))
           ORDER BY e.event_date, e.start_time, e.name), '[]'::jsonb)
    FROM events e
   WHERE auth.uid() IS NOT NULL AND _event_visible(e);
$$;


-- ============================================================
-- STEP 9 — get_my_event_students()
-- The students on the caller's login (siblings share one), for the
-- "who is performing?" picker. Active and trial students only.
-- ============================================================
CREATE OR REPLACE FUNCTION get_my_event_students()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'name', btrim(coalesce(nullif(btrim(s.first_name),''), p.first_name, '') || ' ' ||
                         coalesce(nullif(btrim(s.last_name),''),  p.last_name,  '')),
           'status', s.status)
         ORDER BY s.created_at), '[]'::jsonb)
    FROM students s LEFT JOIN profiles p ON p.id = s.user_id
   WHERE s.user_id = auth.uid() AND s.status IN ('active','trial');
$$;


-- ============================================================
-- STEP 10 — get_event_form_options(student, event)
-- What the booking form offers for this student: their instruments
-- and their teachers (with the instrument each teaches them).
-- Admins also get every teacher, for students with no teacher on file.
-- ============================================================
CREATE OR REPLACE FUNCTION get_event_form_options(p_student uuid, p_event uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ev   events%ROWTYPE;
  adm  boolean := get_my_role() IN ('superuser','admin');
  nm   text;
BEGIN
  SELECT * INTO ev FROM events WHERE id = p_event;
  IF NOT FOUND OR NOT _event_student_ok(p_student, ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;

  SELECT btrim(coalesce(nullif(btrim(s.first_name),''), p.first_name, '') || ' ' ||
               coalesce(nullif(btrim(s.last_name),''),  p.last_name,  ''))
    INTO nm
    FROM students s LEFT JOIN profiles p ON p.id = s.user_id WHERE s.id = p_student;

  RETURN jsonb_build_object(
    'student', jsonb_build_object('id', p_student, 'name', nm),
    'instruments', (
      SELECT coalesce(jsonb_agg(DISTINCT i ORDER BY i), '[]'::jsonb) FROM (
        SELECT instrument AS i FROM student_instruments WHERE student_id = p_student
        UNION
        SELECT x.instrument FROM _event_student_teachers(p_student) x
      ) y),
    'teachers', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', t.id,
               'name', btrim(coalesce(tp.first_name,'') || ' ' || coalesce(tp.last_name,'')),
               'instrument', x.instrument) ORDER BY tp.first_name, x.instrument), '[]'::jsonb)
        FROM _event_student_teachers(p_student) x
        JOIN teachers t  ON t.id = x.teacher_id
        JOIN profiles tp ON tp.id = t.user_id),
    'all_teachers', CASE WHEN adm THEN (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', t.id,
               'name', btrim(coalesce(tp.first_name,'') || ' ' || coalesce(tp.last_name,'')))
               ORDER BY tp.first_name), '[]'::jsonb)
        FROM teachers t JOIN profiles tp ON tp.id = t.user_id) ELSE '[]'::jsonb END
  );
END;
$$;


-- ============================================================
-- STEP 11 — get_event_grid(event)
-- The whole grid in one call, masked by who is asking:
--   admin    → every field of every performance
--   teacher  → full detail for their own students, masked for others
--   student  → full detail for their own family's performances,
--              masked ("Ava L." + instrument + piece + accompaniment
--              type) for everyone else; no teacher, no comments
-- own = true marks the rows to highlight (student's own / teacher's
-- own students). detail = true means the private fields are present.
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
                OR (r = 'teacher' AND tid IS NOT NULL AND (
                      b.teacher_id = tid
                      OR EXISTS (SELECT 1 FROM student_teachers stt
                                  WHERE stt.student_id = b.student_id AND stt.teacher_id = tid)))
               ) AS detail,
               (CASE WHEN r IN ('superuser','admin') THEN false
                     WHEN r = 'teacher' THEN (tid IS NOT NULL AND (
                           b.teacher_id = tid
                           OR EXISTS (SELECT 1 FROM student_teachers stt
                                       WHERE stt.student_id = b.student_id AND stt.teacher_id = tid)))
                     ELSE s.user_id = auth.uid() END) AS own
          FROM event_bookings b
          JOIN students s ON s.id = b.student_id
          LEFT JOIN profiles sp ON sp.id = s.user_id
          LEFT JOIN teachers t  ON t.id = b.teacher_id
          LEFT JOIN profiles tp ON tp.id = t.user_id
          CROSS JOIN LATERAL (SELECT coalesce(nullif(btrim(s.first_name),''), sp.first_name, '') AS fn,
                                     coalesce(nullif(btrim(s.last_name),''),  sp.last_name,  '') AS ln) f
         WHERE b.event_id = p_event AND b.status = 'booked'
      ) q), '[]'::jsonb)
  );
END;
$$;


-- ============================================================
-- STEP 12 — submit_event_booking(...)
-- Create a booking (p_booking_id NULL) or change one.
--
-- The student ranks 1–3 preferred BLOCKS. The first one with a free
-- slot wins; the slot number is the lowest free one in that block.
-- Changing a booking keeps its current slot if the preferences are
-- unchanged; otherwise it is re-placed (its own seat counts as free).
-- If every preferred block is full, nothing changes and the error
-- 'none_available' tells the student to pick again.
--
-- Errors raised (message = code): not_allowed, event_closed,
-- deadline_passed, instrument_booked, limit_reached, bad_input,
-- bad_preferences, not_found, none_available.
-- ============================================================
CREATE OR REPLACE FUNCTION submit_event_booking(
  p_event            uuid,
  p_student          uuid,
  p_instrument       text,
  p_teacher_id       uuid,
  p_teacher_name     text,
  p_piece            text,
  p_accompaniment    text,
  p_accompanist_name text,
  p_preferred        integer[],
  p_notes            text,
  p_booking_id       uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ev       events%ROWTYPE;
  bk       event_bookings%ROWTYPE;
  adm      boolean := get_my_role() IN ('superuser','admin');
  nb       integer;
  i        integer;
  j        integer;
  b        integer;
  v_pos    integer;
  new_b    integer;
  new_p    integer;
  v_id     uuid;
  kept     boolean := false;
  v_instr  text := btrim(coalesce(p_instrument, ''));
  v_piece  text := btrim(coalesce(p_piece, ''));
  v_acc    text := coalesce(p_accompaniment, 'none');
  v_accname text := nullif(btrim(coalesce(p_accompanist_name, '')), '');
  v_tname  text := nullif(btrim(coalesce(p_teacher_name, '')), '');
  v_notes  text := nullif(btrim(coalesce(p_notes, '')), '');
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_allowed'; END IF;

  -- One booking at a time per event: this lock is what stops two
  -- families being given the same slot.
  SELECT * INTO ev FROM events WHERE id = p_event FOR UPDATE;
  IF NOT FOUND OR NOT _event_student_ok(p_student, ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;

  PERFORM _event_check_window(ev);

  -- Inputs
  IF v_instr = '' OR char_length(v_instr) > 60
     OR v_piece = '' OR char_length(v_piece) > 120
     OR v_acc NOT IN ('teacher','peer','backing_track','none')
     OR (v_acc = 'peer' AND v_accname IS NULL)
     OR (v_accname IS NOT NULL AND char_length(v_accname) > 80)
     OR (v_tname IS NOT NULL AND char_length(v_tname) > 80)
     OR (v_notes IS NOT NULL AND char_length(v_notes) > 500) THEN
    RAISE EXCEPTION 'bad_input';
  END IF;
  IF v_acc <> 'peer' THEN v_accname := NULL; END IF;
  IF p_teacher_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM teachers WHERE id = p_teacher_id) THEN RAISE EXCEPTION 'bad_input'; END IF;
    v_tname := NULL;
  END IF;

  -- Preferences: 1–3 distinct blocks that exist
  nb := event_block_count(ev.start_time, ev.end_time, ev.block_minutes);
  IF p_preferred IS NULL OR cardinality(p_preferred) NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'bad_preferences';
  END IF;
  FOR i IN 1 .. cardinality(p_preferred) LOOP
    IF p_preferred[i] IS NULL OR p_preferred[i] < 1 OR p_preferred[i] > nb THEN
      RAISE EXCEPTION 'bad_preferences';
    END IF;
    FOR j IN 1 .. i - 1 LOOP
      IF p_preferred[j] = p_preferred[i] THEN RAISE EXCEPTION 'bad_preferences'; END IF;
    END LOOP;
  END LOOP;

  -- Editing an existing booking?
  IF p_booking_id IS NOT NULL THEN
    SELECT * INTO bk FROM event_bookings
     WHERE id = p_booking_id AND event_id = p_event AND student_id = p_student AND status = 'booked';
    IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  END IF;

  -- One performance per instrument per student (admins may bypass), plus an
  -- overall cap per student (admins may exceed it)
  IF NOT adm THEN
    IF EXISTS (
         SELECT 1 FROM event_bookings x
          WHERE x.event_id = p_event AND x.student_id = p_student AND x.status = 'booked'
            AND x.id IS DISTINCT FROM p_booking_id
            AND lower(btrim(x.instrument)) = lower(v_instr)
       ) THEN
      RAISE EXCEPTION 'instrument_booked';
    END IF;
    IF (
         SELECT count(*) FROM event_bookings x
          WHERE x.event_id = p_event AND x.student_id = p_student AND x.status = 'booked'
            AND x.id IS DISTINCT FROM p_booking_id
       ) >= ev.max_per_student THEN
      RAISE EXCEPTION 'limit_reached';
    END IF;
  END IF;

  -- Placement
  IF bk.id IS NOT NULL AND bk.preferred_blocks = p_preferred THEN
    new_b := bk.assigned_block; new_p := bk.assigned_position; kept := true;
  ELSE
    FOR i IN 1 .. cardinality(p_preferred) LOOP
      b := p_preferred[i];
      SELECT min(n) INTO v_pos
        FROM generate_series(1, ev.slots_per_block) n
       WHERE NOT EXISTS (
               SELECT 1 FROM event_bookings x
                WHERE x.event_id = p_event AND x.status = 'booked'
                  AND x.assigned_block = b AND x.assigned_position = n
                  AND x.id IS DISTINCT FROM p_booking_id);
      IF v_pos IS NOT NULL THEN new_b := b; new_p := v_pos; EXIT; END IF;
    END LOOP;
    IF new_b IS NULL THEN RAISE EXCEPTION 'none_available'; END IF;
  END IF;

  IF bk.id IS NULL THEN
    INSERT INTO event_bookings
      (event_id, student_id, instrument, teacher_id, teacher_name, piece, accompaniment,
       accompanist_name, preferred_blocks, assigned_block, assigned_position, notes)
    VALUES
      (p_event, p_student, v_instr, p_teacher_id, v_tname, v_piece, v_acc,
       v_accname, p_preferred, new_b, new_p, v_notes)
    RETURNING id INTO v_id;
  ELSE
    UPDATE event_bookings SET
           instrument = v_instr, teacher_id = p_teacher_id, teacher_name = v_tname,
           piece = v_piece, accompaniment = v_acc, accompanist_name = v_accname,
           preferred_blocks = p_preferred, assigned_block = new_b, assigned_position = new_p,
           notes = v_notes, updated_at = now()
     WHERE id = bk.id;
    v_id := bk.id;
  END IF;

  RETURN jsonb_build_object('booking_id', v_id, 'block', new_b, 'position', new_p,
                            'kept', kept,
                            'got_first_choice', new_b = p_preferred[1]);
END;
$$;


-- ============================================================
-- STEP 13 — cancel_event_booking(booking)
-- The family (while the event is open) or an admin (any time).
-- The row is kept, marked cancelled, and the slot is freed.
-- ============================================================
CREATE OR REPLACE FUNCTION cancel_event_booking(p_booking uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bk event_bookings%ROWTYPE;
  ev events%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_allowed'; END IF;
  SELECT * INTO bk FROM event_bookings WHERE id = p_booking;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  SELECT * INTO ev FROM events WHERE id = bk.event_id FOR UPDATE;
  IF NOT _event_student_ok(bk.student_id, ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;
  PERFORM _event_check_window(ev);

  UPDATE event_bookings
     SET status = 'cancelled', cancelled_at = now(), updated_at = now()
   WHERE id = p_booking AND status = 'booked';
  RETURN jsonb_build_object('cancelled', FOUND);
END;
$$;


-- ============================================================
-- STEP 14 — move_event_booking(booking, block, position, swap)
-- Admin only. Moves a performance to another slot. If the target
-- slot is taken, it is refused ('slot_taken') unless p_swap is true,
-- in which case the two performances change places.
-- ============================================================
CREATE OR REPLACE FUNCTION move_event_booking(
  p_booking  uuid,
  p_block    integer,
  p_position integer,
  p_swap     boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bk    event_bookings%ROWTYPE;
  other event_bookings%ROWTYPE;
  ev    events%ROWTYPE;
  nb    integer;
BEGIN
  IF auth.uid() IS NULL OR get_my_role() NOT IN ('superuser','admin') THEN
    RAISE EXCEPTION 'not_allowed';
  END IF;
  SELECT * INTO bk FROM event_bookings WHERE id = p_booking AND status = 'booked';
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  SELECT * INTO ev FROM events WHERE id = bk.event_id FOR UPDATE;
  IF NOT _event_visible(ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;

  nb := event_block_count(ev.start_time, ev.end_time, ev.block_minutes);
  IF p_block IS NULL OR p_position IS NULL
     OR p_block < 1 OR p_block > nb
     OR p_position < 1 OR p_position > ev.slots_per_block THEN
    RAISE EXCEPTION 'bad_slot';
  END IF;

  -- Already there: nothing to do
  IF bk.assigned_block = p_block AND bk.assigned_position = p_position THEN
    RETURN jsonb_build_object('moved', false);
  END IF;

  SELECT * INTO other FROM event_bookings
   WHERE event_id = bk.event_id AND status = 'booked'
     AND assigned_block = p_block AND assigned_position = p_position;

  IF FOUND THEN
    IF NOT p_swap THEN RAISE EXCEPTION 'slot_taken'; END IF;
    -- Park the other performance on the reserved slot 1000, move this
    -- one, then bring the other into the slot just vacated.
    UPDATE event_bookings SET assigned_position = 1000, updated_at = now() WHERE id = other.id;
    UPDATE event_bookings SET assigned_block = p_block, assigned_position = p_position, updated_at = now()
     WHERE id = bk.id;
    UPDATE event_bookings SET assigned_block = bk.assigned_block, assigned_position = bk.assigned_position,
                              updated_at = now()
     WHERE id = other.id;
    RETURN jsonb_build_object('moved', true, 'swapped_with', other.id);
  END IF;

  UPDATE event_bookings SET assigned_block = p_block, assigned_position = p_position, updated_at = now()
   WHERE id = bk.id;
  RETURN jsonb_build_object('moved', true);
END;
$$;


-- ============================================================
-- STEP 15 — who may call what.
-- The helpers (names starting _) are for the functions above only.
-- The browser may call the public functions, as a signed-in user.
-- ============================================================
REVOKE ALL ON FUNCTION _event_visible(events)             FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION _event_student_ok(uuid, events)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION _event_check_window(events)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION _event_json(events)                FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION _event_student_teachers(uuid)    FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION list_events_for_me()               FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION get_my_event_students()            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION get_event_form_options(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION get_event_grid(uuid)               FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION submit_event_booking(uuid, uuid, text, uuid, text, text, text, text, integer[], text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION cancel_event_booking(uuid)         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION move_event_booking(uuid, integer, integer, boolean) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION list_events_for_me()               TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_event_students()            TO authenticated;
GRANT EXECUTE ON FUNCTION get_event_form_options(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_event_grid(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION submit_event_booking(uuid, uuid, text, uuid, text, text, text, text, integer[], text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_event_booking(uuid)         TO authenticated;
GRANT EXECUTE ON FUNCTION move_event_booking(uuid, integer, integer, boolean) TO authenticated;


-- ============================================================
-- STEP 16 — verify (optional). Expect: both tables listed with
-- rowsecurity = true, and seven callable functions.
-- ============================================================
SELECT tablename, rowsecurity FROM pg_tables
 WHERE tablename IN ('events','event_bookings') ORDER BY tablename;

SELECT proname FROM pg_proc
 WHERE proname IN ('list_events_for_me','get_my_event_students','get_event_form_options',
                   'get_event_grid','submit_event_booking','cancel_event_booking','move_event_booking')
 ORDER BY proname;


-- ============================================================
-- TO REVERSE (only if you must; it deletes every event and booking)
-- ============================================================
-- DROP FUNCTION IF EXISTS move_event_booking(uuid, integer, integer, boolean);
-- DROP FUNCTION IF EXISTS cancel_event_booking(uuid);
-- DROP FUNCTION IF EXISTS submit_event_booking(uuid, uuid, text, uuid, text, text, text, text, integer[], text, uuid);
-- DROP FUNCTION IF EXISTS get_event_grid(uuid);
-- DROP FUNCTION IF EXISTS get_event_form_options(uuid, uuid);
-- DROP FUNCTION IF EXISTS get_my_event_students();
-- DROP FUNCTION IF EXISTS list_events_for_me();
-- DROP FUNCTION IF EXISTS _event_json(events);
-- DROP FUNCTION IF EXISTS _event_student_teachers(uuid);
-- DROP FUNCTION IF EXISTS _event_check_window(events);
-- DROP FUNCTION IF EXISTS _event_student_ok(uuid, events);
-- DROP FUNCTION IF EXISTS _event_visible(events);
-- DROP TABLE IF EXISTS event_bookings;
-- DROP TABLE IF EXISTS events;
-- DROP FUNCTION IF EXISTS events_guard_update();
-- DROP FUNCTION IF EXISTS event_block_count(time, time, integer);
