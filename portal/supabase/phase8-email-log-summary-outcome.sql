-- ============================================================
-- PATHFINDER PORTAL — record whether the studio summary email
-- actually sent
--
-- Traced from: a teacher's lessons were cancelled for illness,
-- students got their emails (confirmed in Resend), but the
-- studio's summary copy never arrived and there was no way to
-- tell why — not even after the fact, from this table.
--
-- send-email.js already computes `summarySent` (true/false) for
-- every multi-recipient send, and swallows the error if the
-- summary's own Resend call fails, so the student send still
-- succeeds. But email_log's `status`/`error` only ever reflected
-- the STUDENT batch — a send where every student email went out
-- fine but the separate studio summary silently failed still
-- logged as status='sent', error=null, with nothing to tell the
-- two apart. That's the gap this closes.
--
-- Two new nullable columns, no RLS change needed (the existing
-- "admins read reminder log"-style policy on email_log already
-- covers whatever it's extended with).
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================

ALTER TABLE email_log
  ADD COLUMN IF NOT EXISTS summary_sent  boolean,
  ADD COLUMN IF NOT EXISTS summary_error text;

-- NULL means "no summary was expected this send" (a single
-- recipient, where the studio copy rides along as a BCC on the
-- student's own email instead of a separate send — see
-- send-email.js's comment on that). true/false only apply once
-- there was more than one recipient and a bcc address to send to.

COMMENT ON COLUMN email_log.summary_sent IS
  'Only meaningful when recipient_count > 1 and bcc is set: whether the separate studio summary email (not the student batch) was accepted by Resend. NULL = no summary was attempted (single recipient, or no studio email on file).';
COMMENT ON COLUMN email_log.summary_error IS
  'The Resend error/status text if summary_sent is false, so a failure is diagnosable after the fact instead of only visible in that moment''s toast.';

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY
-- ============================================================
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'email_log'
   AND column_name IN ('summary_sent', 'summary_error')
 ORDER BY column_name;
