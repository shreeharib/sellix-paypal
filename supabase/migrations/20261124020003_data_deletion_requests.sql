-- Shop deletions and Meta's data-deletion requests (24 Nov 2026).
--
-- DELETE /v1/shop and Meta's data-deletion callback delete a shop and everything it stores (every
-- shop table cascades from merchants). This table keeps only a confirmation code, where the
-- request came from and what happened, so <PUBLIC_BASE_URL>/data-deletion?code=... can tell the
-- person their data was deleted. It holds no shop id, account id or other personal data.
CREATE TABLE data_deletion_requests (
    code TEXT PRIMARY KEY,
    source TEXT NOT NULL CHECK (source IN ('app', 'meta')),
    status TEXT NOT NULL CHECK (status IN ('deleted', 'no_data')),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE data_deletion_requests ENABLE ROW LEVEL SECURITY;
