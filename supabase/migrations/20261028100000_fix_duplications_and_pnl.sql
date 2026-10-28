-- Migration: 20261028100000_fix_duplications_and_pnl.sql
-- Goal:
--   1. Unify payments & transactions and fix v_merchant_pnl_summary (join payments, snapshot COGS, group by IST business_date).
--   2. Unify order_events & order_timeline (make order_timeline a view over order_events preserving actor & comments).
--   3. Add business_date (Asia/Kolkata IST) to stock_holds and fix all SQL functions/views to use IST instead of UTC CURRENT_DATE.
--   4. Fix stale-update bugs on sync triggers (product_variants, daily_stock, products, etc.).
--   5. Fix trg_order_paid customer lifetime stats trigger to prevent double-counting and decrement on refund.
--   6. Enable RLS on all remaining public tables and drop redundant duplicate indexes.

-- =============================================================================
-- 1. INDIA TIMEZONE (Asia/Kolkata) DEFAULTS & STOCK_HOLDS BUSINESS_DATE
-- =============================================================================

ALTER TABLE orders
    ALTER COLUMN business_date SET DEFAULT (NOW() AT TIME ZONE 'Asia/Kolkata')::date;

ALTER TABLE daily_stock
    ALTER COLUMN business_date SET DEFAULT (NOW() AT TIME ZONE 'Asia/Kolkata')::date,
    ALTER COLUMN stock_date SET DEFAULT (NOW() AT TIME ZONE 'Asia/Kolkata')::date;

ALTER TABLE daily_closing_reports
    ALTER COLUMN report_date SET DEFAULT (NOW() AT TIME ZONE 'Asia/Kolkata')::date;

ALTER TABLE stock_holds
    ADD COLUMN IF NOT EXISTS business_date DATE NOT NULL DEFAULT (NOW() AT TIME ZONE 'Asia/Kolkata')::date;

-- Backfill stock_holds.business_date from linked orders if any exist
UPDATE stock_holds sh
SET business_date = o.business_date
FROM orders o
WHERE sh.order_id = o.id
  AND sh.business_date IS DISTINCT FROM o.business_date;

-- =============================================================================
-- 2. FIX STALE-UPDATE SYNC TRIGGERS ON CATALOG, STOCK & CORE TABLES
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_sync_variant_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.merchant_id IS NULL THEN
        SELECT merchant_id INTO NEW.merchant_id FROM products WHERE id = NEW.product_id;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.name IS NOT NULL AND (NEW.variant_name IS NULL OR NEW.variant_name = '') THEN
            NEW.variant_name := NEW.name;
        ELSIF NEW.variant_name IS NOT NULL AND (NEW.name IS NULL OR NEW.name = '') THEN
            NEW.name := NEW.variant_name;
        END IF;

        IF NEW.price_minor > 0 AND (NEW.selling_price_minor IS NULL OR NEW.selling_price_minor = 0) THEN
            NEW.selling_price_minor := NEW.price_minor;
        ELSIF NEW.selling_price_minor > 0 AND (NEW.price_minor IS NULL OR NEW.price_minor = 0) THEN
            NEW.price_minor := NEW.selling_price_minor::INT;
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.name IS DISTINCT FROM OLD.name THEN
            NEW.variant_name := NEW.name;
        ELSIF NEW.variant_name IS DISTINCT FROM OLD.variant_name THEN
            NEW.name := NEW.variant_name;
        END IF;

        IF NEW.price_minor IS DISTINCT FROM OLD.price_minor THEN
            NEW.selling_price_minor := NEW.price_minor;
        ELSIF NEW.selling_price_minor IS DISTINCT FROM OLD.selling_price_minor THEN
            NEW.price_minor := COALESCE(NEW.selling_price_minor, 0)::INT;
        END IF;
    END IF;

    IF NEW.sku IS NULL OR NEW.sku = '' THEN
        NEW.sku := substr(gen_random_uuid()::text, 1, 8);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_sync_daily_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.merchant_id IS NULL THEN
        SELECT p.merchant_id INTO NEW.merchant_id
        FROM product_variants pv
        JOIN products p ON pv.product_id = p.id
        WHERE pv.id = NEW.variant_id;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.business_date IS NOT NULL AND NEW.stock_date IS NULL THEN
            NEW.stock_date := NEW.business_date;
        ELSIF NEW.stock_date IS NOT NULL AND NEW.business_date IS NULL THEN
            NEW.business_date := NEW.stock_date;
        END IF;
        IF NEW.opening > 0 AND (NEW.opening_stock IS NULL OR NEW.opening_stock = 0) THEN
            NEW.opening_stock := NEW.opening;
        ELSIF NEW.opening_stock > 0 AND (NEW.opening IS NULL OR NEW.opening = 0) THEN
            NEW.opening := NEW.opening_stock;
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.business_date IS DISTINCT FROM OLD.business_date THEN
            NEW.stock_date := NEW.business_date;
        END IF;
        IF NEW.opening IS DISTINCT FROM OLD.opening THEN
            NEW.opening_stock := NEW.opening;
        ELSIF NEW.opening_stock IS DISTINCT FROM OLD.opening_stock THEN
            NEW.opening := COALESCE(NEW.opening_stock, 0);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_sync_product_names()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.name IS NOT NULL AND (NEW.title IS NULL OR NEW.title = '') THEN
            NEW.title := NEW.name;
        ELSIF NEW.title IS NOT NULL AND (NEW.name IS NULL OR NEW.name = '') THEN
            NEW.name := NEW.title;
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.name IS DISTINCT FROM OLD.name THEN
            NEW.title := NEW.name;
        ELSIF NEW.title IS DISTINCT FROM OLD.title THEN
            NEW.name := NEW.title;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 3. SNAPSHOT COGS (unit_cost_minor & orders.total_cost_minor) FOR P&L
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_sync_order_items()
RETURNS TRIGGER AS $$
DECLARE
    v_prod_name TEXT;
    v_cost_minor BIGINT;
BEGIN
    IF NEW.merchant_id IS NULL THEN
        SELECT merchant_id INTO NEW.merchant_id FROM orders WHERE id = NEW.order_id;
    END IF;

    SELECT p.name, COALESCE(pv.cost_price_minor, 0)
    INTO v_prod_name, v_cost_minor
    FROM product_variants pv
    JOIN products p ON pv.product_id = p.id
    WHERE pv.id = NEW.variant_id;

    IF NEW.product_name IS NULL OR NEW.product_name = '' THEN
        NEW.product_name := v_prod_name;
    END IF;

    IF NEW.unit_cost_minor IS NULL OR NEW.unit_cost_minor = 0 THEN
        NEW.unit_cost_minor := COALESCE(v_cost_minor, 0);
    END IF;

    IF NEW.line_total_minor IS NULL OR NEW.line_total_minor = 0 THEN
        NEW.line_total_minor := NEW.unit_price_minor * NEW.quantity;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_recalc_order_total_cost()
RETURNS TRIGGER AS $$
DECLARE
    v_order_id UUID;
BEGIN
    v_order_id := COALESCE(NEW.order_id, OLD.order_id);
    UPDATE orders
    SET total_cost_minor = COALESCE(
        (SELECT SUM(total_cost_minor) FROM order_items WHERE order_id = v_order_id),
        0
    )
    WHERE id = v_order_id;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_items_recalc_cost ON order_items;
CREATE TRIGGER trg_order_items_recalc_cost
AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW EXECUTE FUNCTION fn_recalc_order_total_cost();

-- =============================================================================
-- 4. UNIFY order_events & order_timeline (SINGLE SOURCE OF TRUTH)
-- =============================================================================

DROP TRIGGER IF EXISTS trg_order_timeline ON orders;
DROP FUNCTION IF EXISTS fn_log_order_timeline();
DROP TABLE IF EXISTS order_timeline CASCADE;

CREATE OR REPLACE VIEW order_timeline AS
SELECT
    id,
    order_id,
    from_status,
    to_status,
    actor AS triggered_by,
    COALESCE(
        details->>'comment',
        details->>'reason',
        CASE
            WHEN event = 'placed' THEN 'Order placed'
            ELSE 'Order status updated'
        END
    ) AS comment,
    created_at
FROM order_events
WHERE to_status IS NOT NULL
  AND (from_status IS DISTINCT FROM to_status);

-- =============================================================================
-- 5. UNIFY payments & transactions AND FIX v_merchant_pnl_summary
-- =============================================================================

DROP VIEW IF EXISTS v_merchant_pnl_summary;
DROP TABLE IF EXISTS transactions CASCADE;

-- Keep transactions as a read-only compatibility view over canonical payments table
CREATE OR REPLACE VIEW transactions AS
SELECT
    id,
    merchant_id,
    order_id,
    provider AS gateway,
    COALESCE(provider_capture_id, provider_order_id) AS gateway_reference,
    amount_minor::BIGINT AS amount_minor,
    COALESCE(fee_minor, 0)::BIGINT AS fee_minor,
    CASE
        WHEN status = 'completed' THEN 'paid'
        ELSE status
    END AS status,
    created_at
FROM payments;

-- Canonical Real-Time Merchant P&L Analytics View
-- Pre-aggregates payments and refunds per order so 1-to-N attempts never multiply order totals,
-- groups by IST business_date, and excludes unpaid/draft/cancelled/expired orders.
CREATE OR REPLACE VIEW v_merchant_pnl_summary AS
WITH order_fees AS (
    SELECT
        order_id,
        COALESCE(SUM(fee_minor), 0)::BIGINT AS gateway_fees_minor
    FROM payments
    WHERE status IN ('completed', 'refunded')
    GROUP BY order_id
),
order_refunds AS (
    SELECT
        order_id,
        COALESCE(SUM(refund_amount_minor), 0)::BIGINT AS refunds_minor
    FROM refunds
    GROUP BY order_id
)
SELECT
    o.merchant_id,
    o.business_date AS order_date,
    COUNT(o.id) AS total_orders,
    COALESCE(SUM(o.total_minor), 0)::BIGINT AS gross_sales_minor,
    COALESCE(SUM(o.total_cost_minor), 0)::BIGINT AS total_cogs_minor,
    COALESCE(SUM(o.shipping_minor), 0)::BIGINT AS total_delivery_fees_minor,
    COALESCE(SUM(f.gateway_fees_minor), 0)::BIGINT AS total_gateway_fees_minor,
    COALESCE(SUM(r.refunds_minor), 0)::BIGINT AS total_refunds_minor,
    (
        COALESCE(SUM(o.total_minor), 0)::BIGINT
        - COALESCE(SUM(o.total_cost_minor), 0)::BIGINT
        - COALESCE(SUM(o.shipping_minor), 0)::BIGINT
        - COALESCE(SUM(f.gateway_fees_minor), 0)::BIGINT
        - COALESCE(SUM(r.refunds_minor), 0)::BIGINT
    ) AS net_profit_minor
FROM orders o
LEFT JOIN order_fees f ON o.id = f.order_id
LEFT JOIN order_refunds r ON o.id = r.order_id
WHERE o.payment_status IN ('paid', 'partially_refunded', 'refunded')
   OR o.status IN ('paid', 'confirmed', 'ready', 'delivered', 'completed', 'refunded')
GROUP BY o.merchant_id, o.business_date;

-- =============================================================================
-- 6. FIX CUSTOMER LIFETIME STATS TRIGGER (PREVENT DOUBLE COUNT & HANDLE REFUND)
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_update_customer_stats()
RETURNS TRIGGER AS $$
DECLARE
    v_was_paid BOOLEAN := FALSE;
    v_is_paid BOOLEAN := FALSE;
    v_is_refunded BOOLEAN := FALSE;
    v_was_refunded BOOLEAN := FALSE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_is_paid := (NEW.payment_status = 'paid' OR NEW.status = 'paid');
        IF v_is_paid THEN
            UPDATE customers
            SET lifetime_orders_count = lifetime_orders_count + 1,
                lifetime_spent_minor = lifetime_spent_minor + COALESCE(NEW.total_minor, 0)
            WHERE id = NEW.customer_id;
        END IF;
        RETURN NEW;
    END IF;

    v_was_paid := (OLD.payment_status = 'paid' OR OLD.status IN ('paid', 'confirmed', 'ready', 'delivered', 'completed'));
    v_is_paid := (NEW.payment_status = 'paid' OR NEW.status IN ('paid', 'confirmed', 'ready', 'delivered', 'completed'));
    v_was_refunded := (OLD.payment_status = 'refunded' OR OLD.status = 'refunded');
    v_is_refunded := (NEW.payment_status = 'refunded' OR NEW.status = 'refunded');

    IF (NOT v_was_paid) AND v_is_paid AND (NOT v_is_refunded) THEN
        UPDATE customers
        SET lifetime_orders_count = lifetime_orders_count + 1,
            lifetime_spent_minor = lifetime_spent_minor + COALESCE(NEW.total_minor, 0)
        WHERE id = NEW.customer_id;
    ELSIF v_was_paid AND (NOT v_was_refunded) AND v_is_refunded THEN
        UPDATE customers
        SET lifetime_orders_count = GREATEST(0, lifetime_orders_count - 1),
            lifetime_spent_minor = GREATEST(0, lifetime_spent_minor - COALESCE(NEW.total_minor, 0))
        WHERE id = NEW.customer_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_paid ON orders;
CREATE TRIGGER trg_order_paid
AFTER INSERT OR UPDATE OF status, payment_status ON orders
FOR EACH ROW EXECUTE FUNCTION fn_update_customer_stats();

-- =============================================================================
-- 7. UPDATE STORED PROCEDURES & VIEWS FOR INDIA TIMEZONE (Asia/Kolkata)
-- =============================================================================

CREATE OR REPLACE FUNCTION hold_stock(
    p_variant_id UUID,
    p_conversation_id UUID,
    p_quantity INT,
    p_hold_minutes INT DEFAULT 15,
    p_business_date DATE DEFAULT (NOW() AT TIME ZONE 'Asia/Kolkata')::date,
    p_order_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_hold_id UUID;
    v_rows_affected INT;
BEGIN
    UPDATE daily_stock
    SET held = held + p_quantity
    WHERE variant_id = p_variant_id
      AND business_date = p_business_date
      AND (opening + restocked - held - sold - counter_sales) >= p_quantity;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK: Item is sold out or unavailable';
    END IF;

    INSERT INTO stock_holds (
        variant_id, conversation_id, order_id, business_date, quantity, status, expires_at
    ) VALUES (
        p_variant_id, p_conversation_id, p_order_id, p_business_date, p_quantity, 'held',
        NOW() + (p_hold_minutes || ' minutes')::INTERVAL
    ) RETURNING id INTO v_hold_id;

    RETURN v_hold_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION convert_stock_hold(p_hold_id UUID)
RETURNS VOID AS $$
DECLARE
    v_variant_id UUID;
    v_quantity INT;
    v_status VARCHAR(30);
    v_order_id UUID;
    v_business_date DATE;
BEGIN
    SELECT variant_id, quantity, status, order_id, business_date
    INTO v_variant_id, v_quantity, v_status, v_order_id, v_business_date
    FROM stock_holds WHERE id = p_hold_id FOR UPDATE;

    IF v_status <> 'held' THEN
        RAISE EXCEPTION 'Hold is already converted or expired';
    END IF;

    UPDATE daily_stock
    SET held = held - v_quantity,
        sold = sold + v_quantity
    WHERE variant_id = v_variant_id
      AND business_date = COALESCE(
          (SELECT o.business_date FROM orders o WHERE o.id = v_order_id),
          v_business_date,
          (NOW() AT TIME ZONE 'Asia/Kolkata')::date
      );

    UPDATE stock_holds SET status = 'converted' WHERE id = p_hold_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION release_expired_holds()
RETURNS INT AS $$
DECLARE
    v_released_count INT := 0;
    v_merchant_id UUID;
    r RECORD;
BEGIN
    FOR r IN
        SELECT id, variant_id, quantity, order_id, business_date, created_at
        FROM stock_holds
        WHERE status = 'held' AND expires_at < NOW()
        FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE daily_stock
        SET held = held - r.quantity
        WHERE variant_id = r.variant_id
          AND business_date = COALESCE(
              (SELECT o.business_date FROM orders o WHERE o.id = r.order_id),
              r.business_date,
              (r.created_at AT TIME ZONE 'Asia/Kolkata')::date
          );

        UPDATE stock_holds SET status = 'expired' WHERE id = r.id;

        IF r.order_id IS NOT NULL THEN
            UPDATE orders
            SET status = 'expired',
                hold_expires_at = NULL,
                updated_at = NOW()
            WHERE id = r.order_id AND status = 'awaiting_payment'
            RETURNING merchant_id INTO v_merchant_id;

            IF v_merchant_id IS NOT NULL THEN
                INSERT INTO order_events (
                    merchant_id, order_id, event, from_status, to_status, actor, details
                ) VALUES (
                    v_merchant_id, r.order_id, 'expired', 'awaiting_payment', 'expired', 'system', '{}'
                );
            END IF;
        END IF;

        v_released_count := v_released_count + 1;
    END LOOP;

    RETURN v_released_count;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION record_counter_sale(
    p_variant_id UUID,
    p_quantity INT,
    p_business_date DATE DEFAULT (NOW() AT TIME ZONE 'Asia/Kolkata')::date
) RETURNS INT AS $$
DECLARE
    v_new_available INT;
BEGIN
    UPDATE daily_stock
    SET counter_sales = counter_sales + p_quantity
    WHERE variant_id = p_variant_id
      AND business_date = p_business_date
      AND available >= p_quantity
    RETURNING available INTO v_new_available;

    RETURN v_new_available;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW v_active_daily_inventory AS
SELECT
    p.merchant_id,
    p.id AS product_id,
    p.name AS product_name,
    pv.id AS variant_id,
    COALESCE(pv.variant_name, pv.name) AS variant_name,
    pv.price_minor::BIGINT AS selling_price_minor,
    ds.available,
    sr.menu_image_url
FROM products p
JOIN product_variants pv ON p.id = pv.product_id
JOIN daily_stock ds ON pv.id = ds.variant_id
    AND ds.business_date = (NOW() AT TIME ZONE 'Asia/Kolkata')::date
LEFT JOIN story_registry sr ON sr.mapped_variant_id = pv.id AND sr.expires_at > NOW()
WHERE p.is_active = true AND pv.is_active = true;

CREATE OR REPLACE VIEW v_missed_demand_summary AS
SELECT
    merchant_id,
    requested_item_name,
    reason,
    COUNT(*) AS request_count,
    SUM(quantity_requested) AS total_units_missed
FROM missed_demands
WHERE (created_at AT TIME ZONE 'Asia/Kolkata')::date >= (NOW() AT TIME ZONE 'Asia/Kolkata')::date
GROUP BY merchant_id, requested_item_name, reason;

-- =============================================================================
-- 8. DROP DUPLICATE INDEXES & ENABLE RLS ON ALL REMAINING PUBLIC TABLES
-- =============================================================================

DROP INDEX IF EXISTS idx_orders_merchant_date;
DROP INDEX IF EXISTS idx_daily_stock_variant_date;
DROP INDEX IF EXISTS idx_messages_conversation;

ALTER TABLE stock_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE story_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE missed_demands ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_closing_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_field_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_auth ENABLE ROW LEVEL SECURITY;
ALTER TABLE merchant_users ENABLE ROW LEVEL SECURITY;

