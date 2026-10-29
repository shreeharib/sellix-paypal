-- Agent memory (agent-phase-2.md section 8): per customer (episodic) and per shop (semantic,
-- procedural). One shop never sees another shop's memory of the same person.

-- Facts a customer told us, written only through the remember_customer_fact tool. Keys are an
-- allow-list: never payment details, other people's data, or health beyond what they
-- volunteered for their order. A newer fact replaces the older one for the same key.
CREATE TABLE customer_memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    key TEXT NOT NULL CHECK (key IN (
        'name', 'preferred_language', 'address', 'usual_order', 'dietary_note', 'occasion'
    )),
    value JSONB NOT NULL,
    source_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    confidence NUMERIC(3, 2) NOT NULL DEFAULT 0.9 CHECK (confidence BETWEEN 0 AND 1),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (merchant_id, customer_id, key)
);

-- Older parts of long conversations, summarised by a background job, never with amounts.
CREATE TABLE conversation_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    summary TEXT NOT NULL,
    covers_until_message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    message_count INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX conversation_summaries_idx ON conversation_summaries (conversation_id, created_at DESC);

-- Code-mixed words the agent should understand; merchant_id NULL is the global glossary.
CREATE TABLE glossary_terms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID REFERENCES merchants(id) ON DELETE CASCADE,
    term TEXT NOT NULL,
    meaning TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX glossary_terms_unique_idx
    ON glossary_terms (COALESCE(merchant_id, '00000000-0000-0000-0000-000000000000'), lower(term));

INSERT INTO glossary_terms (merchant_id, term, meaning) VALUES
    (NULL, 'seri / sari', 'ok, yes (Tamil)'),
    (NULL, 'venum', 'want (Tamil)'),
    (NULL, 'venam / vendam', 'don''t want, no (Tamil)'),
    (NULL, 'evlo', 'how much (Tamil)'),
    (NULL, 'irukka', 'is it available? (Tamil)'),
    (NULL, 'naalaikku', 'tomorrow (Tamil)'),
    (NULL, 'rendu', 'two (Tamil)'),
    (NULL, 'moonu', 'three (Tamil)'),
    (NULL, 'chahiye', 'want (Hindi)'),
    (NULL, 'kitna', 'how much (Hindi)'),
    (NULL, 'kal', 'tomorrow or yesterday (Hindi): ask which');

-- "Always answer this way": saved when the merchant ticks it while answering in Ask me.
CREATE TABLE merchant_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    source_escalation_id UUID REFERENCES escalations(id) ON DELETE SET NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX merchant_rules_idx ON merchant_rules (merchant_id) WHERE active;

ALTER TABLE customer_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE glossary_terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE merchant_rules ENABLE ROW LEVEL SECURITY;
