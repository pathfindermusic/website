-- ============================================================
-- PATHFINDER PORTAL — Supabase security lints
--
-- Three ERROR-level findings:
--   1. zoho_leads_import has no RLS and is exposed via PostgREST
--   2. schedule_view runs as owner, bypassing RLS
--   3. student_schedule_view, likewise
--
-- (1) is a leftover and is dealt with here.
-- (2) and (3) need read policies on the underlying tables first —
--     see phase5-view-rls.sql. Do NOT flip the views to
--     security_invoker before those exist, or every dashboard
--     goes blank.
--
-- ⚠ Run one statement at a time and read each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. What is actually in the staging table?
--    It should have been dropped after the Zoho import. If it
--    holds real contact details, they are sitting on an endpoint
--    reachable with the anon key that ships in the browser.
-- ------------------------------------------------------------
SELECT COUNT(*) AS rows_held FROM zoho_leads_import;

SELECT * FROM zoho_leads_import LIMIT 5;


-- ------------------------------------------------------------
-- 2. Drop it. It is a staging table — the import is finished and
--    zoho-migration.sql recreates it when the real import runs.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS zoho_leads_import;


-- ------------------------------------------------------------
-- If you would rather keep it for now, lock it instead. With RLS
-- on and no policy, nothing can read it except the service role.
-- ------------------------------------------------------------
-- ALTER TABLE zoho_leads_import ENABLE ROW LEVEL SECURITY;


-- ------------------------------------------------------------
-- 3. Anything else exposed without RLS? Should return no rows.
-- ------------------------------------------------------------
SELECT c.relname AS table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND NOT c.relrowsecurity
 ORDER BY c.relname;
