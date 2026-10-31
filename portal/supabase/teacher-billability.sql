-- ============================================================
-- PATHFINDER PORTAL — Teachers' billability report
--
-- Two small tables, both for the SUPERUSER only:
--
--   teacher_employment    one row per teacher: Full-time / Part-time / Casual.
--                         A separate table (not a column on `teachers`) so the
--                         pay arrangement is not visible through the normal
--                         teacher/student API. No row = "not set yet".
--
--   billability_reports   one saved report per reporting period
--                         (period_start..period_end): every teacher's billable
--                         hours for each day (cells, JSON), the employment
--                         types as they were when saved (types, JSON) and the
--                         superuser's free-text notes. Saving the same period
--                         again replaces it.
--
-- ⚠ Run ONE STATEMENT AT A TIME in the Supabase SQL editor, in order.
-- Needs: get_my_role(), teachers. Safe to re-run.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Employment type per teacher
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.teacher_employment (
  teacher_id      uuid PRIMARY KEY REFERENCES public.teachers(id) ON DELETE CASCADE,
  employment_type text NOT NULL CHECK (employment_type IN ('full_time','part_time','casual')),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      uuid DEFAULT auth.uid()
);


-- ------------------------------------------------------------
-- 2. Saved reports
--    cells : { "<teacher_id>": { "YYYY-MM-DD": hours, ... }, ... }
--    types : { "<teacher_id>": "full_time" | "part_time" | "casual" | null }
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.billability_reports (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_start date NOT NULL,
  period_end   date NOT NULL,
  cells        jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(cells) = 'object'),
  types        jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(types) = 'object'),
  notes        text CHECK (notes IS NULL OR char_length(notes) <= 10000),
  saved_by     uuid DEFAULT auth.uid(),
  saved_at     timestamptz NOT NULL DEFAULT now(),
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT billability_period_ok CHECK (period_end >= period_start AND period_end <= period_start + 92),
  CONSTRAINT billability_one_per_period UNIQUE (period_start, period_end)
);


-- ------------------------------------------------------------
-- 3. Stamp who saved it and when, whatever the page sends
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.billability_reports_stamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.saved_by := auth.uid();
  NEW.saved_at := now();
  IF TG_OP = 'UPDATE' THEN NEW.created_at := OLD.created_at; END IF;
  RETURN NEW;
END;
$$;


-- 4. (separate statement)
DROP TRIGGER IF EXISTS billability_reports_stamp_trg ON public.billability_reports;
CREATE TRIGGER billability_reports_stamp_trg
  BEFORE INSERT OR UPDATE ON public.billability_reports
  FOR EACH ROW EXECUTE FUNCTION public.billability_reports_stamp();


-- ------------------------------------------------------------
-- 5. Row Level Security: superuser only (read and write)
-- ------------------------------------------------------------
ALTER TABLE public.teacher_employment  ENABLE ROW LEVEL SECURITY;


-- 6. (separate statement)
ALTER TABLE public.billability_reports ENABLE ROW LEVEL SECURITY;


-- 7. (separate statement)
DROP POLICY IF EXISTS "Superuser manages teacher employment" ON public.teacher_employment;
CREATE POLICY "Superuser manages teacher employment"
  ON public.teacher_employment FOR ALL
  USING (get_my_role() = 'superuser')
  WITH CHECK (get_my_role() = 'superuser');


-- 8. (separate statement)
DROP POLICY IF EXISTS "Superuser manages billability reports" ON public.billability_reports;
CREATE POLICY "Superuser manages billability reports"
  ON public.billability_reports FOR ALL
  USING (get_my_role() = 'superuser')
  WITH CHECK (get_my_role() = 'superuser');


-- ------------------------------------------------------------
-- 9. Privileges (Supabase no longer grants these automatically on new
--    tables). No access for anon. Run the statements one at a time.
-- ------------------------------------------------------------
REVOKE ALL ON public.teacher_employment  FROM PUBLIC, anon;


-- 10. (separate statement)
REVOKE ALL ON public.billability_reports FROM PUBLIC, anon;


-- 11. (separate statement)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teacher_employment  TO authenticated, service_role;


-- 12. (separate statement)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.billability_reports TO authenticated, service_role;


-- ------------------------------------------------------------
-- Verify (optional):
-- SELECT tablename, rowsecurity FROM pg_tables
--  WHERE tablename IN ('teacher_employment','billability_reports');          -- both true
-- SELECT tablename, policyname FROM pg_policies
--  WHERE tablename IN ('teacher_employment','billability_reports');          -- 1 each
--
-- Revert (removes the saved reports and employment types):
-- DROP TABLE IF EXISTS public.billability_reports;
-- DROP FUNCTION IF EXISTS public.billability_reports_stamp();
-- DROP TABLE IF EXISTS public.teacher_employment;
-- ------------------------------------------------------------
