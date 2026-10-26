-- The shop's weekly opening hours and one-off closures, so the agent can tell exactly whether
-- the shop is open now. Null until the merchant sets them. Shape (validated by the API):
-- {"week": {"tue": [{"opens": "09:00", "closes": "20:00"}], ...}, "closed_dates": ["2026-11-01"]}
alter table merchants add column opening_hours jsonb;
