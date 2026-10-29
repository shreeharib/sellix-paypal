-- The outbox (agent-phase-2.md section 13.2): every outbound message is a row here before
-- anything is sent. A job sends rows in order per conversation, retries what can be retried,
-- and records Instagram's message id. Queuing the same idempotency key twice does nothing.
--
-- One chat message (messages row) can go out as up to two parts: Instagram allows 1,000
-- UTF-8 bytes per message, so a long reply is split at a sentence.
--
-- status:
--   queued          waiting to be sent (next_attempt_at says when)
--   sending         a worker is sending it now (stuck > 2 minutes -> the sweep recovers it)
--   sent            Instagram accepted it
--   failed          gave up: a permanent error, or retries ran out
--   pending_window  Instagram's 24-hour window is closed; sent when the customer writes again

CREATE TABLE outbound_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Queue order: rows queued in one transaction share created_at, so order by this instead.
    seq BIGINT GENERATED ALWAYS AS IDENTITY,
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    part SMALLINT NOT NULL DEFAULT 1 CHECK (part >= 1),
    kind TEXT NOT NULL DEFAULT 'text' CHECK (kind IN ('text')),
    payload JSONB NOT NULL,
    window_policy TEXT NOT NULL DEFAULT 'standard'
        CHECK (window_policy IN ('standard', 'human_agent', 'when_open')),
    status TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'sending', 'sent', 'failed', 'pending_window')),
    attempts INT NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_error TEXT,
    provider_message_id TEXT,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (idempotency_key, part)
);

CREATE INDEX outbound_messages_queue_idx
    ON outbound_messages (conversation_id, seq)
    WHERE status IN ('queued', 'sending');
CREATE INDEX outbound_messages_due_idx ON outbound_messages (next_attempt_at) WHERE status = 'queued';
CREATE INDEX outbound_messages_provider_idx
    ON outbound_messages (merchant_id, provider_message_id) WHERE provider_message_id IS NOT NULL;

ALTER TABLE outbound_messages ENABLE ROW LEVEL SECURITY;
