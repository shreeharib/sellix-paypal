-- Migration: 20261028000000_enterprise_schema_alignment.sql
-- Goal: Strictly conform orders, payments, order_items to Enterprise SaaS ER Diagram
-- Eliminating MVP legacy columns, redundant duplicates, and sync triggers

-- 1. Drop legacy MVP sync trigger and function
DROP TRIGGER IF EXISTS trg_orders_sync ON orders;
DROP FUNCTION IF EXISTS fn_sync_orders_fields();

-- 2. Align orders table with Enterprise ER diagram
-- Ensure canonical fulfilment_method column exists
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS fulfilment_method VARCHAR(50) DEFAULT 'pickup';

-- Backfill fulfilment_method from existing columns if populated
DO $$
BEGIN
    UPDATE orders 
    SET fulfilment_method = COALESCE(
        fulfilment_method,
        CASE 
            WHEN fulfilment = 'delivery' OR delivery_type = 'delivery' THEN 'local_delivery'
            ELSE 'pickup'
        END
    )
    WHERE fulfilment_method IS NULL OR fulfilment_method = '';
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

-- Add check constraint for fulfilment_method
DO $$
BEGIN
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_fulfilment_method_check;
    ALTER TABLE orders ADD CONSTRAINT orders_fulfilment_method_check 
        CHECK (fulfilment_method IN ('pickup', 'delivery', 'local_delivery', 'courier', 'digital'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Ensure canonical fulfilment_status exists on orders
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS fulfilment_status VARCHAR(50) NOT NULL DEFAULT 'unfulfilled';

DO $$
BEGIN
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_fulfilment_status_check;
    ALTER TABLE orders ADD CONSTRAINT orders_fulfilment_status_check 
        CHECK (fulfilment_status IN ('unfulfilled', 'in_production', 'ready', 'partially_fulfilled', 'fulfilled', 'returned'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Ensure canonical payment_status exists on orders
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS payment_status VARCHAR(50) NOT NULL DEFAULT 'unpaid';

DO $$
BEGIN
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_payment_status_check;
    ALTER TABLE orders ADD CONSTRAINT orders_payment_status_check 
        CHECK (payment_status IN ('pending', 'unpaid', 'partially_paid', 'paid', 'partially_refunded', 'refunded', 'failed'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Ensure customer channel constraint supports omnichannel channels (counter, manual)
DO $$
BEGIN
    ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_channel_check;
    ALTER TABLE customers ADD CONSTRAINT customers_channel_check 
        CHECK (channel IN ('instagram', 'whatsapp', 'webchat', 'counter', 'manual', 'walk_in'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Ensure canonical channel column exists
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS channel VARCHAR(50) DEFAULT 'instagram';

DO $$
BEGIN
    UPDATE orders 
    SET channel = COALESCE(channel, source_channel, 'instagram')
    WHERE channel IS NULL OR channel = '';
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

DO $$
BEGIN
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_channel_check;
    ALTER TABLE orders ADD CONSTRAINT orders_channel_check 
        CHECK (channel IN ('instagram', 'whatsapp', 'webchat', 'counter', 'manual'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Ensure customer_note exists and backfill from notes / delivery_notes
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS customer_note TEXT;

DO $$
BEGIN
    UPDATE orders 
    SET customer_note = COALESCE(customer_note, notes, delivery_notes)
    WHERE customer_note IS NULL;
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

-- Ensure scheduled_date and scheduled_window exist
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS scheduled_date DATE;

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS scheduled_window TEXT;

-- Ensure shipping_minor exists and backfill from delivery_fee_minor
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS shipping_minor BIGINT DEFAULT 0;

DO $$
BEGIN
    UPDATE orders 
    SET shipping_minor = COALESCE(shipping_minor, delivery_fee_minor, 0);
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS tax_minor BIGINT NOT NULL DEFAULT 0;

-- Ensure deposit and paid amounts
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS amount_paid_minor BIGINT DEFAULT 0;

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS deposit_required_minor BIGINT DEFAULT 0;

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS pickup_location_id UUID;

-- Drop non-canonical gift columns if any existed
ALTER TABLE orders DROP COLUMN IF EXISTS is_gift CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS gift CASCADE;

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS source_message_id UUID;

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancelled_reason TEXT;

-- Ensure total_minor has correct values before dropping total_amount_minor
DO $$
BEGIN
    UPDATE orders 
    SET total_minor = total_amount_minor
    WHERE (total_minor IS NULL OR total_minor = 0) AND total_amount_minor > 0;
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

-- Recreate generated column estimated_profit_minor to use canonical total_minor and shipping_minor
ALTER TABLE orders DROP COLUMN IF EXISTS estimated_profit_minor CASCADE;
ALTER TABLE orders ADD COLUMN estimated_profit_minor BIGINT GENERATED ALWAYS AS (
    total_minor - total_cost_minor - shipping_minor
) STORED;

-- Drop obsolete MVP columns from orders
ALTER TABLE orders DROP COLUMN IF EXISTS fulfilment CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS delivery_type CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS source_channel CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS total_amount_minor CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS delivery_fee_minor CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS notes CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS delivery_notes CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS needed_by CASCADE;

-- 3. Align payments table with Enterprise ER diagram
-- Expand provider check constraint
DO $$
BEGIN
    ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_provider_check;
    ALTER TABLE payments ADD CONSTRAINT payments_provider_check 
        CHECK (provider IN ('paypal', 'razorpay', 'cashfree', 'upi_manual', 'manual', 'cash', 'stripe'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Make provider_order_id nullable for manual/cash payments
ALTER TABLE payments ALTER COLUMN provider_order_id DROP NOT NULL;

-- Add method, kind, fee_minor, paid_at
ALTER TABLE payments 
ADD COLUMN IF NOT EXISTS method TEXT DEFAULT 'upi';

DO $$
BEGIN
    ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_method_check;
    ALTER TABLE payments ADD CONSTRAINT payments_method_check 
        CHECK (method IN ('upi', 'card', 'paypal_wallet', 'cash'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE payments 
ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'full';

DO $$
BEGIN
    ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_kind_check;
    ALTER TABLE payments ADD CONSTRAINT payments_kind_check 
        CHECK (kind IN ('full', 'deposit', 'balance'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE payments 
ADD COLUMN IF NOT EXISTS fee_minor INT DEFAULT 0;

ALTER TABLE payments 
ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

-- 4. Align order_items table with Enterprise ER diagram
ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS variant_label TEXT;

DO $$
BEGIN
    UPDATE order_items 
    SET variant_label = COALESCE(variant_label, variant_name);
EXCEPTION WHEN undefined_column THEN NULL;
END $$;

-- Drop legacy variant_name column
ALTER TABLE order_items DROP COLUMN IF EXISTS variant_name CASCADE;

ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS option_values JSONB NOT NULL DEFAULT '{}';

ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS personalization JSONB NOT NULL DEFAULT '{}';

ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS line_total_minor INT NOT NULL DEFAULT 0;

ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS fulfilment_status VARCHAR(50) NOT NULL DEFAULT 'unfulfilled';

DO $$
BEGIN
    ALTER TABLE order_items DROP CONSTRAINT IF EXISTS order_items_fulfilment_status_check;
    ALTER TABLE order_items ADD CONSTRAINT order_items_fulfilment_status_check 
        CHECK (fulfilment_status IN ('unfulfilled', 'in_production', 'ready', 'partially_fulfilled', 'fulfilled', 'returned'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 5. Update CRM customer stats trigger to use canonical NEW.total_minor
CREATE OR REPLACE FUNCTION fn_update_customer_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE') AND (
        (OLD.payment_status <> 'paid' AND NEW.payment_status = 'paid') OR
        (OLD.status <> 'paid' AND NEW.status = 'paid')
    ) THEN
        UPDATE customers
        SET lifetime_orders_count = lifetime_orders_count + 1,
            lifetime_spent_minor = lifetime_spent_minor + COALESCE(NEW.total_minor, 0)
        WHERE id = NEW.customer_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Update PnL View to use canonical total_minor and shipping_minor
CREATE OR REPLACE VIEW v_merchant_pnl_summary AS
SELECT 
    o.merchant_id,
    DATE(o.created_at) AS order_date,
    COUNT(o.id) AS total_orders,
    SUM(o.total_minor) AS gross_sales_minor,
    SUM(o.total_cost_minor) AS total_cogs_minor,
    SUM(o.shipping_minor) AS total_delivery_fees_minor,
    COALESCE(SUM(t.fee_minor), 0) AS total_gateway_fees_minor,
    COALESCE(SUM(r.refund_amount_minor), 0) AS total_refunds_minor,
    (SUM(o.total_minor) 
     - SUM(o.total_cost_minor) 
     - SUM(o.shipping_minor) 
     - COALESCE(SUM(t.fee_minor), 0) 
     - COALESCE(SUM(r.refund_amount_minor), 0)
    ) AS net_profit_minor
FROM orders o
LEFT JOIN transactions t ON o.id = t.order_id AND t.status = 'paid'
LEFT JOIN refunds r ON o.id = r.order_id
WHERE o.status NOT IN ('draft', 'cancelled')
GROUP BY o.merchant_id, DATE(o.created_at);
