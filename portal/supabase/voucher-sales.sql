-- ============================================================
-- PATHFINDER PORTAL — Gift voucher sales online (migration #48)
--
-- Run each numbered STEP ONE STATEMENT AT A TIME in the Supabase SQL
-- editor, BEFORE deploying the new gift-vouchers.html / voucher-result.html,
-- the updated portal/vouchers.html and the voucher-* Netlify functions.
-- Safe to re-run. Needs migration #43 (gift-vouchers.sql) first.
--
-- How it works
--   * A visitor to /gift-vouchers chooses a voucher, enters who it is from
--     and who it is for (and an optional personal message). The website
--     creates an ORDER (status 'pending') and sends them to eWAY to pay.
--   * When eWAY sends them back, the website asks eWAY directly whether
--     the payment was approved. Only then is the order marked 'paid' and
--     the VOUCHER created in the same register the front desk already uses
--     (gift_vouchers), numbered, and emailed as a PDF to the purchaser
--     (and to the recipient, if the purchaser gave an address).
--
--   voucher_orders   one row per purchase (a payment)          admins read
--   gift_vouchers    + source ('manual' | 'online'), + order_id,
--                    recipient_email may now be empty
--
-- All writes are made by the Netlify functions (service role). Students,
-- teachers and the public have NO access to voucher_orders.
--
-- ⚠ Needs: get_my_role() and the gift_vouchers table.
-- ============================================================


-- ============================================================
-- STEP 1 — orders
--   status: pending   payment started, not yet confirmed by eWAY
--           paid      eWAY approved the right amount; voucher issued
--           failed    eWAY declined / the amount did not match
--           abandoned the buyer never finished (cleaned up by the
--                     scheduled job after eWAY confirms nothing was paid)
--           refunded  refunded in MYeWAY; its voucher is void
-- ============================================================
CREATE TABLE IF NOT EXISTS voucher_orders (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- VO-XXXXXX from an alphabet with no 0/O/1/I/L. Also the invoice
  -- reference eWAY records against the payment.
  order_no            text NOT NULL UNIQUE
                        CHECK (order_no ~ '^VO-[2-9A-HJKMNP-Z]{6}$'),

  voucher_type        text NOT NULL CHECK (char_length(voucher_type) BETWEEN 1 AND 40),   -- e.g. '5-lesson'
  voucher_title       text NOT NULL CHECK (char_length(btrim(voucher_title)) BETWEEN 1 AND 80),   -- e.g. '5-Lesson Voucher'
  subject             text NOT NULL CHECK (char_length(btrim(subject)) BETWEEN 1 AND 120),      -- the headline printed on the voucher
  amount_cents        integer NOT NULL CHECK (amount_cents BETWEEN 100 AND 1000000),

  purchaser_name      text NOT NULL CHECK (char_length(btrim(purchaser_name)) BETWEEN 1 AND 120),
  purchaser_email     text NOT NULL CHECK (char_length(purchaser_email) BETWEEN 3 AND 254),
  recipient_name      text NOT NULL CHECK (char_length(btrim(recipient_name)) BETWEEN 1 AND 120),
  recipient_email     text CHECK (recipient_email IS NULL OR char_length(recipient_email) BETWEEN 3 AND 254),
  message             text CHECK (message IS NULL OR char_length(message) <= 600),

  status              text NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','paid','failed','abandoned','refunded')),
  status_note         text CHECK (status_note IS NULL OR char_length(status_note) <= 500),

  -- eWAY
  eway_access_code    text,
  eway_transaction_id text,
  eway_response_code  text,
  eway_message        text,
  last_checked_at     timestamptz,

  paid_at             timestamptz,

  -- email tracking (stamped by the voucher functions)
  purchaser_emailed_at   timestamptz,
  purchaser_email_error  text,
  purchaser_send_count   integer NOT NULL DEFAULT 0,
  recipient_emailed_at   timestamptz,
  recipient_email_error  text,
  recipient_send_count   integer NOT NULL DEFAULT 0,
  delivery_attempts      integer NOT NULL DEFAULT 0,          -- failed rounds; the scheduled job stops after a few

  ip_hash             text,                                    -- for rate limiting only
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- STEP 2 — indexes (run the four statements one at a time)
-- ============================================================
CREATE INDEX IF NOT EXISTS voucher_orders_status_idx  ON voucher_orders (status, created_at);

CREATE UNIQUE INDEX IF NOT EXISTS voucher_orders_access_code_idx
  ON voucher_orders (eway_access_code) WHERE eway_access_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS voucher_orders_ip_idx      ON voucher_orders (ip_hash, created_at) WHERE ip_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS voucher_orders_created_idx ON voucher_orders (created_at DESC);


-- ============================================================
-- STEP 3 — the register learns about online vouchers
--   * recipient_email may be empty (the purchaser chose not to give one:
--     the voucher goes to the purchaser only). Front-desk vouchers still
--     need one — STEP 3d keeps that rule.
--   * source: 'manual' (issued at the front desk) or 'online'
--   * order_id: the paid order an online voucher came from (one voucher
--     per order, enforced in STEP 3e)
-- Run 3a–3e one at a time.
-- ============================================================
-- 3a
ALTER TABLE gift_vouchers ALTER COLUMN recipient_email DROP NOT NULL;

-- 3b
ALTER TABLE gift_vouchers
  ADD COLUMN IF NOT EXISTS source   text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'online')),
  ADD COLUMN IF NOT EXISTS order_id uuid REFERENCES voucher_orders(id);

-- 3c
ALTER TABLE gift_vouchers DROP CONSTRAINT IF EXISTS gift_vouchers_recipient_email_needed;

-- 3d
ALTER TABLE gift_vouchers ADD CONSTRAINT gift_vouchers_recipient_email_needed
  CHECK (source = 'online' OR (recipient_email IS NOT NULL AND btrim(recipient_email) <> ''));

-- 3e
CREATE UNIQUE INDEX IF NOT EXISTS gift_vouchers_order_idx ON gift_vouchers (order_id) WHERE order_id IS NOT NULL;


-- ============================================================
-- STEP 4 — the register's guard, updated (same rules as before, plus:
-- an empty recipient email is stored as NULL; source and order_id never
-- change). Replaces the function from migration #43; the trigger that
-- calls it stays in place.
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


-- ============================================================
-- STEP 5 — order guard
--   * what was bought (voucher, price, names, message, order number) can
--     never change; a mistake is refunded, not edited. The two email
--     addresses CAN be corrected (to resend to the right place).
--   * paid can only move on to refunded; refunded is final.
--   * going to refunded voids the order's voucher in the same
--     transaction (if it has not already been redeemed).
-- ============================================================
CREATE OR REPLACE FUNCTION voucher_orders_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.subject         := btrim(NEW.subject);
    NEW.purchaser_name  := btrim(NEW.purchaser_name);
    NEW.purchaser_email := lower(btrim(NEW.purchaser_email));
    NEW.recipient_name  := btrim(NEW.recipient_name);
    NEW.recipient_email := nullif(lower(btrim(coalesce(NEW.recipient_email, ''))), '');
    NEW.message         := nullif(btrim(coalesce(NEW.message, '')), '');
    NEW.status          := 'pending';
    NEW.paid_at         := NULL;
    NEW.purchaser_send_count := 0;
    NEW.recipient_send_count := 0;
    NEW.delivery_attempts    := 0;
    NEW.updated_at      := now();
    RETURN NEW;
  END IF;

  IF NEW.order_no       IS DISTINCT FROM OLD.order_no
  OR NEW.voucher_type   IS DISTINCT FROM OLD.voucher_type
  OR NEW.voucher_title  IS DISTINCT FROM OLD.voucher_title
  OR NEW.subject        IS DISTINCT FROM OLD.subject
  OR NEW.amount_cents   IS DISTINCT FROM OLD.amount_cents
  OR NEW.purchaser_name IS DISTINCT FROM OLD.purchaser_name
  OR NEW.recipient_name IS DISTINCT FROM OLD.recipient_name
  OR NEW.message        IS DISTINCT FROM OLD.message
  OR NEW.created_at     IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'order_locked: what was bought cannot be changed — refund the order and sell again';
  END IF;

  NEW.purchaser_email := lower(btrim(NEW.purchaser_email));
  NEW.recipient_email := nullif(lower(btrim(coalesce(NEW.recipient_email, ''))), '');
  NEW.updated_at      := now();

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status = 'refunded' THEN
      RAISE EXCEPTION 'order_locked: a refunded order is final';
    END IF;
    IF OLD.status = 'paid' AND NEW.status <> 'refunded' THEN
      RAISE EXCEPTION 'order_locked: a paid order can only be refunded';
    END IF;
    IF NEW.status = 'paid' AND NEW.paid_at IS NULL THEN
      NEW.paid_at := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION voucher_orders_after_refund()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'refunded' AND OLD.status IS DISTINCT FROM 'refunded' THEN
    UPDATE gift_vouchers
       SET status = 'void', status_note = 'Order ' || NEW.order_no || ' was refunded'
     WHERE order_id = NEW.id AND status = 'issued';
  END IF;
  RETURN NULL;
END;
$$;


-- ============================================================
-- STEP 6 — attach the triggers (run the two statements and the two
-- DROPs one at a time)
-- ============================================================
DROP TRIGGER IF EXISTS voucher_orders_guard_trg ON voucher_orders;

CREATE TRIGGER voucher_orders_guard_trg
  BEFORE INSERT OR UPDATE ON voucher_orders
  FOR EACH ROW EXECUTE FUNCTION voucher_orders_guard();

DROP TRIGGER IF EXISTS voucher_orders_refund_trg ON voucher_orders;

CREATE TRIGGER voucher_orders_refund_trg
  AFTER UPDATE ON voucher_orders
  FOR EACH ROW EXECUTE FUNCTION voucher_orders_after_refund();


-- ============================================================
-- STEP 7 — row-level security: admins read; nobody writes directly
-- ============================================================
ALTER TABLE voucher_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "voucher_orders_admin_select" ON voucher_orders;

CREATE POLICY "voucher_orders_admin_select" ON voucher_orders FOR SELECT TO authenticated
  USING (get_my_role() IN ('superuser', 'admin'));

-- table privileges (run both statements one at a time)
REVOKE ALL ON voucher_orders FROM anon, authenticated;

GRANT SELECT ON voucher_orders TO authenticated;


-- ============================================================
-- STEP 8 — issue the voucher for a paid order (called by the Netlify
-- functions only, never by a browser)
--
-- Atomic and idempotent: of any number of simultaneous or repeated
-- calls for one order, exactly ONE flips it to 'paid' and creates the
-- voucher; every other call returns false and does nothing. That is what
-- stops a double-clicked return page, the reconciliation job and a
-- manual "Check payment" from issuing duplicate vouchers.
--
-- Voucher numbers: PF-XXXX-XXXX from 8 random characters of a 31-character
-- alphabet without 0/O/1/I/L (about 8×10^11 combinations) — not guessable.
-- The purchase date is today's date in Melbourne.
-- ============================================================
CREATE OR REPLACE FUNCTION _new_voucher_no()
RETURNS text
LANGUAGE plpgsql VOLATILE
SET search_path = public
AS $$
DECLARE
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  bytes bytea := decode(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex');
  s text := '';
  i integer;
BEGIN
  FOR i IN 0..7 LOOP
    s := s || substr(alphabet, (get_byte(bytes, i) % 31) + 1, 1);
  END LOOP;
  RETURN 'PF-' || substr(s, 1, 4) || '-' || substr(s, 5, 4);
END;
$$;

CREATE OR REPLACE FUNCTION voucher_issue_order(
  p_order    uuid,
  p_txn      text,
  p_response text,
  p_message  text
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o     voucher_orders%ROWTYPE;
  n     text;
  tries integer := 0;
  done  boolean := false;
BEGIN
  UPDATE voucher_orders
     SET status = 'paid',
         paid_at = now(),
         eway_transaction_id = p_txn,
         eway_response_code  = p_response,
         eway_message        = left(p_message, 300),
         last_checked_at     = now()
   WHERE id = p_order
     AND status IN ('pending','failed','abandoned')
  RETURNING * INTO o;

  IF NOT FOUND THEN
    RETURN false;                                   -- already issued (or refunded)
  END IF;

  WHILE NOT done LOOP
    tries := tries + 1;
    IF tries > 25 THEN RAISE EXCEPTION 'could not generate a unique voucher number'; END IF;
    n := _new_voucher_no();
    INSERT INTO gift_vouchers (
      voucher_no, studio_id, subject, value_amount,
      recipient_name, recipient_email, purchaser_name, purchaser_email, message,
      purchase_date, expires_on, source, order_id
    ) VALUES (
      n, NULL, o.subject, o.amount_cents / 100.0,
      o.recipient_name, o.recipient_email, o.purchaser_name, o.purchaser_email, o.message,
      (now() AT TIME ZONE 'Australia/Melbourne')::date, current_date, 'online', o.id
    )
    ON CONFLICT (voucher_no) DO NOTHING;
    done := FOUND;
  END LOOP;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION voucher_issue_order(uuid, text, text, text) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION _new_voucher_no() FROM PUBLIC, anon, authenticated;


-- ============================================================
-- STEP 9 — verify (run each; expect what the comment says)
-- ============================================================
-- SELECT relname, relrowsecurity FROM pg_class WHERE relname = 'voucher_orders';                       -- true
-- SELECT policyname FROM pg_policies WHERE tablename = 'voucher_orders';                              -- 1 row
-- SELECT tgname FROM pg_trigger WHERE tgname IN ('voucher_orders_guard_trg','voucher_orders_refund_trg'); -- 2 rows
-- SELECT column_name, is_nullable FROM information_schema.columns
--  WHERE table_name = 'gift_vouchers' AND column_name IN ('recipient_email','source','order_id');      -- recipient_email YES; source; order_id
-- SELECT proname FROM pg_proc WHERE proname IN ('voucher_issue_order','_new_voucher_no');              -- 2 rows

-- ------------------------------------------------------------
-- Revert (only if you ever need to remove the feature; this deletes
-- all online voucher orders):
-- ALTER TABLE gift_vouchers DROP CONSTRAINT IF EXISTS gift_vouchers_recipient_email_needed;
-- DROP INDEX IF EXISTS gift_vouchers_order_idx;
-- ALTER TABLE gift_vouchers DROP COLUMN IF EXISTS order_id, DROP COLUMN IF EXISTS source;
-- DROP TABLE IF EXISTS voucher_orders;
-- DROP FUNCTION IF EXISTS voucher_issue_order(uuid, text, text, text);
-- DROP FUNCTION IF EXISTS _new_voucher_no();
-- DROP FUNCTION IF EXISTS voucher_orders_guard();
-- DROP FUNCTION IF EXISTS voucher_orders_after_refund();
-- (Online vouchers already in gift_vouchers keep working; give them a recipient
--  email or void them before restoring NOT NULL on recipient_email.)
-- ------------------------------------------------------------
