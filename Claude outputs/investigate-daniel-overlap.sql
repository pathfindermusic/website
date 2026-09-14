-- Investigating Daniel Vu's two overlapping weekly lessons:
--   Group,   17:30-18:30 (60 min) — lesson_id 3f5dbd18-33ca-4ea4-82b8-03086c9e03ec
--   Private, 18:00-18:30 (30 min) — lesson_id d2a91279-4bf3-4638-b326-207878f6369f
-- Read-only SELECTs — safe to run.

-- 1. Full lesson records — when each started, its recurrence shape, notes
SELECT id, instrument, lesson_type, day_of_week, start_time, duration_mins,
       recurrence_type, recurrence_start, recurrence_count, recurrence_end,
       frequency, status, series_notes, created_at, updated_at
  FROM lessons
 WHERE id IN ('3f5dbd18-33ca-4ea4-82b8-03086c9e03ec','d2a91279-4bf3-4638-b326-207878f6369f')
 ORDER BY created_at;

-- 2. Who's on each roster
SELECT ls.lesson_id, p.first_name || ' ' || p.last_name AS student_name,
       ls.added_for_occurrence_id, ls.joined_at
  FROM lesson_students ls
  JOIN students s ON s.id = ls.student_id
  JOIN profiles p ON p.id = s.user_id
 WHERE ls.lesson_id IN ('3f5dbd18-33ca-4ea4-82b8-03086c9e03ec','d2a91279-4bf3-4638-b326-207878f6369f')
 ORDER BY ls.lesson_id, p.first_name;

-- 3. Every upcoming Monday where BOTH have a live ('scheduled') occurrence
--    — i.e. how often this collision actually bites in practice.
SELECT lo.date,
       COUNT(*) FILTER (WHERE lo.lesson_id = '3f5dbd18-33ca-4ea4-82b8-03086c9e03ec' AND lo.status = 'scheduled') AS group_scheduled,
       COUNT(*) FILTER (WHERE lo.lesson_id = 'd2a91279-4bf3-4638-b326-207878f6369f' AND lo.status = 'scheduled') AS private_scheduled
  FROM lesson_occurrences lo
 WHERE lo.lesson_id IN ('3f5dbd18-33ca-4ea4-82b8-03086c9e03ec','d2a91279-4bf3-4638-b326-207878f6369f')
   AND lo.date >= CURRENT_DATE
 GROUP BY lo.date
HAVING COUNT(*) FILTER (WHERE lo.lesson_id = '3f5dbd18-33ca-4ea4-82b8-03086c9e03ec' AND lo.status = 'scheduled') > 0
   AND COUNT(*) FILTER (WHERE lo.lesson_id = 'd2a91279-4bf3-4638-b326-207878f6369f' AND lo.status = 'scheduled') > 0
 ORDER BY lo.date;
