-- ============================================================
-- PATHFINDER PORTAL — purge lessons scheduled before 1 Sep 2026
--
-- Removes every lesson_occurrences row dated before the cutoff,
-- plus everything that hangs off it (attendance, lesson notes,
-- BoK artefact picks, reminder-email log rows, and any ad-hoc
-- occurrence-only student added just for one of them). A lesson
-- SERIES (the `lessons` row — student + teacher + instrument +
-- weekly/fortnightly slot) is then removed too, but only once it
-- has zero occurrences left anywhere, past or future — a series
-- that still has an upcoming lesson is left completely alone.
--
-- Deliberately NOT touched:
--   email_log   — the sent-mail history isn't linked to a lesson
--                  by ID (just free text), so there's no reliable
--                  way to know which rows are "about" an old
--                  lesson without risking unrelated ones.
--   students, teachers, tasks, processes — nothing here is
--                  lesson-specific; a student/teacher with no
--                  lessons left is unaffected.
--
-- Does not rely on ON DELETE CASCADE anywhere — every table is
-- cleared explicitly, children before parents, the same style as
-- reset-for-golive.sql.
--
-- ⚠ IRREVERSIBLE. Take a backup first: Supabase → Database → Backups
--   (or Database → Backups → "Export" for a plain SQL/CSV copy of
--   just these tables if you'd rather not do a full snapshot).
--
-- ⚠ Run ONE STATEMENT AT A TIME and read each result.
--   STEP 1 only counts — nothing is deleted until STEP 2.
--
-- To reuse this later with a different cutoff, find/replace every
-- '2026-09-01' below with the new date (appears in STEP 1, 2 and 3).
-- ============================================================


-- ============================================================
-- STEP 1 — what would be removed? Deletes nothing.
-- ============================================================

-- a. Occurrences before the cutoff, and everything that hangs off them
SELECT 'lesson_occurrences (to purge)' AS t, COUNT(*) AS n
  FROM lesson_occurrences WHERE date < '2026-09-01'
UNION ALL
SELECT 'attendance', COUNT(*) FROM attendance
 WHERE lesson_occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01')
UNION ALL
SELECT 'lesson_notes', COUNT(*) FROM lesson_notes
 WHERE lesson_occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01')
UNION ALL
SELECT 'lesson_occurrence_artefacts', COUNT(*) FROM lesson_occurrence_artefacts
 WHERE occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01')
UNION ALL
SELECT 'reminder_log', COUNT(*) FROM reminder_log
 WHERE occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01')
UNION ALL
SELECT 'lesson_students (occurrence-only guests)', COUNT(*) FROM lesson_students
 WHERE added_for_occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01')
ORDER BY t;

-- b. Series that would become empty (zero occurrences left anywhere)
--    once (a) above is gone — these `lessons` rows get removed too.
--    Check this list: it's who stops appearing in the portal entirely.
--    Restricted to series created before the cutoff, so a lesson set
--    up today whose occurrences just haven't been generated yet is
--    never mistaken for an abandoned one.
SELECT l.id, sp.first_name || ' ' || sp.last_name AS student_name,
       tp.first_name || ' ' || tp.last_name AS teacher_name,
       l.instrument, l.status, l.recurrence_start, l.recurrence_end
  FROM lessons l
  LEFT JOIN students s ON s.id = l.student_id
  LEFT JOIN profiles sp ON sp.id = s.user_id
  JOIN teachers t  ON t.id = l.teacher_id
  JOIN profiles tp ON tp.id = t.user_id
 WHERE l.created_at < '2026-09-01'
   AND NOT EXISTS (
     SELECT 1 FROM lesson_occurrences lo
      WHERE lo.lesson_id = l.id AND lo.date >= '2026-09-01'
   )
 ORDER BY student_name;


-- ============================================================
-- STEP 2 — delete, children before parents
-- ============================================================

-- Attendance and notes for the purged occurrences
DELETE FROM attendance
 WHERE lesson_occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01');

DELETE FROM lesson_notes
 WHERE lesson_occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01');

-- BoK artefact picks and reminder-send log for those occurrences
DELETE FROM lesson_occurrence_artefacts
 WHERE occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01');

DELETE FROM reminder_log
 WHERE occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01');

-- Ad-hoc guests added for one of the purged occurrences only
-- (a permanent series member — added_for_occurrence_id IS NULL — is
-- untouched here; that's handled below, only if their whole series
-- is being removed)
DELETE FROM lesson_students
 WHERE added_for_occurrence_id IN (SELECT id FROM lesson_occurrences WHERE date < '2026-09-01');

-- The occurrences themselves
DELETE FROM lesson_occurrences WHERE date < '2026-09-01';

-- Series left with nothing scheduled anywhere, past or future —
-- their permanent roster, then the series row itself. Same
-- created-before-cutoff guard as the STEP 1b preview.
DELETE FROM lesson_students
 WHERE lesson_id IN (
   SELECT l.id FROM lessons l
    WHERE l.created_at < '2026-09-01'
      AND NOT EXISTS (SELECT 1 FROM lesson_occurrences lo WHERE lo.lesson_id = l.id)
 );

DELETE FROM lessons
 WHERE id IN (
   SELECT l.id FROM lessons l
    WHERE l.created_at < '2026-09-01'
      AND NOT EXISTS (SELECT 1 FROM lesson_occurrences lo WHERE lo.lesson_id = l.id)
 );


-- ============================================================
-- STEP 3 — verify
-- ============================================================

-- Should be 0
SELECT 'lesson_occurrences before cutoff' AS t, COUNT(*) AS n
  FROM lesson_occurrences WHERE date < '2026-09-01'
UNION ALL
SELECT 'orphaned attendance', COUNT(*) FROM attendance a
 WHERE NOT EXISTS (SELECT 1 FROM lesson_occurrences lo WHERE lo.id = a.lesson_occurrence_id)
UNION ALL
SELECT 'orphaned lesson_notes', COUNT(*) FROM lesson_notes n
 WHERE NOT EXISTS (SELECT 1 FROM lesson_occurrences lo WHERE lo.id = n.lesson_occurrence_id)
UNION ALL
SELECT 'old lessons with zero occurrences left', COUNT(*) FROM lessons l
 WHERE l.created_at < '2026-09-01'
   AND NOT EXISTS (SELECT 1 FROM lesson_occurrences lo WHERE lo.lesson_id = l.id)
ORDER BY t;

-- Sanity check: what's left is only 1 Sep 2026 onward
SELECT MIN(date) AS earliest_remaining_occurrence FROM lesson_occurrences;
