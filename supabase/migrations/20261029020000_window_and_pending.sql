-- Late merchant answers and Instagram's 24-hour window (agent-phase-2.md section 10.3).
--
-- answer_delivery: how the merchant's answer reached (or will reach) the customer
--   sent            the agent passed it on inside the 24 hours
--   pending_window  the window had closed; it's passed on when the customer writes again
--   human_agent     sent as written with Instagram's HUMAN_AGENT tag (24 hours to 7 days)
--   expired         more than 7 days after the customer's last message: can't be sent
-- window_warned_at: when the merchant was told the customer's window closes within 2 hours.
-- The countdown itself is computed from conversations.last_customer_message_at, which moves
-- every time the customer writes, so it isn't stored here.

ALTER TABLE escalations
    ADD COLUMN answer_delivery TEXT
        CHECK (answer_delivery IN ('sent', 'pending_window', 'human_agent', 'expired')),
    ADD COLUMN window_warned_at TIMESTAMPTZ;

CREATE INDEX escalations_pending_answer_idx
    ON escalations (conversation_id) WHERE answer_delivery = 'pending_window';
