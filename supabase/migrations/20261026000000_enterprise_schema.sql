-- =======================================================
-- SELLIX ENTERPRISE SAAS SCHEMA
-- Tables, Triggers, Stored Procedures, Views & RLS
-- =======================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =======================================================
-- 1. BASE TABLES: TENANCY, USERS & CONFIG
-- =======================================================

CREATE TABLE merchants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    currency VARCHAR(3) DEFAULT 'INR',
    timezone VARCHAR(50) DEFAULT 'Asia/Kolkata',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE merchant_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(150) NOT NULL,
    role VARCHAR(50) DEFAULT 'owner',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE shop_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    version INT NOT NULL DEFAULT 1,
    prompt_markdown TEXT NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(merchant_id, version)
);

CREATE TABLE channel_integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    channel VARCHAR(50) NOT NULL,
    account_id VARCHAR(150) NOT NULL,
    access_token_encrypted TEXT,
    is_agent_enabled BOOLEAN DEFAULT true,
    config JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(merchant_id, channel, account_id)
);

CREATE TABLE custom_field_definitions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    target_entity VARCHAR(50) NOT NULL,
    field_key VARCHAR(100) NOT NULL,
    label VARCHAR(150) NOT NULL,
    data_type VARCHAR(50) NOT NULL,
    options JSONB DEFAULT '[]',
    agent_prompt_instruction TEXT,
    is_required BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(merchant_id, target_entity, field_key)
);

-- =======================================================
-- 2. CATALOG, ALIASES & DAILY STOCK LEDGER
-- =======================================================

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    base_image_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sku VARCHAR(100) NOT NULL,
    variant_name VARCHAR(150) NOT NULL,
    selling_price_minor BIGINT NOT NULL,
    cost_price_minor BIGINT NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(product_id, sku)
);

CREATE TABLE product_aliases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    alias_text VARCHAR(255) NOT NULL,
    confidence_source VARCHAR(50) DEFAULT 'merchant_confirmed',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE daily_stock (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    stock_date DATE NOT NULL DEFAULT CURRENT_DATE,
    opening_stock INT NOT NULL DEFAULT 0,
    restocked INT NOT NULL DEFAULT 0,
    held INT NOT NULL DEFAULT 0,
    sold INT NOT NULL DEFAULT 0,
    counter_sales INT NOT NULL DEFAULT 0,
    available INT GENERATED ALWAYS AS (
        opening_stock + restocked - held - sold - counter_sales
    ) STORED,
    CONSTRAINT check_stock_not_negative CHECK (
        (opening_stock + restocked - held - sold - counter_sales) >= 0
    ),
    UNIQUE(variant_id, stock_date)
);

-- =======================================================
-- 3. CUSTOMERS, AUTH & CHAT
-- =======================================================

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    primary_name VARCHAR(150),
    primary_phone VARCHAR(30),
    primary_email VARCHAR(255),
    default_address JSONB,
    lifetime_orders_count INT DEFAULT 0,
    lifetime_spent_minor BIGINT DEFAULT 0,
    custom_attributes JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE customer_identities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    channel VARCHAR(50) NOT NULL,
    channel_user_id VARCHAR(150) NOT NULL,
    channel_username VARCHAR(150),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(channel, channel_user_id)
);

CREATE TABLE customer_auth (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    phone_number VARCHAR(30) UNIQUE,
    current_otp_hash VARCHAR(255),
    otp_expires_at TIMESTAMPTZ,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    channel VARCHAR(50) NOT NULL,
    detected_language VARCHAR(20) DEFAULT 'en',
    is_human_takeover BOOLEAN DEFAULT false,
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_type VARCHAR(20) NOT NULL,
    content_text TEXT,
    media_url TEXT,
    raw_payload JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE stock_holds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    quantity INT NOT NULL CHECK (quantity > 0),
    status VARCHAR(30) DEFAULT 'held',
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE escalations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    customer_question TEXT NOT NULL,
    media_url TEXT,
    merchant_answer TEXT,
    status VARCHAR(30) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE story_registry (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    ig_story_id VARCHAR(150) NOT NULL,
    mapped_variant_id UUID REFERENCES product_variants(id),
    menu_image_url TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(merchant_id, ig_story_id)
);

CREATE TABLE ai_usage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID,
    model_name VARCHAR(100) NOT NULL,
    prompt_tokens INT NOT NULL,
    completion_tokens INT NOT NULL,
    cost_minor_units BIGINT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE agent_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    action_type VARCHAR(100) NOT NULL,
    tool_inputs JSONB NOT NULL,
    tool_outputs JSONB,
    confidence_score NUMERIC(4, 3),
    requires_approval BOOLEAN DEFAULT false,
    is_approved BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =======================================================
-- 4. ORDERS, TIMELINE, REFUNDS & TRANSACTIONS
-- =======================================================

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id),
    conversation_id UUID REFERENCES conversations(id),
    order_number VARCHAR(50) NOT NULL,
    source_channel VARCHAR(50) NOT NULL,
    placed_by VARCHAR(50) NOT NULL,
    delivery_type VARCHAR(30) DEFAULT 'pickup',
    delivery_slot TIMESTAMPTZ,
    delivery_address JSONB,
    delivery_notes TEXT,
    status VARCHAR(50) DEFAULT 'draft',
    payment_status VARCHAR(50) DEFAULT 'pending',
    currency VARCHAR(3) DEFAULT 'INR',
    subtotal_minor BIGINT NOT NULL DEFAULT 0,
    discount_minor BIGINT NOT NULL DEFAULT 0,
    delivery_fee_minor BIGINT NOT NULL DEFAULT 0,
    total_amount_minor BIGINT NOT NULL DEFAULT 0,
    total_cost_minor BIGINT NOT NULL DEFAULT 0,
    estimated_profit_minor BIGINT GENERATED ALWAYS AS (
        total_amount_minor - total_cost_minor - delivery_fee_minor
    ) STORED,
    custom_attributes JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(merchant_id, order_number)
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price_minor BIGINT NOT NULL,
    unit_cost_minor BIGINT NOT NULL,
    total_price_minor BIGINT GENERATED ALWAYS AS (unit_price_minor * quantity) STORED,
    total_cost_minor BIGINT GENERATED ALWAYS AS (unit_cost_minor * quantity) STORED
);

CREATE TABLE order_timeline (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    from_status VARCHAR(50),
    to_status VARCHAR(50) NOT NULL,
    triggered_by VARCHAR(50) NOT NULL,
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE refunds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    refund_amount_minor BIGINT NOT NULL,
    reason TEXT,
    is_restocked BOOLEAN DEFAULT true,
    processed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    order_id UUID REFERENCES orders(id),
    gateway VARCHAR(50) NOT NULL,
    gateway_reference VARCHAR(150),
    amount_minor BIGINT NOT NULL,
    fee_minor BIGINT DEFAULT 0,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE missed_demands (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id),
    requested_item_name VARCHAR(150) NOT NULL,
    variant_id UUID REFERENCES product_variants(id),
    quantity_requested INT DEFAULT 1,
    reason VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE daily_closing_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    report_date DATE NOT NULL DEFAULT CURRENT_DATE,
    total_sales_minor BIGINT NOT NULL DEFAULT 0,
    total_counter_sales_minor BIGINT NOT NULL DEFAULT 0,
    items_sold_out_early JSONB DEFAULT '[]',
    leftover_stock JSONB DEFAULT '[]',
    missed_requests_count INT DEFAULT 0,
    tomorrow_recommendation TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(merchant_id, report_date)
);

-- =======================================================
-- 5. BUSINESS LOGIC FUNCTIONS (STORED PROCEDURES)
-- =======================================================

-- 1. Atomic 15-Minute Stock Hold (Prevents Overselling in DMs)
CREATE OR REPLACE FUNCTION hold_stock(
    p_variant_id UUID,
    p_conversation_id UUID,
    p_quantity INT,
    p_hold_minutes INT DEFAULT 15
) RETURNS UUID AS $$
DECLARE
    v_hold_id UUID;
    v_rows_affected INT;
BEGIN
    -- Atomically lock and increment held stock IF enough available
    UPDATE daily_stock
    SET held = held + p_quantity
    WHERE variant_id = p_variant_id
      AND stock_date = CURRENT_DATE
      AND (opening_stock + restocked - held - sold - counter_sales) >= p_quantity;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK: Item is sold out or unavailable';
    END IF;

    -- Create the hold record
    INSERT INTO stock_holds (
        variant_id, conversation_id, quantity, status, expires_at
    ) VALUES (
        p_variant_id, p_conversation_id, p_quantity, 'held',
        NOW() + (p_hold_minutes || ' minutes')::INTERVAL
    ) RETURNING id INTO v_hold_id;

    RETURN v_hold_id;
END;
$$ LANGUAGE plpgsql;

-- 2. Convert Hold to Confirmed Sale on Payment
CREATE OR REPLACE FUNCTION convert_stock_hold(p_hold_id UUID) 
RETURNS VOID AS $$
DECLARE
    v_variant_id UUID;
    v_quantity INT;
    v_status VARCHAR(30);
BEGIN
    SELECT variant_id, quantity, status 
    INTO v_variant_id, v_quantity, v_status
    FROM stock_holds WHERE id = p_hold_id FOR UPDATE;

    IF v_status <> 'held' THEN
        RAISE EXCEPTION 'Hold is already converted or expired';
    END IF;

    -- Shift from held to sold in daily ledger
    UPDATE daily_stock
    SET held = held - v_quantity,
        sold = sold + v_quantity
    WHERE variant_id = v_variant_id AND stock_date = CURRENT_DATE;

    UPDATE stock_holds SET status = 'converted' WHERE id = p_hold_id;
END;
$$ LANGUAGE plpgsql;

-- 3. Release Expired Holds (Triggered by Cron / Procrastinate)
CREATE OR REPLACE FUNCTION release_expired_holds() 
RETURNS INT AS $$
DECLARE
    v_released_count INT := 0;
    r RECORD;
BEGIN
    FOR r IN 
        SELECT id, variant_id, quantity 
        FROM stock_holds 
        WHERE status = 'held' AND expires_at < NOW()
        FOR UPDATE
    LOOP
        UPDATE daily_stock
        SET held = held - r.quantity
        WHERE variant_id = r.variant_id AND stock_date = CURRENT_DATE;

        UPDATE stock_holds SET status = 'expired' WHERE id = r.id;
        v_released_count := v_released_count + 1;
    END LOOP;

    RETURN v_released_count;
END;
$$ LANGUAGE plpgsql;

-- 4. Record Offline Counter Sales ("5 brownies counter-la poyiduchu")
CREATE OR REPLACE FUNCTION record_counter_sale(
    p_variant_id UUID,
    p_quantity INT
) RETURNS INT AS $$
DECLARE
    v_new_available INT;
BEGIN
    UPDATE daily_stock
    SET counter_sales = counter_sales + p_quantity
    WHERE variant_id = p_variant_id AND stock_date = CURRENT_DATE
    RETURNING available INTO v_new_available;

    RETURN v_new_available;
END;
$$ LANGUAGE plpgsql;

-- =======================================================
-- 6. TRIGGERS
-- =======================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION fn_touch_updated_at() 
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_merchants_touch BEFORE UPDATE ON merchants
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TRIGGER trg_orders_touch BEFORE UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- Auto-log order status timeline
CREATE OR REPLACE FUNCTION fn_log_order_timeline() 
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.status IS DISTINCT FROM NEW.status) THEN
        INSERT INTO order_timeline (
            order_id, from_status, to_status, triggered_by, comment
        ) VALUES (
            NEW.id, OLD.status, NEW.status, 'system', 'Order status updated'
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_timeline AFTER UPDATE OF status ON orders
FOR EACH ROW EXECUTE FUNCTION fn_log_order_timeline();

-- Update customer lifetime spend on paid orders
CREATE OR REPLACE FUNCTION fn_update_customer_stats() 
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.payment_status <> 'paid' AND NEW.payment_status = 'paid') THEN
        UPDATE customers
        SET lifetime_orders_count = lifetime_orders_count + 1,
            lifetime_spent_minor = lifetime_spent_minor + NEW.total_amount_minor
        WHERE id = NEW.customer_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_paid AFTER UPDATE OF payment_status ON orders
FOR EACH ROW EXECUTE FUNCTION fn_update_customer_stats();

-- =======================================================
-- 7. ESSENTIAL VIEWS (AI AGENT & ANALYTICS)
-- =======================================================

-- View 1: Real-Time Available Stock for AI Agent
CREATE OR REPLACE VIEW v_active_daily_inventory AS
SELECT 
    p.merchant_id,
    p.id AS product_id,
    p.title AS product_name,
    pv.id AS variant_id,
    pv.variant_name,
    pv.selling_price_minor,
    ds.available,
    sr.menu_image_url
FROM products p
JOIN product_variants pv ON p.id = pv.product_id
JOIN daily_stock ds ON pv.id = ds.variant_id AND ds.stock_date = CURRENT_DATE
LEFT JOIN story_registry sr ON sr.mapped_variant_id = pv.id AND sr.expires_at > NOW()
WHERE p.is_active = true AND pv.is_active = true;

-- View 2: Real-Time Merchant P&L Analytics
CREATE OR REPLACE VIEW v_merchant_pnl_summary AS
SELECT 
    o.merchant_id,
    DATE(o.created_at) AS order_date,
    COUNT(o.id) AS total_orders,
    SUM(o.total_amount_minor) AS gross_sales_minor,
    SUM(o.total_cost_minor) AS total_cogs_minor,
    SUM(o.delivery_fee_minor) AS total_delivery_fees_minor,
    COALESCE(SUM(t.fee_minor), 0) AS total_gateway_fees_minor,
    COALESCE(SUM(r.refund_amount_minor), 0) AS total_refunds_minor,
    -- Net Profit = Gross Sales - COGS - Delivery Fees - Gateway Fees - Refunds
    (SUM(o.total_amount_minor) 
     - SUM(o.total_cost_minor) 
     - SUM(o.delivery_fee_minor) 
     - COALESCE(SUM(t.fee_minor), 0) 
     - COALESCE(SUM(r.refund_amount_minor), 0)
    ) AS net_profit_minor
FROM orders o
LEFT JOIN transactions t ON o.id = t.order_id AND t.status = 'paid'
LEFT JOIN refunds r ON o.id = r.order_id
WHERE o.status NOT IN ('draft', 'cancelled')
GROUP BY o.merchant_id, DATE(o.created_at);

-- View 3: Pending "Ask Me" Escalations for Owner App
CREATE OR REPLACE VIEW v_pending_escalations AS
SELECT 
    e.id AS escalation_id,
    e.merchant_id,
    e.conversation_id,
    c.primary_name AS customer_name,
    c.primary_phone AS customer_phone,
    conv.channel,
    e.customer_question,
    e.media_url AS customer_photo_url,
    e.created_at
FROM escalations e
JOIN conversations conv ON e.conversation_id = conv.id
JOIN customers c ON conv.customer_id = c.id
WHERE e.status = 'pending';

-- View 4: Lost Demand Summary (Baking Advice)
CREATE OR REPLACE VIEW v_missed_demand_summary AS
SELECT 
    merchant_id,
    requested_item_name,
    reason,
    COUNT(*) AS request_count,
    SUM(quantity_requested) AS total_units_missed
FROM missed_demands
WHERE created_at >= CURRENT_DATE
GROUP BY merchant_id, requested_item_name, reason;

-- =======================================================
-- 8. INDEXES FOR SUB-MILLISECOND LOOKUPS
-- =======================================================

CREATE INDEX idx_daily_stock_variant_date ON daily_stock(variant_id, stock_date);
CREATE INDEX idx_stock_holds_active ON stock_holds(variant_id, status, expires_at);
CREATE INDEX idx_orders_merchant_date ON orders(merchant_id, created_at DESC);
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at ASC);
CREATE INDEX idx_story_registry_lookup ON story_registry(merchant_id, ig_story_id);
CREATE INDEX idx_orders_custom_gin ON orders USING GIN (custom_attributes);
CREATE INDEX idx_customers_custom_gin ON customers USING GIN (custom_attributes);
