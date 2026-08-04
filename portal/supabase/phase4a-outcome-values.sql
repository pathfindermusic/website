-- ============================================================
-- Contact log outcomes now depend on the contact method
--
-- The original three values ('reached', 'unreachable',
-- 'left_message') did not fit every method — "left a message"
-- makes no sense for an email, and neither did "sent".
--
-- Outcomes offered in the UI:
--   Phone      → spoke / left_message / unreachable
--   SMS        → sent / replied
--   Email      → sent / replied
--   In person  → spoke
--
-- 'reached' is retained so existing entries still read correctly.
-- ============================================================

ALTER TABLE task_notes DROP CONSTRAINT IF EXISTS task_notes_outcome_check;

ALTER TABLE task_notes ADD CONSTRAINT task_notes_outcome_check
  CHECK (outcome IS NULL OR outcome IN (
    'spoke',          -- phone / in person
    'left_message',   -- phone
    'unreachable',    -- phone
    'sent',           -- sms / email
    'replied',        -- sms / email
    'reached'         -- legacy
  ));

-- Verify
SELECT conname, pg_get_constraintdef(oid)
  FROM pg_constraint
 WHERE conrelid = 'task_notes'::regclass
   AND contype = 'c';
