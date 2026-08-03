-- ============================================================
-- PATHFINDER PORTAL — Teacher read access to their own students
--
-- Why: teacher access used to be granted via the student_teachers
-- table. Since v0.3, lesson membership lives in lesson_students,
-- so those old policies no longer match anything and teachers
-- see an empty student list.
--
-- These are additive SELECT policies. Postgres combines permissive
-- policies with OR, so existing admin/superuser policies are
-- unaffected.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Students enrolled in this teacher's lessons
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Teacher reads own students" ON students;
CREATE POLICY "Teacher reads own students"
  ON students FOR SELECT
  USING (
    id IN (
      SELECT ls.student_id
        FROM lesson_students ls
        JOIN lessons l ON l.id = ls.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

-- ------------------------------------------------------------
-- 2. Those students' profiles (names)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Teacher reads own student profiles" ON profiles;
CREATE POLICY "Teacher reads own student profiles"
  ON profiles FOR SELECT
  USING (
    id IN (
      SELECT s.user_id
        FROM students s
        JOIN lesson_students ls ON ls.student_id = s.id
        JOIN lessons l          ON l.id = ls.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

-- ------------------------------------------------------------
-- 3. Skill levels — read AND update, so teachers can grade
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Teacher reads own student instruments" ON student_instruments;
CREATE POLICY "Teacher reads own student instruments"
  ON student_instruments FOR SELECT
  USING (
    student_id IN (
      SELECT ls.student_id
        FROM lesson_students ls
        JOIN lessons l ON l.id = ls.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

DROP POLICY IF EXISTS "Teacher updates own student skill levels" ON student_instruments;
CREATE POLICY "Teacher updates own student skill levels"
  ON student_instruments FOR UPDATE
  USING (
    student_id IN (
      SELECT ls.student_id
        FROM lesson_students ls
        JOIN lessons l ON l.id = ls.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

-- ------------------------------------------------------------
-- 4. Verify — should list the four policies above
-- ------------------------------------------------------------
SELECT tablename, policyname, cmd
  FROM pg_policies
 WHERE policyname LIKE 'Teacher %'
 ORDER BY tablename, policyname;
