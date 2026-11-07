-- The simulator (agent-phase-2.md section 17): a web chat that goes through the same
-- pipeline as Instagram. Its messages are stored like any other channel's but never leave
-- sellix. customers.channel already allows 'webchat'.

ALTER TABLE channel_connections DROP CONSTRAINT channel_connections_channel_check;
ALTER TABLE channel_connections
    ADD CONSTRAINT channel_connections_channel_check
        CHECK (channel IN ('instagram', 'whatsapp', 'webchat'));
