-- ============================================================
-- Portal Events — a student may be in more than one band (migration #46)
-- Run each numbered statement ONE AT A TIME in the Supabase SQL editor,
-- BEFORE deploying the matching pages. Safe to re-run.
--
-- Until now a student could be in only ONE band performance per event
-- ('already_in_band'). Now a student may be in any number of bands at the same
-- event, including bands in the same time block (students often want their
-- band performances back to back). Nothing else changes: members must be
-- Active/Trial and in the event's studio, 2-12 members, and each slot still
-- holds only one performance.
--
-- An earlier version of this file refused two bands in the same block. Running
-- this version replaces that: the same-block check is removed from both
-- functions and its helper is dropped. Safe whether or not the earlier
-- version was run.
--
-- Fresh installs: run events-bands.sql first, then this file.
-- ============================================================

-- 1. combine_event_bookings — replaces the existing one
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


-- 2. (separate statement) move_event_booking — back to the plain version
--    (a band move is no longer checked against the student's other bands)
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


-- 3. (separate statement) The same-block helper from the earlier version of
--    this migration, if it exists
DROP FUNCTION IF EXISTS _event_band_clash(uuid, integer, uuid[], uuid[]);


-- 4. Verify — combine_event_bookings and move_event_booking should be listed,
--    and _event_band_clash should NOT be
SELECT proname FROM pg_proc
 WHERE proname IN ('_event_band_clash', 'combine_event_bookings', 'move_event_booking')
 ORDER BY proname;
