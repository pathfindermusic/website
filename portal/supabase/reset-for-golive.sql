-- ============================================================
-- PATHFINDER PORTAL — reset for go-live
--
-- Clears test data so real records can be entered.
--
-- KEPT:      studios, super user, admin accounts
-- OPTIONAL:  teachers and their availability (see STEP 3)
-- DELETED:   students, enquiries, lessons, occurrences,
--            attendance, notes, tasks, processes, email log
--
-- ⚠ IRREVERSIBLE. Take a backup first:
--   Supabase → Database → Backups
--
-- ⚠ Run ONE SECTION AT A TIME and read each result.
--   STEP 1 only counts. Nothing is deleted until STEP 2.
-- ============================================================


-- ============================================================
-- STEP 1 — what is there now? Deletes nothing.
-- ============================================================
SELECT 'studios'            AS t, COUNT(*) FROM studios
UNION ALL SELECT 'admins',           COUNT(*) FROM admins
UNION ALL SELECT 'teachers',         COUNT(*) FROM teachers
UNION ALL SELECT 'teacher_availability', COUNT(*) FROM teacher_availability
UNION ALL SELECT 'students',         COUNT(*) FROM students
UNION ALL SELECT 'student_instruments', COUNT(*) FROM student_instruments
UNION ALL SELECT 'lessons',          COUNT(*) FROM lessons
UNION ALL SELECT 'lesson_occurrences', COUNT(*) FROM lesson_occurrences
UNION ALL SELECT 'lesson_students',  COUNT(*) FROM lesson_students
UNION ALL SELECT 'attendance',       COUNT(*) FROM attendance
UNION ALL SELECT 'lesson_notes',     COUNT(*) FROM lesson_notes
UNION ALL SELECT 'tasks',            COUNT(*) FROM tasks
UNION ALL SELECT 'task_notes',       COUNT(*) FROM task_notes
UNION ALL SELECT 'task_handovers',   COUNT(*) FROM task_handovers
UNION ALL SELECT 'student_processes', COUNT(*) FROM student_processes
UNION ALL SELECT 'process_items',    COUNT(*) FROM process_items
UNION ALL SELECT 'email_log',        COUNT(*) FROM email_log
UNION ALL SELECT 'profiles',         COUNT(*) FROM profiles
ORDER BY t;

-- Who is being kept? Check this list before going further.
SELECT p.id, p.first_name, p.last_name, p.role, u.email
  FROM profiles p
  LEFT JOIN auth.users u ON u.id = p.id
 WHERE p.role IN ('superuser','admin')
 ORDER BY p.role, p.first_name;


-- ============================================================
-- STEP 2 — clear everything that hangs off students and lessons
--
-- Order matters: children before parents. Each statement reports
-- how many rows it removed.
-- ============================================================

-- Tasks and their history
DELETE FROM task_notes;
DELETE FROM task_handovers;
DELETE FROM tasks;

-- Enrolment checklists
DELETE FROM process_items;
DELETE FROM student_processes;

-- Attendance and lesson notes
DELETE FROM attendance;
DELETE FROM lesson_notes;

-- Lessons
DELETE FROM lesson_students;
DELETE FROM lesson_occurrences;
DELETE FROM lessons;

-- Students
DELETE FROM student_instruments;
DELETE FROM students;

-- Sent-mail audit trail
DELETE FROM email_log;


-- ============================================================
-- STEP 3 — teachers
--
-- Skip this section entirely to keep them.
-- ============================================================

DELETE FROM teacher_availability;
DELETE FROM teachers;


-- ============================================================
-- STEP 4 — orphaned profiles
--
-- Every profile that is not an admin, super user, or a teacher
-- still on file. Students had a profile each; those are now
-- unreferenced.
--
-- Check the list before deleting.
-- ============================================================
SELECT p.id, p.first_name, p.last_name, p.role
  FROM profiles p
 WHERE p.role NOT IN ('superuser','admin')
   AND NOT EXISTS (SELECT 1 FROM teachers t WHERE t.user_id = p.id)
 ORDER BY p.role, p.first_name;

-- Then:
DELETE FROM profiles p
 WHERE p.role NOT IN ('superuser','admin')
   AND NOT EXISTS (SELECT 1 FROM teachers t WHERE t.user_id = p.id);


-- ============================================================
-- STEP 5 — orphaned login accounts
--
-- A profile row and an auth account are separate: profiles.id has
-- no foreign key to auth.users, which is what lets bulk-imported
-- students exist without a login. Deleting profiles therefore
-- leaves the auth accounts behind, and those addresses stay
-- taken — a real student re-registering later would collide.
--
-- Check the list first. Anything here can still sign in.
-- ============================================================
SELECT u.id, u.email, u.created_at
  FROM auth.users u
 WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = u.id)
 ORDER BY u.created_at;

-- Then:
-- DELETE FROM auth.users u
--  WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = u.id);


-- ============================================================
-- STEP 6 — verify
--
-- Everything cleared should read 0. Studios, admins and (unless
-- STEP 3 was run) teachers should be unchanged.
-- ============================================================
SELECT 'studios'            AS t, COUNT(*) FROM studios
UNION ALL SELECT 'admins',           COUNT(*) FROM admins
UNION ALL SELECT 'teachers',         COUNT(*) FROM teachers
UNION ALL SELECT 'teacher_availability', COUNT(*) FROM teacher_availability
UNION ALL SELECT 'students',         COUNT(*) FROM students
UNION ALL SELECT 'lessons',          COUNT(*) FROM lessons
UNION ALL SELECT 'lesson_occurrences', COUNT(*) FROM lesson_occurrences
UNION ALL SELECT 'attendance',       COUNT(*) FROM attendance
UNION ALL SELECT 'lesson_notes',     COUNT(*) FROM lesson_notes
UNION ALL SELECT 'tasks',            COUNT(*) FROM tasks
UNION ALL SELECT 'student_processes', COUNT(*) FROM student_processes
UNION ALL SELECT 'email_log',        COUNT(*) FROM email_log
UNION ALL SELECT 'profiles',         COUNT(*) FROM profiles
UNION ALL SELECT 'auth.users',       COUNT(*) FROM auth.users
ORDER BY t;

-- Finally, confirm you can still sign in as the super user before
-- entering any real data.
