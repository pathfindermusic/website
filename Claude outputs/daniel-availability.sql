-- Daniel Vu's Monday availability at Ringwood, so I can suggest a
-- genuinely free slot for Justin's makeup lesson. Read-only.
SELECT ta.day_of_week, ta.start_time, ta.end_time
  FROM teacher_availability ta
  JOIN teachers t ON t.id = ta.teacher_id
  JOIN profiles p ON p.id = t.user_id
  JOIN studios st ON st.id = ta.studio_id
 WHERE p.first_name = 'Daniel' AND p.last_name = 'Vu'
   AND st.name = 'Ringwood'
   AND ta.day_of_week = 1
 ORDER BY ta.start_time;
