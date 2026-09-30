-- ============================================================
-- PATHFINDER PORTAL — lesson credits
--
-- Tracks a per-student ledger of lesson credits: a student banks
-- one when a lesson doesn't happen through no fault of their own
-- (teacher cancelled — sick or public holiday — or the student
-- gave sufficient notice), and spends one when a makeup lesson is
-- booked against it.
--
-- Deliberately an append-only ledger, not a running balance column
-- on `students`. A balance is just SUM(delta) for a student — the
-- same "compute state from history" approach already used for
-- schedule_view's fully_marked, rather than a cached counter that
-- can drift out of sync with the events that produced it. It also
-- means every movement carries its own date, note and initiator
-- forever, which a running counter would throw away.
--
-- No UPDATE/DELETE policy is added on purpose. A mistaken credit
-- is corrected with an offsetting manual_adjustment row, never by
-- editing or removing the original — the log stays a true history
-- of who did what and when, which is the whole point of it.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The ledger table
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lesson_credit_movements (
  id                 uuid NOT NULL DEFAULT gen_random_uuid(),
  student_id         uuid NOT NULL REFERENCES students(id),
  delta              integer NOT NULL CHECK (delta <> 0),
  reason             text NOT NULL CHECK (reason = ANY (ARRAY[
                       'teacher_cancelled', -- teacher unavailable, or a public holiday closure
                       'student_notice',    -- student gave sufficient notice of an absence
                       'makeup_booked',     -- a credit spent booking a makeup lesson
                       'manual_adjustment'  -- correction, or anything outside the automatic triggers
                     ]::text[])),
  note               text,
  occurrence_id      uuid REFERENCES lesson_occurrences(id),
  initiated_by       uuid REFERENCES profiles(id),
  -- Snapshotted at the time, not looked up from profiles.role live —
  -- a role can change later (or the profile could be deactivated),
  -- and the log should still say who acted and in what capacity.
  initiated_by_role  text NOT NULL CHECK (initiated_by_role = ANY (ARRAY['admin','superuser','teacher']::text[])),
  created_at         timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT lesson_credit_movements_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS lesson_credit_movements_student_idx
  ON lesson_credit_movements (student_id);

CREATE INDEX IF NOT EXISTS lesson_credit_movements_occurrence_idx
  ON lesson_credit_movements (occurrence_id);

ALTER TABLE lesson_credit_movements ENABLE ROW LEVEL SECURITY;


-- ------------------------------------------------------------
-- 2. Balance view — current balance and last movement, per
--    student. security_invoker so RLS on the table underneath
--    still applies to whoever queries the view (the same lint
--    schedule_view and student_schedule_view already needed
--    fixed for, in phase5-view-rls.sql / phase5-makeup-lessons.sql).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW student_credit_balances AS
SELECT
  student_id,
  SUM(delta)                                         AS balance,
  MAX(created_at)                                     AS last_movement_at,
  (ARRAY_AGG(note   ORDER BY created_at DESC))[1]     AS last_movement_note,
  (ARRAY_AGG(reason ORDER BY created_at DESC))[1]     AS last_movement_reason
FROM lesson_credit_movements
GROUP BY student_id;

ALTER VIEW student_credit_balances SET (security_invoker = on);


-- ------------------------------------------------------------
-- 3. Which students does the current teacher teach? — merges
--    their own roster with anything they're covering as a
--    substitute. SECURITY DEFINER STABLE, same pattern as
--    my_owned_occurrence_ids() (attendance-owner-check-perf-fix.sql)
--    and my_covered_student_ids() (phase5-substitute-access.sql) —
--    a helper function so a policy reading this never pays the
--    full RLS cost of every policy on lesson_students/lessons for
--    every row it scans.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_teaching_student_ids()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY(
    SELECT ls.student_id
      FROM lesson_students ls
      JOIN lessons l ON l.id = ls.lesson_id
     WHERE l.teacher_id = get_my_teacher_id()
    UNION
    SELECT unnest(my_covered_student_ids())
  ), ARRAY[]::uuid[]);
$$;


-- ------------------------------------------------------------
-- 4. Policies
--
--   admin/superuser — full access, per the admin dashboard's
--     Credits report and manual-adjustment action.
--   teacher — can read and grant/spend credits only for their
--     own students (regular roster or a lesson they're covering),
--     and only ever attributes the row to themselves.
--   student/parent — no policy, by design (Q4 answer: admin/
--     superuser visibility only for now).
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "admin_manage_credit_movements" ON lesson_credit_movements;
CREATE POLICY "admin_manage_credit_movements"
  ON lesson_credit_movements FOR ALL
  USING      (get_my_role() IN ('admin','superuser'))
  WITH CHECK (get_my_role() IN ('admin','superuser'));

DROP POLICY IF EXISTS "teacher_reads_own_student_credit_movements" ON lesson_credit_movements;
CREATE POLICY "teacher_reads_own_student_credit_movements"
  ON lesson_credit_movements FOR SELECT
  USING (student_id = ANY(my_teaching_student_ids()));

DROP POLICY IF EXISTS "teacher_grants_own_student_credit" ON lesson_credit_movements;
CREATE POLICY "teacher_grants_own_student_credit"
  ON lesson_credit_movements FOR INSERT
  WITH CHECK (
    student_id = ANY(my_teaching_student_ids())
    AND initiated_by = auth.uid()
    AND initiated_by_role = 'teacher'
  );

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================
SELECT table_name FROM information_schema.tables
 WHERE table_name = 'lesson_credit_movements';

SELECT policyname, cmd, qual, with_check FROM pg_policies
 WHERE tablename = 'lesson_credit_movements';

SELECT c.relname,
       COALESCE((SELECT option_value FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'security_invoker'), 'off') AS security_invoker
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'student_credit_balances';

-- Should return zero rows both times (empty ledger so far)
SELECT * FROM lesson_credit_movements LIMIT 5;
SELECT * FROM student_credit_balances LIMIT 5;
