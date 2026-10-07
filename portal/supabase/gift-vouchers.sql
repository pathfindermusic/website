-- ============================================================
-- Portal Gift Vouchers (migration #43)
--
-- Run each numbered STEP one statement at a time in the Supabase SQL
-- editor, BEFORE deploying vouchers.html / voucher-pdf.js / the
-- send-voucher function. Safe to re-run.
--
-- A voucher is issued by an admin at the front desk and emailed to the
-- recipient as a PDF. This table is the register: one row per voucher,
-- so a voucher can be looked up by its number, resent, redeemed or
-- voided later.
--
-- Access: admins and superusers only (read, create, update). There is
-- no delete — a mistake is VOIDED, so the number stays on record and
-- can never be honoured by accident. The Netlify function that sends
-- the email uses the service role (bypasses RLS) to stamp emailed_at.
-- ============================================================

-- ============================================================
-- STEP 1 — the table
-- ============================================================
CREATE TABLE IF NOT EXISTS gift_vouchers (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- PF-XXXX-XXXX from an alphabet with no 0/O/1/I/L. Generated in the
  -- browser (so the preview shows the real number) and kept unique here.
  voucher_no           text NOT NULL UNIQUE
                         CHECK (voucher_no ~ '^PF-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$'),

  studio_id            uuid REFERENCES studios(id),      -- issuing studio (sender + BCC)

  subject              text NOT NULL
                         CHECK (char_length(btrim(subject)) BETWEEN 1 AND 120),
  value_amount         numeric(10,2) CHECK (value_amount IS NULL OR value_amount >= 0),

  recipient_name       text NOT NULL
                         CHECK (char_length(btrim(recipient_name)) BETWEEN 1 AND 120),
  recipient_email      text NOT NULL CHECK (char_length(recipient_email) <= 254),
  recipient_student_id uuid REFERENCES students(id) ON DELETE SET NULL,

  purchaser_name       text NOT NULL
                         CHECK (char_length(btrim(purchaser_name)) BETWEEN 1 AND 120),
  purchaser_email      text CHECK (purchaser_email IS NULL OR char_length(purchaser_email) <= 254),

  message              text CHECK (message IS NULL OR char_length(message) <= 600),

  purchase_date        date NOT NULL DEFAULT current_date,
  expires_on           date NOT NULL,                    -- purchase_date + 1 year (set by trigger)

  status               text NOT NULL DEFAULT 'issued'
                         CHECK (status IN ('issued', 'redeemed', 'void')),
  status_changed_at    timestamptz,
  status_note          text CHECK (status_note IS NULL OR char_length(status_note) <= 500),

  -- email tracking (stamped by the send-voucher function)
  emailed_at           timestamptz,
  emailed_to           text,
  email_error          text,
  send_count           integer NOT NULL DEFAULT 0,

  created_by           uuid DEFAULT auth.uid(),
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gift_vouchers_created_idx ON gift_vouchers (created_at DESC);
CREATE INDEX IF NOT EXISTS gift_vouchers_status_idx  ON gift_vouchers (status);


-- ============================================================
-- STEP 2 — insert/update guard
--   insert : trims text, forces status 'issued', sets expires_on to
--            exactly one year after purchase_date (29 Feb → 28 Feb), and
--            refuses a purchase date in the future.
--   update : what the PDF printed can never change afterwards — the
--            number, subject, names, message, value and dates are
--            frozen. Only contact emails, status and the email-tracking
--            columns may change. Wrong details → void and reissue.
-- ============================================================
CREATE OR REPLACE FUNCTION gift_vouchers_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.subject         := btrim(NEW.subject);
    NEW.recipient_name  := btrim(NEW.recipient_name);
    NEW.recipient_email := lower(btrim(NEW.recipient_email));
    NEW.purchaser_name  := btrim(NEW.purchaser_name);
    NEW.purchaser_email := nullif(lower(btrim(coalesce(NEW.purchaser_email, ''))), '');
    NEW.message         := nullif(btrim(coalesce(NEW.message, '')), '');
    NEW.status          := 'issued';
    NEW.send_count      := 0;
    NEW.emailed_at      := NULL;
    IF NEW.purchase_date > current_date + 1 THEN
      RAISE EXCEPTION 'purchase_date_future: the purchase date cannot be in the future';
    END IF;
    NEW.expires_on := (NEW.purchase_date + interval '1 year')::date;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF NEW.voucher_no     IS DISTINCT FROM OLD.voucher_no
  OR NEW.subject        IS DISTINCT FROM OLD.subject
  OR NEW.value_amount   IS DISTINCT FROM OLD.value_amount
  OR NEW.recipient_name IS DISTINCT FROM OLD.recipient_name
  OR NEW.purchaser_name IS DISTINCT FROM OLD.purchaser_name
  OR NEW.message        IS DISTINCT FROM OLD.message
  OR NEW.purchase_date  IS DISTINCT FROM OLD.purchase_date
  OR NEW.expires_on     IS DISTINCT FROM OLD.expires_on
  OR NEW.studio_id      IS DISTINCT FROM OLD.studio_id
  OR NEW.created_at     IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'voucher_locked: an issued voucher cannot be edited — void it and issue a new one';
  END IF;

  NEW.recipient_email := lower(btrim(NEW.recipient_email));
  NEW.purchaser_email := nullif(lower(btrim(coalesce(NEW.purchaser_email, ''))), '');

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status = 'void' THEN
      RAISE EXCEPTION 'voucher_locked: a voided voucher cannot be reinstated — issue a new one';
    END IF;
    NEW.status_changed_at := now();
  END IF;
  RETURN NEW;
END;
$$;


-- ============================================================
-- STEP 3 — attach the trigger
-- ============================================================
DROP TRIGGER IF EXISTS gift_vouchers_guard_trg ON gift_vouchers;

CREATE TRIGGER gift_vouchers_guard_trg
  BEFORE INSERT OR UPDATE ON gift_vouchers
  FOR EACH ROW EXECUTE FUNCTION gift_vouchers_guard();


-- ============================================================
-- STEP 4 — row-level security: admins and superusers only
-- ============================================================
ALTER TABLE gift_vouchers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "gift_vouchers_admin_select" ON gift_vouchers;

CREATE POLICY "gift_vouchers_admin_select" ON gift_vouchers FOR SELECT TO authenticated
  USING (get_my_role() IN ('superuser', 'admin'));

DROP POLICY IF EXISTS "gift_vouchers_admin_insert" ON gift_vouchers;

CREATE POLICY "gift_vouchers_admin_insert" ON gift_vouchers FOR INSERT TO authenticated
  WITH CHECK (get_my_role() IN ('superuser', 'admin'));

DROP POLICY IF EXISTS "gift_vouchers_admin_update" ON gift_vouchers;

CREATE POLICY "gift_vouchers_admin_update" ON gift_vouchers FOR UPDATE TO authenticated
  USING (get_my_role() IN ('superuser', 'admin'))
  WITH CHECK (get_my_role() IN ('superuser', 'admin'));


-- ============================================================
-- STEP 5 — table privileges: signed-in users may read/insert/update
-- (RLS then limits that to admins); no delete, no truncate, no anonymous
-- access. Run the two statements one at a time.
-- ============================================================
REVOKE ALL ON gift_vouchers FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE ON gift_vouchers TO authenticated;


-- ============================================================
-- STEP 6 — verify (run each; expect what the comment says)
-- ============================================================
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'gift_vouchers';          -- true
-- SELECT policyname FROM pg_policies WHERE tablename = 'gift_vouchers';         -- 3 rows
-- SELECT tgname FROM pg_trigger WHERE tgname = 'gift_vouchers_guard_trg';       -- 1 row

-- ------------------------------------------------------------
-- Revert (only if you ever need to remove the feature):
-- DROP TABLE IF EXISTS gift_vouchers;
-- DROP FUNCTION IF EXISTS gift_vouchers_guard();
-- ------------------------------------------------------------
