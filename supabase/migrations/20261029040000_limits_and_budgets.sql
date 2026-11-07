-- Inbound protection (agent-phase-2.md section 12): per-shop AI budget, and the index the
-- per-customer turn limits count with. Limits are counted over agent_turns and messages, so
-- they survive restarts and work across workers (no Redis).

-- US dollars per day; NULL uses the AGENT_DAILY_BUDGET_USD default.
ALTER TABLE merchants ADD COLUMN ai_daily_budget_usd NUMERIC(10, 4)
    CHECK (ai_daily_budget_usd IS NULL OR ai_daily_budget_usd >= 0);

CREATE INDEX agent_turns_conversation_idx ON agent_turns (conversation_id, started_at DESC);
CREATE INDEX messages_conversation_sender_idx ON messages (conversation_id, sender, created_at DESC);
