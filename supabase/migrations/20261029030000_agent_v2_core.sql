-- The v2 agent (agent-phase-2.md sections 6, 7, 16 and 19): conversation state owned by code,
-- quotes the customer must see before confirming, and a trace of every turn and step.

-- Which engine answers a shop's customers. v2 runs behind this flag until it has proven itself:
--   shadow: v1 replies; v2 runs on the same messages without writing or sending anything
--   draft:  v2 replies, but each reply waits for the merchant's approval in Chats
ALTER TABLE merchants
    ADD COLUMN agent_engine TEXT NOT NULL DEFAULT 'v1'
        CHECK (agent_engine IN ('v1', 'v2', 'shadow', 'draft')),
    -- Phrases the agent must never promise (Settings), on top of the global list.
    ADD COLUMN never_promise TEXT[] NOT NULL DEFAULT '{}';

-- Code owns the stage; the model can't set it. Transitions happen inside tools and payment or
-- expiry handlers, with the conversation row locked.
ALTER TABLE conversations
    ADD COLUMN order_stage TEXT NOT NULL DEFAULT 'browsing'
        CHECK (order_stage IN (
            'browsing', 'collecting_details', 'awaiting_confirmation', 'payment_pending',
            'handed_off'
        )),
    ADD COLUMN order_draft JSONB NOT NULL DEFAULT '{}';

-- The agent can hand a chat to the merchant (hand_off_to_owner); it then stops replying there.
-- Why it handed off is in the merchant's Ask me question.
ALTER TABLE conversations DROP CONSTRAINT conversations_agent_paused_reason_check;
ALTER TABLE conversations
    ADD CONSTRAINT conversations_agent_paused_reason_check
        CHECK (agent_paused_reason IN ('merchant_replied', 'merchant_switched_off', 'handed_off'));

-- A priced offer, sent to the customer as a card. It can be confirmed only once the card was
-- delivered (shown_message_id), by a later customer message or tap, before expires_at.
CREATE TABLE quotes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    business_date DATE NOT NULL,
    lines JSONB NOT NULL,  -- [{variant_id, label, product, variant, quantity, unit_price_minor}]
    currency TEXT NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    total_minor BIGINT NOT NULL CHECK (total_minor >= 0),
    fulfilment TEXT CHECK (fulfilment IN ('pickup', 'delivery')),
    delivery_address TEXT,
    needed_by TEXT,
    notes TEXT,
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'superseded', 'confirmed', 'expired')),
    expires_at TIMESTAMPTZ NOT NULL,
    shown_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    shown_at TIMESTAMPTZ,
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX quotes_conversation_idx ON quotes (conversation_id, created_at DESC);
-- One order per quote: confirming twice returns the same order.
CREATE UNIQUE INDEX quotes_order_idx ON quotes (order_id) WHERE order_id IS NOT NULL;
ALTER TABLE quotes ENABLE ROW LEVEL SECURITY;

-- One row per agent turn: what it saw, what it used, what it cost, how it ended.
CREATE TABLE agent_turns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    trigger_message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'running'
        CHECK (status IN ('running', 'replied', 'fallback', 'gated', 'handed_off')),
    mode TEXT NOT NULL DEFAULT 'live' CHECK (mode IN ('live', 'shadow', 'draft')),
    would_send TEXT,  -- shadow mode: the reply v2 would have sent
    stage_before TEXT,
    stage_after TEXT,
    playbook TEXT,
    prompt_refs TEXT[] NOT NULL DEFAULT '{}',  -- id@version of every prompt used
    models TEXT[] NOT NULL DEFAULT '{}',
    model_calls INT NOT NULL DEFAULT 0,
    tool_calls INT NOT NULL DEFAULT 0,
    input_tokens INT NOT NULL DEFAULT 0,
    output_tokens INT NOT NULL DEFAULT 0,
    cost_usd NUMERIC(12, 6),
    latency_ms INT,
    error TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    -- A retried turn for the same customer message resumes this row instead of starting over.
    UNIQUE (conversation_id, trigger_message_id)
);
CREATE INDEX agent_turns_merchant_idx ON agent_turns (merchant_id, started_at DESC);
ALTER TABLE agent_turns ENABLE ROW LEVEL SECURITY;

-- Each model call and tool call of a turn. A resumed turn replays these instead of running
-- them again, so a write (an order, a payment link, a message) never happens twice.
CREATE TABLE turn_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    turn_id UUID NOT NULL REFERENCES agent_turns(id) ON DELETE CASCADE,
    step INT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('model', 'tool')),
    name TEXT NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    request JSONB NOT NULL DEFAULT '{}',
    result JSONB NOT NULL DEFAULT '{}',
    input_tokens INT,
    output_tokens INT,
    latency_ms INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX turn_steps_turn_idx ON turn_steps (turn_id, step);
ALTER TABLE turn_steps ENABLE ROW LEVEL SECURITY;
