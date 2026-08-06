-- ============================================================
-- Confirmation emails are sent, not ticked
--
-- The email item on the Trial and Enrolment checklists is
-- automatic: it fires when the lesson is added, because that is
-- the moment the details it needs come into existence.
--
-- sent_at records that it went, so it cannot be sent twice.
-- ============================================================

ALTER TABLE process_items ADD COLUMN IF NOT EXISTS sent_at timestamptz;

-- Existing checklists were created with the email item as a manual
-- tick. Convert them so they behave like every other automatic step.
UPDATE process_items
   SET auto_key = 'email_sent'
 WHERE auto_key IS NULL
   AND label ILIKE 'Confirmation email sent%';

NOTIFY pgrst, 'reload schema';

-- Verify
SELECT column_name FROM information_schema.columns
 WHERE table_name = 'process_items' AND column_name = 'sent_at';

SELECT label, auto_key, COUNT(*)
  FROM process_items GROUP BY label, auto_key ORDER BY label;
