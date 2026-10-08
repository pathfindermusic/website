-- ============================================================
-- PATHFINDER PORTAL — Concert ticket sales (migration #46)
--
-- Run each numbered STEP ONE STATEMENT AT A TIME in the Supabase SQL
-- editor, BEFORE deploying the new tickets.html / ticket-result.html,
-- portal/ticket-sales.html, the updated events.html and the ticket-*
-- Netlify functions. Safe to re-run.
--
-- How it works
--   * An admin switches "Sell tickets online" on for an event (Events →
--     Edit event) and sets the price (default $15.00).
--   * A visitor to /tickets enters their name, email, the performer they
--     are coming to see and how many tickets they want. The website
--     creates an ORDER (status 'pending') and sends them to eWAY to pay
--     the total.
--   * When eWAY sends them back, the website asks eWAY directly whether
--     the payment was approved. Only then is the order marked 'paid' and
--     one TICKET per seat created (each with its own unique number and
--     QR code) and emailed as a PDF. The browser is never trusted.
--   * On the night, admins look a ticket up (scan the QR or type the
--     number) and tick it off. A ticket can be admitted once only.
--
--   events          + tickets_enabled, ticket_price_cents, ticket_info
--   ticket_orders   one row per purchase (a payment)       admins read
--   tickets         one row per seat                       admins read
--
-- All writes are made by the Netlify functions (service role) or by the
-- check-in function below. Students, teachers and the public have NO
-- access to these tables.
--
-- ⚠ Needs: get_my_role(), get_my_studio_ids() and the events table.
-- ============================================================


-- ============================================================
-- STEP 1 — three new columns on events
-- ============================================================
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS tickets_enabled    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ticket_price_cents integer NOT NULL DEFAULT 1500
                             CHECK (ticket_price_cents BETWEEN 100 AND 100000),
  ADD COLUMN IF NOT EXISTS ticket_info        text
                             CHECK (ticket_info IS NULL OR char_length(ticket_info) <= 500);


-- ============================================================
-- STEP 2 — orders
--   status: pending   payment started, not yet confirmed by eWAY
--           paid      eWAY approved the right amount; tickets issued
--           failed    eWAY declined / the amount did not match
--           abandoned the buyer never finished (cleaned up by the
--                     scheduled job after eWAY confirms nothing was paid)
--           refunded  refunded in MYeWAY; its tickets are void
-- ============================================================
CREATE TABLE IF NOT EXISTS ticket_orders (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- TO-XXXXXX from an alphabet with no 0/O/1/I/L. Also the invoice
  -- reference eWAY records against the payment.
  order_no            text NOT NULL UNIQUE
                        CHECK (order_no ~ '^TO-[2-9A-HJKMNP-Z]{6}$'),

  event_id            uuid NOT NULL REFERENCES events(id),

  purchaser_name      text NOT NULL CHECK (char_length(btrim(purchaser_name)) BETWEEN 1 AND 120),
  purchaser_email     text NOT NULL CHECK (char_length(purchaser_email) BETWEEN 3 AND 254),
  performer_name      text NOT NULL CHECK (char_length(btrim(performer_name)) BETWEEN 1 AND 120),

  quantity            integer NOT NULL CHECK (quantity BETWEEN 1 AND 20),
  unit_price_cents    integer NOT NULL CHECK (unit_price_cents BETWEEN 100 AND 100000),
  total_cents         integer NOT NULL,
  CONSTRAINT ticket_orders_total_matches CHECK (total_cents = quantity * unit_price_cents),

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

  -- email tracking (stamped by the ticket functions)
  emailed_at          timestamptz,
  emailed_to          text,
  email_error         text,
  send_count          integer NOT NULL DEFAULT 0,

  ip_hash             text,                               -- for rate limiting only
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- STEP 3 — tickets (one per seat)
-- ============================================================
CREATE TABLE IF NOT EXISTS tickets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_no   text NOT NULL UNIQUE
                CHECK (ticket_no ~ '^TK-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$'),
  order_id    uuid NOT NULL REFERENCES ticket_orders(id) ON DELETE CASCADE,
  event_id    uuid NOT NULL REFERENCES events(id),
  seq         integer NOT NULL CHECK (seq >= 1),          -- "ticket 2 of 4"
  status      text NOT NULL DEFAULT 'valid' CHECK (status IN ('valid','used','void')),
  used_at     timestamptz,
  used_by     uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, seq)
);


-- ============================================================
-- STEP 4 — indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS ticket_orders_event_idx   ON ticket_orders (event_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ticket_orders_status_idx  ON ticket_orders (status, created_at);

CREATE UNIQUE INDEX IF NOT EXISTS ticket_orders_access_code_idx
  ON ticket_orders (eway_access_code) WHERE eway_access_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS ticket_orders_ip_idx      ON ticket_orders (ip_hash, created_at) WHERE ip_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS tickets_event_idx         ON tickets (event_id);


-- ============================================================
-- STEP 5 — order guard
--   * what was bought (event, quantity, price, order number) can never
--     change; a mistake is refunded, not edited.
--   * paid can only move on to refunded; refunded is final.
--   * going to refunded voids every ticket of the order, in the same
--     transaction, so a refunded seat cannot be admitted.
-- ============================================================
CREATE OR REPLACE FUNCTION ticket_orders_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.purchaser_name  := btrim(NEW.purchaser_name);
    NEW.purchaser_email := lower(btrim(NEW.purchaser_email));
    NEW.performer_name  := btrim(NEW.performer_name);
    NEW.status          := 'pending';
    NEW.paid_at         := NULL;
    NEW.send_count      := 0;
    NEW.updated_at      := now();
    RETURN NEW;
  END IF;

  IF NEW.order_no         IS DISTINCT FROM OLD.order_no
  OR NEW.event_id         IS DISTINCT FROM OLD.event_id
  OR NEW.quantity         IS DISTINCT FROM OLD.quantity
  OR NEW.unit_price_cents IS DISTINCT FROM OLD.unit_price_cents
  OR NEW.total_cents      IS DISTINCT FROM OLD.total_cents
  OR NEW.created_at       IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'order_locked: what was bought cannot be changed — refund the order and sell again';
  END IF;

  NEW.purchaser_name  := btrim(NEW.purchaser_name);
  NEW.purchaser_email := lower(btrim(NEW.purchaser_email));
  NEW.performer_name  := btrim(NEW.performer_name);
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

CREATE OR REPLACE FUNCTION ticket_orders_after_refund()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'refunded' AND OLD.status IS DISTINCT FROM 'refunded' THEN
    UPDATE tickets SET status = 'void' WHERE order_id = NEW.id AND status <> 'void';
  END IF;
  RETURN NULL;
END;
$$;


-- ============================================================
-- STEP 6 — ticket guard: the number, order and seat never change;
-- void is final; used ⇄ valid is how check-in is undone.
-- ============================================================
CREATE OR REPLACE FUNCTION tickets_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.ticket_no IS DISTINCT FROM OLD.ticket_no
  OR NEW.order_id  IS DISTINCT FROM OLD.order_id
  OR NEW.event_id  IS DISTINCT FROM OLD.event_id
  OR NEW.seq       IS DISTINCT FROM OLD.seq THEN
    RAISE EXCEPTION 'ticket_locked: a ticket''s number and order cannot be changed';
  END IF;
  IF OLD.status = 'void' AND NEW.status <> 'void' THEN
    RAISE EXCEPTION 'ticket_locked: a void ticket cannot be reinstated';
  END IF;
  IF NEW.status = 'valid' THEN
    NEW.used_at := NULL;
    NEW.used_by := NULL;
  END IF;
  RETURN NEW;
END;
$$;


-- ============================================================
-- STEP 7 — attach the triggers (run the three statements one at a time)
-- ============================================================
DROP TRIGGER IF EXISTS ticket_orders_guard_trg ON ticket_orders;

CREATE TRIGGER ticket_orders_guard_trg
  BEFORE INSERT OR UPDATE ON ticket_orders
  FOR EACH ROW EXECUTE FUNCTION ticket_orders_guard();

DROP TRIGGER IF EXISTS ticket_orders_refund_trg ON ticket_orders;

CREATE TRIGGER ticket_orders_refund_trg
  AFTER UPDATE ON ticket_orders
  FOR EACH ROW EXECUTE FUNCTION ticket_orders_after_refund();

DROP TRIGGER IF EXISTS tickets_guard_trg ON tickets;

CREATE TRIGGER tickets_guard_trg
  BEFORE UPDATE ON tickets
  FOR EACH ROW EXECUTE FUNCTION tickets_guard();


-- ============================================================
-- STEP 8 — may the caller manage this event's ticket sales?
-- Superusers: any event. Admins: events of their studios (or of all
-- studios). Everyone else: no.
-- ============================================================
CREATE OR REPLACE FUNCTION _can_manage_event_tickets(p_event uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE get_my_role()
    WHEN 'superuser' THEN EXISTS (SELECT 1 FROM events e WHERE e.id = p_event)
    WHEN 'admin' THEN EXISTS (
      SELECT 1 FROM events e
       WHERE e.id = p_event
         AND (e.studio_id IS NULL OR e.studio_id = ANY(get_my_studio_ids())))
    ELSE false
  END;
$$;


-- ============================================================
-- STEP 9 — row-level security: admins read; nobody writes directly
-- ============================================================
ALTER TABLE ticket_orders ENABLE ROW LEVEL SECURITY;

ALTER TABLE tickets       ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ticket_orders_admin_select" ON ticket_orders;

CREATE POLICY "ticket_orders_admin_select" ON ticket_orders FOR SELECT TO authenticated
  USING (_can_manage_event_tickets(event_id));

DROP POLICY IF EXISTS "tickets_admin_select" ON tickets;

CREATE POLICY "tickets_admin_select" ON tickets FOR SELECT TO authenticated
  USING (_can_manage_event_tickets(event_id));


-- ============================================================
-- STEP 10 — table privileges (run the three statements one at a time)
-- ============================================================
REVOKE ALL ON ticket_orders FROM anon, authenticated;

REVOKE ALL ON tickets FROM anon, authenticated;

GRANT SELECT ON ticket_orders, tickets TO authenticated;


-- ============================================================
-- STEP 11 — issue the tickets for a paid order (called by the Netlify
-- functions only, never by a browser)
--
-- Atomic and idempotent: of any number of simultaneous or repeated
-- calls for one order, exactly ONE flips it to 'paid' and creates the
-- tickets; every other call returns false and does nothing. That is
-- what stops a double-clicked "return" page, the reconciliation job
-- and a manual "Check payment" from issuing duplicate tickets.
--
-- Ticket numbers: TK-XXXX-XXXX from 8 random characters of a 31-character
-- alphabet without 0/O/1/I/L (about 8×10^11 combinations) — not guessable.
-- ============================================================
CREATE OR REPLACE FUNCTION _new_ticket_no()
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
  RETURN 'TK-' || substr(s, 1, 4) || '-' || substr(s, 5, 4);
END;
$$;

CREATE OR REPLACE FUNCTION ticket_issue_order(
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
  o   ticket_orders%ROWTYPE;
  n   text;
  i   integer;
  tries integer;
  done boolean;
BEGIN
  UPDATE ticket_orders
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

  FOR i IN 1..o.quantity LOOP
    tries := 0;
    done  := false;
    WHILE NOT done LOOP
      tries := tries + 1;
      IF tries > 25 THEN RAISE EXCEPTION 'could not generate a unique ticket number'; END IF;
      n := _new_ticket_no();
      INSERT INTO tickets (ticket_no, order_id, event_id, seq)
      VALUES (n, o.id, o.event_id, i)
      ON CONFLICT (ticket_no) DO NOTHING;
      done := FOUND;
    END LOOP;
  END LOOP;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION ticket_issue_order(uuid, text, text, text) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION _new_ticket_no() FROM PUBLIC, anon, authenticated;


-- ============================================================
-- STEP 12 — door check-in (called from the Ticket sales page)
--
-- ticket_check_in(text, action)
--   action 'lookup' (default)  show the ticket, change nothing
--          'use'               admit it — once only, even if two phones
--                              scan at the same instant
--          'undo'              un-tick a ticket admitted by mistake
--
-- The text may be a ticket number (any case, dashes optional) or the
-- whole address a QR code holds — the number is found inside it.
--
-- Returns json: { result, ticket, order, event, seats }
--   result: ok | undone | lookup | already_used | void | not_found
--           | not_allowed | bad_action
-- ============================================================
CREATE OR REPLACE FUNCTION ticket_check_in(p_ticket text, p_action text DEFAULT 'lookup')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r   text := get_my_role();
  raw text;
  m   text[];
  no  text;
  t   tickets%ROWTYPE;
  tid uuid;
  o   ticket_orders%ROWTYPE;
  ev  events%ROWTYPE;
  res text;
  n   integer;
BEGIN
  IF r NOT IN ('admin','superuser') THEN
    RETURN jsonb_build_object('result', 'not_allowed');
  END IF;
  IF p_action NOT IN ('lookup','use','undo') THEN
    RETURN jsonb_build_object('result', 'bad_action');
  END IF;

  raw := upper(coalesce(p_ticket, ''));
  m := regexp_match(raw, 'TK-?([2-9A-HJKMNP-Z]{4})-?([2-9A-HJKMNP-Z]{4})');
  IF m IS NULL THEN
    RETURN jsonb_build_object('result', 'not_found');
  END IF;
  no := 'TK-' || m[1] || '-' || m[2];

  SELECT * INTO t FROM tickets WHERE ticket_no = no;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('result', 'not_found');
  END IF;
  IF NOT _can_manage_event_tickets(t.event_id) THEN
    RETURN jsonb_build_object('result', 'not_allowed');
  END IF;
  tid := t.id;

  res := 'lookup';
  IF p_action = 'use' THEN
    UPDATE tickets SET status = 'used', used_at = now(), used_by = auth.uid()
     WHERE id = tid AND status = 'valid'
    RETURNING * INTO t;
    IF FOUND THEN
      res := 'ok';
    ELSE
      SELECT * INTO t FROM tickets WHERE id = tid;
      res := CASE t.status WHEN 'void' THEN 'void' ELSE 'already_used' END;
    END IF;
  ELSIF p_action = 'undo' THEN
    UPDATE tickets SET status = 'valid'
     WHERE id = tid AND status = 'used'
    RETURNING * INTO t;
    IF FOUND THEN
      res := 'undone';
    ELSE
      SELECT * INTO t FROM tickets WHERE id = tid;
    END IF;
  ELSIF t.status = 'void' THEN
    res := 'void';
  END IF;

  SELECT * INTO o  FROM ticket_orders WHERE id = t.order_id;
  SELECT * INTO ev FROM events        WHERE id = t.event_id;
  SELECT count(*) FILTER (WHERE status = 'used') INTO n FROM tickets WHERE order_id = t.order_id;

  RETURN jsonb_build_object(
    'result', res,
    'ticket', jsonb_build_object(
      'ticket_no', t.ticket_no, 'seq', t.seq, 'status', t.status, 'used_at', t.used_at),
    'order', jsonb_build_object(
      'order_no', o.order_no, 'purchaser_name', o.purchaser_name,
      'performer_name', o.performer_name, 'quantity', o.quantity, 'status', o.status),
    'event', jsonb_build_object(
      'id', ev.id, 'name', ev.name, 'event_date', ev.event_date),
    'seats_used', n
  );
END;
$$;

REVOKE ALL ON FUNCTION ticket_check_in(text, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION ticket_check_in(text, text) TO authenticated;


-- ============================================================
-- STEP 13 — verify (run each; expect what the comment says)
-- ============================================================
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'events' AND column_name IN ('tickets_enabled','ticket_price_cents','ticket_info');  -- 3 rows
-- SELECT relname, relrowsecurity FROM pg_class WHERE relname IN ('ticket_orders','tickets');       -- both true
-- SELECT policyname FROM pg_policies WHERE tablename IN ('ticket_orders','tickets');               -- 2 rows
-- SELECT tgname FROM pg_trigger WHERE tgname IN
--   ('ticket_orders_guard_trg','ticket_orders_refund_trg','tickets_guard_trg');                    -- 3 rows

-- ------------------------------------------------------------
-- Revert (only if you ever need to remove the feature; this deletes
-- all ticket orders and tickets):
-- DROP TABLE IF EXISTS tickets;
-- DROP TABLE IF EXISTS ticket_orders;
-- DROP FUNCTION IF EXISTS ticket_check_in(text, text);
-- DROP FUNCTION IF EXISTS ticket_issue_order(uuid, text, text, text);
-- DROP FUNCTION IF EXISTS _new_ticket_no();
-- DROP FUNCTION IF EXISTS _can_manage_event_tickets(uuid);
-- DROP FUNCTION IF EXISTS ticket_orders_guard();
-- DROP FUNCTION IF EXISTS ticket_orders_after_refund();
-- DROP FUNCTION IF EXISTS tickets_guard();
-- ALTER TABLE events DROP COLUMN IF EXISTS tickets_enabled, DROP COLUMN IF EXISTS ticket_price_cents, DROP COLUMN IF EXISTS ticket_info;
-- ------------------------------------------------------------
