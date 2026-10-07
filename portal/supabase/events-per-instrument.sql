-- ============================================================
-- Portal Events — one performance per instrument (migration #42)
-- Run each numbered statement ONE AT A TIME in the Supabase SQL editor,
-- BEFORE deploying the matching pages. Safe to re-run.
--
-- Fresh installs do NOT need this file: events.sql already includes it.
-- ============================================================

-- 1. Allow the overall per-student cap to go up to 10
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_max_per_student_check;

-- 2. (separate statement)
ALTER TABLE events ADD CONSTRAINT events_max_per_student_check
  CHECK (max_per_student BETWEEN 1 AND 10);

-- 3. New events default to a cap of 5 (the real limit is one per instrument)
ALTER TABLE events ALTER COLUMN max_per_student SET DEFAULT 5;

-- 4. Existing events still on the old default of 1 would block a second
--    instrument, so lift them to 5
UPDATE events SET max_per_student = 5 WHERE max_per_student = 1;

-- 5. The booking function (replaces the existing one; privileges are kept)
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
