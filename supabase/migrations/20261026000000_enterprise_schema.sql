-- =======================================================
-- SELLIX ENTERPRISE SAAS SCHEMA
-- Tables, Triggers, Stored Procedures, Views & RLS
-- =======================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Common trigger functions for updated_at
CREATE OR REPLACE FUNCTION fn_touch_updated_at() 
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION set_updated_at() 
RETURNS TRIGGER 
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

-- =======================================================
-- 1. BASE TABLES: TENANCY, USERS & CONFIG
-- =======================================================

CREATE TABLE merchants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_name VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    currency VARCHAR(3) DEFAULT 'INR',
    timezone VARCHAR(50) DEFAULT 'Asia/Kolkata',
    is_active BOOLEAN DEFAULT true,
    agent_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Sync business_name and name
CREATE OR REPLACE FUNCTION fn_sync_merchant_names()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.name IS NOT NULL AND (NEW.business_name IS NULL OR NEW.business_name = '') THEN
        NEW.business_name := NEW.name;
    ELSIF NEW.business_name IS NOT NULL AND (NEW.name IS NULL OR NEW.name = '') THEN
        NEW.name := NEW.business_name;
    END IF;
    IF NEW.slug IS NULL OR NEW.slug = '' THEN
        NEW.slug := lower(regexp_replace(COALESCE(NEW.name, 'shop'), '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(gen_random_uuid()::text, 1, 8);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_merchants_sync_names
BEFORE INSERT OR UPDATE ON merchants
FOR EACH ROW EXECUTE FUNCTION fn_sync_merchant_names();

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255),
    display_name TEXT,
    name VARCHAR(150),
    role VARCHAR(50) DEFAULT 'owner',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login_at TIMESTAMPTZ
);

CREATE TABLE merchant_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) DEFAULT '',
    name VARCHAR(150) NOT NULL,
    role VARCHAR(50) DEFAULT 'owner',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_identities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider in ('instagram', 'phone', 'email')),
    subject TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (provider, subject)
);
CREATE INDEX user_identities_user_idx ON user_identities (user_id);

CREATE TABLE merchant_members (
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'owner' CHECK (role in ('owner', 'staff')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (merchant_id, user_id)
);
CREATE INDEX merchant_members_user_idx ON merchant_members (user_id);

CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash TEXT NOT NULL UNIQUE,
    previous_refresh_token_hash TEXT,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);
CREATE INDEX sessions_user_idx ON sessions (user_id);
CREATE INDEX sessions_previous_token_idx
  ON sessions (previous_refresh_token_hash) WHERE previous_refresh_token_hash IS NOT NULL;

CREATE TABLE login_codes (
    code_hash TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_challenge TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE shop_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    version INT NOT NULL DEFAULT 1 CHECK (version > 0),
    content_md TEXT NOT NULL DEFAULT '',
    prompt_markdown TEXT NOT NULL DEFAULT '',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(merchant_id, version)
);

CREATE OR REPLACE FUNCTION fn_sync_shop_profile()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.content_md IS NOT NULL AND (NEW.prompt_markdown IS NULL OR NEW.prompt_markdown = '') THEN
        NEW.prompt_markdown := NEW.content_md;
    ELSIF NEW.prompt_markdown IS NOT NULL AND (NEW.content_md IS NULL OR NEW.content_md = '') THEN
        NEW.content_md := NEW.prompt_markdown;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_shop_profile_sync
BEFORE INSERT OR UPDATE ON shop_profiles
FOR EACH ROW EXECUTE FUNCTION fn_sync_shop_profile();

CREATE TABLE shop_onboarding (
    merchant_id UUID PRIMARY KEY REFERENCES merchants(id) ON DELETE CASCADE,
    answers JSONB NOT NULL DEFAULT '{}'::jsonb,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE channel_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    channel TEXT NOT NULL CHECK (channel in ('instagram', 'whatsapp')),
    external_account_id TEXT NOT NULL,
    username TEXT,
    access_token_encrypted TEXT NOT NULL,
    token_expires_at TIMESTAMPTZ,
    token_refreshed_at TIMESTAMPTZ DEFAULT NOW(),
    scopes TEXT[] DEFAULT '{}',
    status TEXT DEFAULT 'active' CHECK (status in ('active', 'revoked', 'error')),
    is_agent_enabled BOOLEAN DEFAULT true,
    config JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (channel, external_account_id)
);
CREATE INDEX channel_connections_merchant_idx ON channel_connections (merchant_id);

CREATE VIEW channel_integrations AS
SELECT 
    id,
    merchant_id,
    channel,
    external_account_id AS account_id,
    access_token_encrypted,
    is_agent_enabled,
    config,
    created_at
FROM channel_connections;

CREATE TABLE custom_field_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    title VARCHAR(255) DEFAULT '',
    description TEXT,
    category VARCHAR(100),
    base_image_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX products_merchant_name_idx ON products (merchant_id, lower(name));

CREATE OR REPLACE FUNCTION fn_sync_product_names()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.name IS NOT NULL AND (NEW.title IS NULL OR NEW.title = '') THEN
        NEW.title := NEW.name;
    ELSIF NEW.title IS NOT NULL AND (NEW.name IS NULL OR NEW.name = '') THEN
        NEW.name := NEW.title;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_products_sync_names
BEFORE INSERT OR UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION fn_sync_product_names();

CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sku VARCHAR(100),
    name TEXT,
    variant_name VARCHAR(150),
    price_minor INT NOT NULL DEFAULT 0 CHECK (price_minor >= 0),
    selling_price_minor BIGINT DEFAULT 0,
    cost_price_minor BIGINT DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'INR' CHECK (currency ~ '^[A-Z]{3}$'),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX product_variants_name_idx
  ON product_variants (product_id, lower(coalesce(name, '')));

CREATE OR REPLACE FUNCTION fn_sync_variant_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Populate merchant_id from product if missing
    IF NEW.merchant_id IS NULL THEN
        SELECT merchant_id INTO NEW.merchant_id FROM products WHERE id = NEW.product_id;
    END IF;
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
    IF NEW.sku IS NULL OR NEW.sku = '' THEN
        NEW.sku := substr(gen_random_uuid()::text, 1, 8);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_product_variants_sync
BEFORE INSERT OR UPDATE ON product_variants
FOR EACH ROW EXECUTE FUNCTION fn_sync_variant_fields();

CREATE TABLE product_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    alias_text VARCHAR(255) NOT NULL,
    confidence_source VARCHAR(50) DEFAULT 'merchant_confirmed',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE daily_stock (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    business_date DATE NOT NULL DEFAULT CURRENT_DATE,
    stock_date DATE DEFAULT CURRENT_DATE,
    opening INT NOT NULL DEFAULT 0 CHECK (opening >= 0),
    opening_stock INT DEFAULT 0,
    restocked INT NOT NULL DEFAULT 0 CHECK (restocked >= 0),
    held INT NOT NULL DEFAULT 0 CHECK (held >= 0),
    sold INT NOT NULL DEFAULT 0 CHECK (sold >= 0),
    counter_sales INT NOT NULL DEFAULT 0 CHECK (counter_sales >= 0),
    available INT GENERATED ALWAYS AS (
        opening + restocked - held - sold - counter_sales
    ) STORED,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(variant_id, business_date),
    CONSTRAINT check_stock_not_negative CHECK (
        (opening + restocked - held - sold - counter_sales) >= 0
    )
);
CREATE INDEX daily_stock_merchant_date_idx ON daily_stock (merchant_id, business_date);

CREATE OR REPLACE FUNCTION fn_sync_daily_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.merchant_id IS NULL THEN
        SELECT p.merchant_id INTO NEW.merchant_id
        FROM product_variants pv
        JOIN products p ON pv.product_id = p.id
        WHERE pv.id = NEW.variant_id;
    END IF;
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
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_daily_stock_sync
BEFORE INSERT OR UPDATE ON daily_stock
FOR EACH ROW EXECUTE FUNCTION fn_sync_daily_stock();

-- =======================================================
-- 3. CUSTOMERS, AUTH & CHAT
-- =======================================================

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    channel TEXT CHECK (channel in ('instagram', 'whatsapp', 'webchat')),
    external_id TEXT,
    display_name TEXT,
    primary_name VARCHAR(150),
    primary_phone VARCHAR(30),
    primary_email VARCHAR(255),
    default_address JSONB,
    lifetime_orders_count INT DEFAULT 0,
    lifetime_spent_minor BIGINT DEFAULT 0,
    custom_attributes JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (merchant_id, channel, external_id)
);

CREATE OR REPLACE FUNCTION fn_sync_customer_names()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.display_name IS NOT NULL AND (NEW.primary_name IS NULL OR NEW.primary_name = '') THEN
        NEW.primary_name := NEW.display_name;
    ELSIF NEW.primary_name IS NOT NULL AND (NEW.display_name IS NULL OR NEW.display_name = '') THEN
        NEW.display_name := NEW.primary_name;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_customers_sync_names
BEFORE INSERT OR UPDATE ON customers
FOR EACH ROW EXECUTE FUNCTION fn_sync_customer_names();

CREATE TABLE customer_identities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    channel VARCHAR(50) NOT NULL,
    channel_user_id VARCHAR(150) NOT NULL,
    channel_username VARCHAR(150),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(channel, channel_user_id)
);

CREATE TABLE customer_auth (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    phone_number VARCHAR(30) UNIQUE,
    current_otp_hash VARCHAR(255),
    otp_expires_at TIMESTAMPTZ,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL UNIQUE REFERENCES customers(id) ON DELETE CASCADE,
    channel TEXT NOT NULL DEFAULT 'instagram',
    channel_connection_id UUID REFERENCES channel_connections(id) ON DELETE CASCADE,
    agent_active BOOLEAN NOT NULL DEFAULT true,
    agent_paused_reason TEXT
        CHECK (agent_paused_reason in ('merchant_replied', 'merchant_switched_off')),
    last_customer_message_at TIMESTAMPTZ,
    detected_language VARCHAR(20) DEFAULT 'en',
    is_human_takeover BOOLEAN DEFAULT false,
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (agent_active or agent_paused_reason is not null)
);
CREATE INDEX conversations_merchant_idx ON conversations (merchant_id);

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    direction TEXT NOT NULL CHECK (direction in ('inbound', 'outbound', 'internal')),
    sender TEXT NOT NULL CHECK (sender in ('customer', 'agent', 'merchant', 'system')),
    sender_type VARCHAR(20),
    external_id TEXT,
    body TEXT NOT NULL DEFAULT '',
    content_text TEXT,
    media_url TEXT,
    raw_payload JSONB,
    metadata JSONB NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'received' CHECK (status in ('received', 'sending', 'sent', 'failed')),
    error TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (
      (direction = 'inbound' AND sender = 'customer') OR
      (direction = 'internal' AND sender = 'system') OR
      (direction = 'outbound' AND sender in ('agent', 'merchant'))
    )
);
CREATE UNIQUE INDEX messages_external_id_idx
  ON messages (merchant_id, external_id) WHERE external_id IS NOT NULL;
CREATE INDEX messages_conversation_idx ON messages (conversation_id, created_at);

CREATE OR REPLACE FUNCTION fn_sync_message_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.body IS NOT NULL AND (NEW.content_text IS NULL OR NEW.content_text = '') THEN
        NEW.content_text := NEW.body;
    ELSIF NEW.content_text IS NOT NULL AND (NEW.body IS NULL OR NEW.body = '') THEN
        NEW.body := NEW.content_text;
    END IF;
    IF NEW.sender IS NOT NULL AND NEW.sender_type IS NULL THEN
        NEW.sender_type := NEW.sender;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_messages_sync
BEFORE INSERT OR UPDATE ON messages
FOR EACH ROW EXECUTE FUNCTION fn_sync_message_fields();

CREATE TABLE stock_holds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    quantity INT NOT NULL CHECK (quantity > 0),
    status VARCHAR(30) DEFAULT 'held',
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE escalations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    trigger_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    question TEXT NOT NULL,
    customer_question TEXT,
    media_url TEXT,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status in ('open', 'answered', 'closed', 'pending')),
    answer TEXT,
    merchant_answer TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    answered_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ
);
CREATE INDEX escalations_open_idx ON escalations (merchant_id, created_at) WHERE status IN ('open', 'pending');

CREATE OR REPLACE FUNCTION fn_sync_escalation_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.question IS NOT NULL AND (NEW.customer_question IS NULL OR NEW.customer_question = '') THEN
        NEW.customer_question := NEW.question;
    ELSIF NEW.customer_question IS NOT NULL AND (NEW.question IS NULL OR NEW.question = '') THEN
        NEW.question := NEW.customer_question;
    END IF;
    IF NEW.answer IS NOT NULL AND (NEW.merchant_answer IS NULL OR NEW.merchant_answer = '') THEN
        NEW.merchant_answer := NEW.answer;
    ELSIF NEW.merchant_answer IS NOT NULL AND (NEW.answer IS NULL OR NEW.answer = '') THEN
        NEW.answer := NEW.merchant_answer;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_escalations_sync
BEFORE INSERT OR UPDATE ON escalations
FOR EACH ROW EXECUTE FUNCTION fn_sync_escalation_fields();

CREATE TABLE story_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    ig_story_id VARCHAR(150) NOT NULL,
    mapped_variant_id UUID REFERENCES product_variants(id),
    menu_image_url TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(merchant_id, ig_story_id)
);

CREATE TABLE ai_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE SET NULL,
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
    purpose TEXT NOT NULL DEFAULT 'customer_reply',
    model TEXT NOT NULL,
    model_name VARCHAR(100),
    input_tokens INT,
    prompt_tokens INT,
    output_tokens INT,
    completion_tokens INT,
    latency_ms INT NOT NULL DEFAULT 0,
    cost_minor_units BIGINT DEFAULT 0,
    succeeded BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ai_usage_merchant_idx ON ai_usage (merchant_id, created_at);

CREATE OR REPLACE FUNCTION fn_sync_ai_usage_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.model IS NOT NULL AND NEW.model_name IS NULL THEN
        NEW.model_name := NEW.model;
    ELSIF NEW.model_name IS NOT NULL AND NEW.model = '' THEN
        NEW.model := NEW.model_name;
    END IF;
    IF NEW.input_tokens IS NOT NULL AND NEW.prompt_tokens IS NULL THEN
        NEW.prompt_tokens := NEW.input_tokens;
    END IF;
    IF NEW.output_tokens IS NOT NULL AND NEW.completion_tokens IS NULL THEN
        NEW.completion_tokens := NEW.output_tokens;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ai_usage_sync
BEFORE INSERT OR UPDATE ON ai_usage
FOR EACH ROW EXECUTE FUNCTION fn_sync_ai_usage_fields();

CREATE TABLE agent_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    action_type VARCHAR(100) NOT NULL,
    tool_inputs JSONB NOT NULL,
    tool_outputs JSONB,
    confidence_score NUMERIC(4, 3),
    requires_approval BOOLEAN DEFAULT false,
    is_approved BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source TEXT NOT NULL CHECK (source in ('meta', 'paypal')),
    dedupe_key TEXT NOT NULL,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status in ('pending', 'processed', 'failed')),
    attempts INT NOT NULL DEFAULT 0,
    error TEXT,
    received_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    UNIQUE (source, dedupe_key)
);
CREATE INDEX webhook_events_pending_idx ON webhook_events (received_at) WHERE status = 'pending';

-- =======================================================
-- 4. ORDERS, TIMELINE, REFUNDS & TRANSACTIONS
-- =======================================================

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    number BIGINT GENERATED ALWAYS AS IDENTITY (START WITH 1001) UNIQUE,
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
    order_number VARCHAR(50),
    source_channel VARCHAR(50) DEFAULT 'instagram',
    placed_by VARCHAR(50) DEFAULT 'customer',
    fulfilment TEXT CHECK (fulfilment in ('pickup', 'delivery')),
    delivery_type VARCHAR(30) DEFAULT 'pickup',
    delivery_slot TIMESTAMPTZ,
    needed_by TEXT,
    delivery_address TEXT,
    delivery_notes TEXT,
    notes TEXT,
    status TEXT NOT NULL
        CHECK (status in ('awaiting_payment', 'paid', 'expired', 'cancelled', 'completed', 'refunded', 'draft', 'pending', 'confirmed', 'ready', 'delivered')),
    payment_status VARCHAR(50) DEFAULT 'pending',
    business_date DATE NOT NULL DEFAULT CURRENT_DATE,
    currency TEXT NOT NULL DEFAULT 'INR' CHECK (currency ~ '^[A-Z]{3}$'),
    total_minor INT NOT NULL DEFAULT 0 CHECK (total_minor >= 0),
    subtotal_minor BIGINT NOT NULL DEFAULT 0,
    discount_minor BIGINT NOT NULL DEFAULT 0,
    delivery_fee_minor BIGINT NOT NULL DEFAULT 0,
    total_amount_minor BIGINT NOT NULL DEFAULT 0,
    total_cost_minor BIGINT NOT NULL DEFAULT 0,
    estimated_profit_minor BIGINT GENERATED ALWAYS AS (
        total_amount_minor - total_cost_minor - delivery_fee_minor
    ) STORED,
    hold_expires_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    custom_attributes JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX orders_merchant_idx ON orders (merchant_id, created_at DESC);
CREATE INDEX orders_awaiting_payment_idx ON orders (hold_expires_at)
  WHERE status = 'awaiting_payment';

CREATE OR REPLACE FUNCTION fn_sync_orders_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
        NEW.order_number := 'ORD-' || COALESCE(NEW.number::text, substr(gen_random_uuid()::text, 1, 8));
    END IF;
    IF NEW.total_minor > 0 AND (NEW.total_amount_minor IS NULL OR NEW.total_amount_minor = 0) THEN
        NEW.total_amount_minor := NEW.total_minor;
    ELSIF NEW.total_amount_minor > 0 AND (NEW.total_minor IS NULL OR NEW.total_minor = 0) THEN
        NEW.total_minor := NEW.total_amount_minor::INT;
    END IF;
    IF NEW.fulfilment IS NOT NULL AND NEW.delivery_type IS NULL THEN
        NEW.delivery_type := NEW.fulfilment;
    ELSIF NEW.delivery_type IS NOT NULL AND NEW.fulfilment IS NULL THEN
        NEW.fulfilment := NEW.delivery_type;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_sync
BEFORE INSERT OR UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION fn_sync_orders_fields();

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id),
    product_name TEXT,
    variant_name TEXT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price_minor INT NOT NULL DEFAULT 0 CHECK (unit_price_minor >= 0),
    unit_cost_minor BIGINT NOT NULL DEFAULT 0,
    total_price_minor BIGINT GENERATED ALWAYS AS (unit_price_minor * quantity) STORED,
    total_cost_minor BIGINT GENERATED ALWAYS AS (unit_cost_minor * quantity) STORED
);
CREATE INDEX order_items_order_idx ON order_items (order_id);

CREATE OR REPLACE FUNCTION fn_sync_order_items()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.merchant_id IS NULL THEN
        SELECT merchant_id INTO NEW.merchant_id FROM orders WHERE id = NEW.order_id;
    END IF;
    IF NEW.product_name IS NULL OR NEW.product_name = '' THEN
        SELECT p.name INTO NEW.product_name
        FROM product_variants pv
        JOIN products p ON pv.product_id = p.id
        WHERE pv.id = NEW.variant_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_items_sync
BEFORE INSERT OR UPDATE ON order_items
FOR EACH ROW EXECUTE FUNCTION fn_sync_order_items();

CREATE TABLE order_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    event TEXT NOT NULL,
    from_status TEXT,
    to_status TEXT,
    actor TEXT NOT NULL CHECK (actor in ('agent', 'customer', 'merchant', 'system', 'paypal')),
    details JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX order_events_order_idx ON order_events (order_id, created_at);

CREATE TABLE order_timeline (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    from_status VARCHAR(50),
    to_status VARCHAR(50) NOT NULL,
    triggered_by VARCHAR(50) NOT NULL,
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider in ('paypal')),
    provider_order_id TEXT NOT NULL,
    provider_capture_id TEXT,
    status TEXT NOT NULL
        CHECK (status in ('created', 'approved', 'completed', 'denied', 'refunded', 'failed')),
    currency TEXT NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    amount_minor INT NOT NULL CHECK (amount_minor >= 0),
    approve_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (provider, provider_order_id)
);
CREATE UNIQUE INDEX payments_capture_idx
  ON payments (provider, provider_capture_id) WHERE provider_capture_id IS NOT NULL;
CREATE INDEX payments_order_idx ON payments (order_id);

CREATE TABLE refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    refund_amount_minor BIGINT NOT NULL,
    reason TEXT,
    is_restocked BOOLEAN DEFAULT true,
    processed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id),
    requested_item_name VARCHAR(150) NOT NULL,
    variant_id UUID REFERENCES product_variants(id),
    quantity_requested INT DEFAULT 1,
    reason VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE daily_closing_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    UPDATE daily_stock
    SET held = held + p_quantity
    WHERE variant_id = p_variant_id
      AND business_date = CURRENT_DATE
      AND (opening + restocked - held - sold - counter_sales) >= p_quantity;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK: Item is sold out or unavailable';
    END IF;

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

    UPDATE daily_stock
    SET held = held - v_quantity,
        sold = sold + v_quantity
    WHERE variant_id = v_variant_id AND business_date = CURRENT_DATE;

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
        WHERE variant_id = r.variant_id AND business_date = CURRENT_DATE;

        UPDATE stock_holds SET status = 'expired' WHERE id = r.id;
        v_released_count := v_released_count + 1;
    END LOOP;

    RETURN v_released_count;
END;
$$ LANGUAGE plpgsql;

-- 4. Record Offline Counter Sales
CREATE OR REPLACE FUNCTION record_counter_sale(
    p_variant_id UUID,
    p_quantity INT
) RETURNS INT AS $$
DECLARE
    v_new_available INT;
BEGIN
    UPDATE daily_stock
    SET counter_sales = counter_sales + p_quantity
    WHERE variant_id = p_variant_id AND business_date = CURRENT_DATE
    RETURNING available INTO v_new_available;

    RETURN v_new_available;
END;
$$ LANGUAGE plpgsql;

-- =======================================================
-- 6. TRIGGERS
-- =======================================================

CREATE TRIGGER trg_merchants_touch BEFORE UPDATE ON merchants
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TRIGGER trg_orders_touch BEFORE UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TRIGGER channel_connections_updated_at BEFORE UPDATE ON channel_connections
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER customers_updated_at BEFORE UPDATE ON customers
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER conversations_updated_at BEFORE UPDATE ON conversations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER products_updated_at BEFORE UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER product_variants_updated_at BEFORE UPDATE ON product_variants
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER daily_stock_updated_at BEFORE UPDATE ON daily_stock
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER payments_updated_at BEFORE UPDATE ON payments
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

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
    IF (OLD.payment_status <> 'paid' AND NEW.payment_status = 'paid') OR
       (OLD.status <> 'paid' AND NEW.status = 'paid') THEN
        UPDATE customers
        SET lifetime_orders_count = lifetime_orders_count + 1,
            lifetime_spent_minor = lifetime_spent_minor + NEW.total_amount_minor
        WHERE id = NEW.customer_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_paid AFTER UPDATE OF status ON orders
FOR EACH ROW EXECUTE FUNCTION fn_update_customer_stats();

-- =======================================================
-- 7. ESSENTIAL VIEWS (AI AGENT & ANALYTICS)
-- =======================================================

-- View 1: Real-Time Available Stock for AI Agent
CREATE OR REPLACE VIEW v_active_daily_inventory AS
SELECT 
    p.merchant_id,
    p.id AS product_id,
    p.name AS product_name,
    pv.id AS variant_id,
    COALESCE(pv.variant_name, pv.name) AS variant_name,
    COALESCE(pv.selling_price_minor, pv.price_minor) AS selling_price_minor,
    ds.available,
    sr.menu_image_url
FROM products p
JOIN product_variants pv ON p.id = pv.product_id
JOIN daily_stock ds ON pv.id = ds.variant_id AND ds.business_date = CURRENT_DATE
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
WHERE e.status IN ('pending', 'open');

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
-- 8. INDEXES & RLS
-- =======================================================

CREATE INDEX idx_daily_stock_variant_date ON daily_stock(variant_id, business_date);
CREATE INDEX idx_stock_holds_active ON stock_holds(variant_id, status, expires_at);
CREATE INDEX idx_orders_merchant_date ON orders(merchant_id, created_at DESC);
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at ASC);
CREATE INDEX idx_story_registry_lookup ON story_registry(merchant_id, ig_story_id);
CREATE INDEX idx_orders_custom_gin ON orders USING GIN (custom_attributes);
CREATE INDEX idx_customers_custom_gin ON customers USING GIN (custom_attributes);

ALTER TABLE merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE merchant_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE login_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_onboarding ENABLE ROW LEVEL SECURITY;
