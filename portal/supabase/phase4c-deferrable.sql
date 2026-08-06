-- ============================================================
-- Only some checklist items are worth deferring to a task
--
-- Admins prefer a light checklist: tick and move on. Raising a
-- task for "explained the cancellation policies" — which happens
-- on the call — is heavier than the work itself.
--
-- Tasks are reserved for external systems, where a real blockage
-- can occur: Xero and eWay.
--
-- Note: the column is `can_defer`, not `deferrable` — the latter
-- is a reserved word in Postgres (a constraint attribute).
-- ============================================================

ALTER TABLE process_items
  ADD COLUMN IF NOT EXISTS can_defer boolean NOT NULL DEFAULT false;

-- Apply to checklists that already exist
UPDATE process_items
   SET can_defer = true
 WHERE auto_key IS NULL
   AND (label ILIKE '%Xero%' OR label ILIKE '%eWay%');

UPDATE process_items
   SET can_defer = false
 WHERE auto_key IS NULL
   AND label NOT ILIKE '%Xero%'
   AND label NOT ILIKE '%eWay%';

NOTIFY pgrst, 'reload schema';

-- Verify
SELECT sp.process_type, pi.label, pi.auto_key, pi.can_defer
  FROM process_items pi
  JOIN student_processes sp ON sp.id = pi.process_id
 ORDER BY sp.process_type, pi.item_order;
