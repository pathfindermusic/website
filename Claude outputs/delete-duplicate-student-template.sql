-- ============================================================
-- ONE-OFF CLEANUP: remove a duplicate/broken student record
-- ============================================================
-- Context: a prospective student ended up with two `students` rows.
-- One completed the ongoing-enrolment process and is the real,
-- active student. The other is stuck mid-process and isn't real.
--
-- This is NOT a schema migration — nothing to add to the README's
-- migration list. It's a one-time cleanup, structured as:
--   STEP 1 — find the pair (read-only)
--   STEP 2 — sanity-check the one you're about to delete (read-only)
--   STEP 3 — delete it and everything hanging off it, in the right
--            order for foreign keys
--   STEP 4 — confirm it's gone (read-only)
--   STEP 5 — optional: remove an orphaned login, if it had its own
--
-- ⚠ Run ONE STATEMENT AT A TIME and read each result before moving
-- on. Deleting the wrong row is not recoverable — there is no undo.
-- ============================================================


-- ============================================================
-- STEP 1 — find the duplicate pair
-- ============================================================
-- Edit the ILIKE values (or switch to matching on parent_email /
-- email instead) until this returns your two candidate rows.

SELECT
  s.id                                                        AS student_id,
  p.first_name, p.last_name,
  s.status, s.studio_id, s.user_id, s.created_at,
  s.email, s.parent_email, s.parent_name,
  (SELECT count(*) FROM lesson_students ls
    WHERE ls.student_id = s.id)                                AS lesson_count,
  (SELECT count(*) FROM attendance a
    WHERE a.student_id = s.id)                                 AS attendance_count,
  (SELECT count(*) FROM student_processes sp
    WHERE sp.student_id = s.id AND sp.status = 'in_progress')   AS processes_in_progress,
  (SELECT count(*) FROM tasks t
    WHERE t.subject_type = 'student' AND t.subject_id = s.id
      AND t.status = 'open')                                    AS open_tasks
FROM students s
LEFT JOIN profiles p ON p.id = s.user_id
WHERE p.first_name ILIKE '%FIRSTNAME%' AND p.last_name ILIKE '%LASTNAME%'
ORDER BY s.created_at;

-- Read this carefully. The broken duplicate is almost certainly the
-- one with lesson_count = 0 and processes_in_progress >= 1 (still
-- mid-enrolment). The real student should show lesson_count > 0 and
-- no processes_in_progress. If both rows look "real" (both have
-- lessons/attendance), STOP and don't delete either — that's a
-- different situation than the one described here.


-- ============================================================
-- STEP 2 — before deleting: note the broken row's user_id, and
-- check whether it's shared with the real student's row
-- ============================================================
-- Paste the BROKEN student's id from Step 1 below. This just tells
-- you whether they share one family login (same user_id as the real
-- student, or as a sibling) or whether this broken record has its
-- own separate login nobody else uses.

SELECT id, user_id FROM students WHERE id = 'BROKEN-STUDENT-ID-HERE';
SELECT id FROM students WHERE user_id = (
  SELECT user_id FROM students WHERE id = 'BROKEN-STUDENT-ID-HERE'
);
-- ^ if this second query returns MORE than just the broken row's own
-- id, the login is shared — leave the profile/auth account alone in
-- Step 5. If it returns only the broken row itself, the login is
-- theirs alone and is safe to clean up in Step 5.


-- ============================================================
-- STEP 3 — delete the broken row and its dependents
-- ============================================================
-- Replace BROKEN-STUDENT-ID-HERE in EVERY statement below with the
-- actual id (find-and-replace before running). Run one at a time,
-- top to bottom — this order respects foreign keys.

-- Task notes / handovers on any task about this student
DELETE FROM task_notes
 WHERE task_id IN (
   SELECT id FROM tasks WHERE subject_type = 'student' AND subject_id = 'BROKEN-STUDENT-ID-HERE'
 );

DELETE FROM task_handovers
 WHERE task_id IN (
   SELECT id FROM tasks WHERE subject_type = 'student' AND subject_id = 'BROKEN-STUDENT-ID-HERE'
 );

-- Any open/closed task about this student (e.g. the enrolment
-- checklist's blocked-task entries)
DELETE FROM tasks
 WHERE subject_type = 'student' AND subject_id = 'BROKEN-STUDENT-ID-HERE';

-- The stuck enrolment process and its checklist items
DELETE FROM process_items
 WHERE process_id IN (
   SELECT id FROM student_processes WHERE student_id = 'BROKEN-STUDENT-ID-HERE'
 );

DELETE FROM student_processes
 WHERE student_id = 'BROKEN-STUDENT-ID-HERE';

-- Attendance, lesson membership, teacher assignments, instruments
DELETE FROM attendance        WHERE student_id = 'BROKEN-STUDENT-ID-HERE';
DELETE FROM lesson_students   WHERE student_id = 'BROKEN-STUDENT-ID-HERE';
DELETE FROM student_teachers  WHERE student_id = 'BROKEN-STUDENT-ID-HERE';
DELETE FROM student_instruments WHERE student_id = 'BROKEN-STUDENT-ID-HERE';

-- Legacy single-student column on lessons (the app now uses
-- lesson_students for this, so this is almost certainly 0 rows for
-- a record that never got a real lesson — but detach rather than
-- delete, in case a real lesson somehow points at it)
UPDATE lessons SET student_id = NULL WHERE student_id = 'BROKEN-STUDENT-ID-HERE';

-- Finally, the student record itself
DELETE FROM students WHERE id = 'BROKEN-STUDENT-ID-HERE';


-- ============================================================
-- STEP 4 — confirm it's gone
-- ============================================================
SELECT * FROM students WHERE id = 'BROKEN-STUDENT-ID-HERE';
-- ^ should return 0 rows


-- ============================================================
-- STEP 5 — optional: remove an orphaned login
-- ============================================================
-- Only do this if Step 2 showed the broken record's user_id was
-- NOT shared with anyone else (its own login, nobody else uses it).
-- If it WAS shared (a family/sibling login), skip this step entirely
-- — deleting it would log out a real student.

-- 5a. Remove the profile row:
-- DELETE FROM profiles WHERE id = 'BROKEN-USER-ID-HERE';

-- 5b. Then remove the actual login — do this in the Supabase
-- Dashboard, not SQL: Authentication → Users → find that person's
-- email → Delete user. That's the safest way to remove an auth
-- account cleanly (it also exists as a "delete-user" action in
-- netlify/functions/create-user.js if you'd rather script it, but
-- the dashboard is simplest for a one-off).
