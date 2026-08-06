-- ============================================================
-- "Lesson series added" must mean a SERIES
--
-- The check was "does an active lesson exist", which a trial
-- student already satisfies — their trial lesson is still on
-- file. So the item ticked itself the moment the ongoing
-- enrolment checklist opened, and worse, the enrolment
-- confirmation email was built from the trial lesson's details.
--
-- A trial is one occurrence; a series recurs.
-- ============================================================

UPDATE process_items pi
   SET auto_key = 'series_exists'
  FROM student_processes sp
 WHERE sp.id = pi.process_id
   AND sp.process_type = 'ongoing_enrolment'
   AND pi.auto_key = 'lesson_exists';

-- Any enrolment email already sent will have described the trial
-- lesson. Clearing sent_at lets it go again correctly once the real
-- series is booked. Check the list first — if a student was sent a
-- wrong one, they should be told.
SELECT p.first_name, p.last_name, pi.sent_at
  FROM process_items pi
  JOIN student_processes sp ON sp.id = pi.process_id
  JOIN students s  ON s.id = sp.student_id
  JOIN profiles p  ON p.id = s.user_id
 WHERE sp.process_type = 'ongoing_enrolment'
   AND pi.auto_key = 'email_sent'
   AND pi.sent_at IS NOT NULL;

-- Then, for those that were wrong:
-- UPDATE process_items pi
--    SET sent_at = NULL
--   FROM student_processes sp
--  WHERE sp.id = pi.process_id
--    AND sp.process_type = 'ongoing_enrolment'
--    AND pi.auto_key = 'email_sent';

NOTIFY pgrst, 'reload schema';

-- Verify
SELECT sp.process_type, pi.label, pi.auto_key
  FROM process_items pi
  JOIN student_processes sp ON sp.id = pi.process_id
 ORDER BY sp.process_type, pi.item_order;
