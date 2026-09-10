-- ============================================================
-- Delete broken duplicate: Ario Ameri (parent_name "Tabesh")
-- student_id = 85f91df1-a29c-4927-92b6-eb3733029956
-- Confirmed by admin: this is the duplicate, intentionally given a
-- different parent_name to tell it apart from the real record
-- (26368637-e3df-4ce0-a183-115f54122d66, parent_name "Azadeh").
--
-- ⚠ Run ONE STATEMENT AT A TIME and read each result.
-- ============================================================


-- ============================================================
-- STEP A — is this record's login shared with anyone else?
-- ============================================================
SELECT id, user_id FROM students
 WHERE id = '85f91df1-a29c-4927-92b6-eb3733029956';

SELECT id FROM students
 WHERE user_id = (
   SELECT user_id FROM students WHERE id = '85f91df1-a29c-4927-92b6-eb3733029956'
 );
-- If this returns ONLY 85f91df1-a29c-4927-92b6-eb3733029956, its
-- login is its own — safe to clean up in Step D below.
-- If it returns more than one id, that login is shared (e.g. with
-- the real Ario record, or a sibling) — do NOT touch the profile/
-- auth account in Step D, only delete the student row itself.


-- ============================================================
-- STEP B — delete the record and everything attached to it
-- ============================================================

-- Task notes / handovers on any task about this student
DELETE FROM task_notes
 WHERE task_id IN (
   SELECT id FROM tasks WHERE subject_type = 'student'
     AND subject_id = '85f91df1-a29c-4927-92b6-eb3733029956'
 );

DELETE FROM task_handovers
 WHERE task_id IN (
   SELECT id FROM tasks WHERE subject_type = 'student'
     AND subject_id = '85f91df1-a29c-4927-92b6-eb3733029956'
 );

-- Any task about this student (e.g. the enrolment checklist's
-- blocked-task entries, and the 2 open tasks we saw in Step 1)
DELETE FROM tasks
 WHERE subject_type = 'student'
   AND subject_id = '85f91df1-a29c-4927-92b6-eb3733029956';

-- The stuck enrolment process and its checklist items
DELETE FROM process_items
 WHERE process_id IN (
   SELECT id FROM student_processes
    WHERE student_id = '85f91df1-a29c-4927-92b6-eb3733029956'
 );

DELETE FROM student_processes
 WHERE student_id = '85f91df1-a29c-4927-92b6-eb3733029956';

-- Attendance, lesson membership, teacher assignments, instruments
DELETE FROM attendance          WHERE student_id = '85f91df1-a29c-4927-92b6-eb3733029956';
DELETE FROM lesson_students     WHERE student_id = '85f91df1-a29c-4927-92b6-eb3733029956';
DELETE FROM student_teachers    WHERE student_id = '85f91df1-a29c-4927-92b6-eb3733029956';
DELETE FROM student_instruments WHERE student_id = '85f91df1-a29c-4927-92b6-eb3733029956';

-- Legacy single-student column on lessons — detach rather than
-- delete, in case a real lesson somehow points at it
UPDATE lessons SET student_id = NULL
 WHERE student_id = '85f91df1-a29c-4927-92b6-eb3733029956';

-- The trial lesson series itself, IF it's only ever used by this
-- duplicate (check first — skip this statement if the real Ario
-- record also appears in lesson_students for the same lesson_id,
-- e.g. if they were merged onto one shared trial lesson).
-- SELECT * FROM lessons WHERE id IN (
--   SELECT lesson_id FROM lesson_students WHERE student_id = '85f91df1-a29c-4927-92b6-eb3733029956'
-- );
-- (lesson_students for this student was already deleted above, so
-- this is just here for reference if you want to also clean up an
-- orphaned one-off trial lesson row afterwards — it's harmless to
-- leave behind if you'd rather not bother.)

-- Finally, the student record itself
DELETE FROM students WHERE id = '85f91df1-a29c-4927-92b6-eb3733029956';


-- ============================================================
-- STEP C — confirm it's gone
-- ============================================================
SELECT * FROM students WHERE id = '85f91df1-a29c-4927-92b6-eb3733029956';
-- ^ should return 0 rows

-- Sanity check the real record is untouched:
SELECT * FROM students WHERE id = '26368637-e3df-4ce0-a183-115f54122d66';


-- ============================================================
-- STEP D — optional: remove an orphaned login
-- ============================================================
-- Only if Step A showed this student's user_id belongs to no one
-- else. If it does, skip this step.

-- DELETE FROM profiles WHERE id = '8003e169-9e68-4c6c-8a01-995608bda968';

-- Then go to Supabase Dashboard → Authentication → Users, find the
-- matching login and delete it there — simplest and safest for a
-- one-off.
