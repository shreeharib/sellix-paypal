-- A reply from the shop owner pauses the assistant for that chat for a while, not for ever
-- (24 Nov 2026).
--
-- When the owner replies (typed in Instagram, or sent from the app), the assistant steps back
-- with reason 'merchant_replied' until agent_paused_until (AGENT_RESUME_AFTER_MERCHANT_HOURS,
-- 12 by default). The next customer message after that switches it back on. An owner's
-- "I'll reply myself" switch-off has no end time and stays off.
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS agent_paused_until TIMESTAMPTZ;

-- Chats paused by an owner's reply before this change: the pause ends 12 hours after the owner's
-- latest message in that chat.
UPDATE conversations c
SET agent_paused_until = COALESCE(
        (SELECT max(m.created_at) FROM messages m
         WHERE m.conversation_id = c.id AND m.sender = 'merchant'),
        c.updated_at,
        NOW()
    ) + INTERVAL '12 hours'
WHERE c.agent_paused_reason = 'merchant_replied'
  AND NOT c.agent_active
  AND c.agent_paused_until IS NULL;
