-- New shops start with the assistant off, on the v2 engine (24 Nov 2026).
--
-- The first "Continue with Instagram" creates the shop, and until now the assistant answered
-- real customers straight away, before the owner had set anything up. Now it waits until the
-- onboarding is finished (PUT /v1/onboarding with complete: true switches it on), and new shops
-- use the v2 engine. Existing shops keep what they have: only the column defaults change.
ALTER TABLE merchants ALTER COLUMN agent_enabled SET DEFAULT false;
ALTER TABLE merchants ALTER COLUMN agent_engine SET DEFAULT 'v2';
