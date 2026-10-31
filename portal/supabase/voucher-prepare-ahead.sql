-- ============================================================
-- Prepare a voucher ahead of its purchase date (Oct 2026)
--
-- Admins often prepare a voucher in advance, with the date the payment is
-- expected, and email it once the money arrives. The register used to
-- refuse any purchase date after tomorrow. It now accepts a date up to a
-- year ahead. Nothing else changes: the same guard function (as last
-- replaced by voucher-sales.sql), one rule different.
--
-- Run the statement below on its own in the Supabase SQL editor, BEFORE
-- deploying the new vouchers.html. Safe to re-run. The trigger that calls
-- the function stays in place, so only this one statement is needed.
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
    NEW.recipient_email := nullif(lower(btrim(coalesce(NEW.recipient_email, ''))), '');
    NEW.purchaser_name  := btrim(NEW.purchaser_name);
    NEW.purchaser_email := nullif(lower(btrim(coalesce(NEW.purchaser_email, ''))), '');
    NEW.message         := nullif(btrim(coalesce(NEW.message, '')), '');
    NEW.status          := 'issued';
    NEW.send_count      := 0;
    NEW.emailed_at      := NULL;
    -- A voucher may be prepared ahead of the day it is paid for (saved,
    -- then emailed once the payment arrives). A year is far enough; more
    -- than that is a typo.
    IF NEW.purchase_date > current_date + 366 THEN
      RAISE EXCEPTION 'purchase_date_future: the purchase date can be at most a year ahead';
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
  OR NEW.source         IS DISTINCT FROM OLD.source
  OR NEW.order_id       IS DISTINCT FROM OLD.order_id
  OR NEW.created_at     IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'voucher_locked: an issued voucher cannot be edited — void it and issue a new one';
  END IF;

  NEW.recipient_email := nullif(lower(btrim(coalesce(NEW.recipient_email, ''))), '');
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

-- ------------------------------------------------------------
-- Verify (optional) — expect the text to contain "366":
-- SELECT prosrc LIKE '%current_date + 366%' FROM pg_proc WHERE proname = 'gift_vouchers_guard';   -- true
--
-- Revert: re-run STEP 4 of voucher-sales.sql.
-- ------------------------------------------------------------
