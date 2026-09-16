-- ============================================================
-- PATHFINDER PORTAL — Phase 6d: discard a teacher-added artefact
--
-- Admins reviewing pending teacher-added artefacts (phase6c) could
-- only Approve one — there was no way to say "not maintaining this
-- one" and have it stop showing up in Pending review every time.
--
-- Adds bok_artefacts.is_discarded, a state distinct from is_active:
--   * pending   → is_custom=true,  is_active=false, is_discarded=false
--   * approved  → is_custom=true,  is_active=true,  is_discarded=false
--   * discarded → is_custom=true,  is_active=false, is_discarded=true
-- A discarded item is never deleted — a teacher may already have used
-- it in a real lesson before an admin ever reviewed it (the note
-- picker offers a teacher's own pending items straight away), and
-- phase6b's history policy depends on the row still existing so that
-- lesson's materials list keeps working. It just drops out of the
-- Pending queue and behaves like a retired item — reversible from
-- "Show retired" if an admin changes their mind.
--
-- No RLS change needed: "Admins manage artefacts" (FOR ALL, from
-- phase6-bok-grading.sql) already covers writing the new column, and
-- the SELECT policy from phase6b/6c keys off is_active and lesson
-- history, not this new field, so it's unaffected either way.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. New column
-- ------------------------------------------------------------
ALTER TABLE bok_artefacts
  ADD COLUMN IF NOT EXISTS is_discarded boolean NOT NULL DEFAULT false;


-- ------------------------------------------------------------
-- 2. Tell PostgREST about the new column.
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY
-- ============================================================
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'bok_artefacts' AND column_name = 'is_discarded';
