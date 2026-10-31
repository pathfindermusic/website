-- ============================================================
-- Events: backing-track link on a performance (migration 51)
-- ============================================================
-- Teachers reply to their "Backing track for ..." task with a link
-- (YouTube, or a file on the studio's Google Drive). An admin / the
-- superuser records that link on the performance. It then shows in
-- the Running order (and its print / PDF sheet) next to
-- "Backing track", for admins, the performer's teacher(s) and the
-- performer's own family. Other families never see it.
--
-- Nothing is lost if the student later switches to another kind of
-- accompaniment: the link is kept, but hidden until the performance
-- is a backing-track one again.
--
-- RUN EACH STATEMENT BELOW ON ITS OWN in the Supabase SQL editor
-- (STEP 1, then 2, 3, 4, 5, 6), in this order.
-- ============================================================


-- ============================================================
-- STEP 1 — the column (a web address, at most 500 characters)
-- ============================================================
ALTER TABLE event_bookings
  ADD COLUMN IF NOT EXISTS backing_track_url text
  CONSTRAINT event_bookings_backing_track_url_chk
  CHECK (backing_track_url IS NULL
         OR (char_length(backing_track_url) <= 500 AND backing_track_url ~* '^https?://[^[:space:]]+$'));


-- ============================================================
-- STEP 2 — set_event_backing_track(booking, url)
-- Admin / superuser only (for an event of their studio).
-- An empty url removes the link. 'bad_url' if it is not an
-- http(s) address.
-- ============================================================
CREATE OR REPLACE FUNCTION set_event_backing_track(p_booking uuid, p_url text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bk event_bookings%ROWTYPE;
  ev events%ROWTYPE;
  v  text := nullif(btrim(coalesce(p_url, '')), '');
BEGIN
  IF auth.uid() IS NULL OR get_my_role() NOT IN ('superuser','admin') THEN
    RAISE EXCEPTION 'not_allowed';
  END IF;
  SELECT * INTO bk FROM event_bookings WHERE id = p_booking AND status = 'booked';
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  SELECT * INTO ev FROM events WHERE id = bk.event_id;
  IF NOT _event_visible(ev) THEN RAISE EXCEPTION 'not_allowed'; END IF;

  IF v IS NOT NULL AND (char_length(v) > 500 OR v !~* '^https?://[^[:space:]]+$') THEN
    RAISE EXCEPTION 'bad_url';
  END IF;

  UPDATE event_bookings SET backing_track_url = v, updated_at = now() WHERE id = p_booking;
  RETURN jsonb_build_object('booking_id', p_booking, 'backing_track_url', v);
END;
$$;


-- ============================================================
-- STEP 3 — who may call it
-- ============================================================
REVOKE ALL ON FUNCTION set_event_backing_track(uuid, text) FROM PUBLIC, anon;


-- ============================================================
-- STEP 4 — ... and the logged-in portal users (the function itself
-- refuses anyone who is not an admin / the superuser)
-- ============================================================
GRANT EXECUTE ON FUNCTION set_event_backing_track(uuid, text) TO authenticated;


-- ============================================================
-- STEP 5 — get_event_grid(): same as before (bands, teachers, ...)
-- plus `backing_track_url` on each booking, only where the viewer
-- may see the performance's details and it is a backing-track one.
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
          'backing_track_url', CASE WHEN q.detail AND q.accompaniment = 'backing_track' THEN q.backing_track_url END,
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
-- STEP 6 — check (should return 1 row, then 1 row with 'text')
-- ============================================================
SELECT proname FROM pg_proc WHERE proname = 'set_event_backing_track';

SELECT column_name, data_type FROM information_schema.columns
 WHERE table_name = 'event_bookings' AND column_name = 'backing_track_url';


-- ROLLBACK (only if needed):
--   re-run the get_event_grid() from events-bands.sql (STEP 7), then
--   DROP FUNCTION IF EXISTS set_event_backing_track(uuid, text);
--   ALTER TABLE event_bookings DROP COLUMN IF EXISTS backing_track_url;
