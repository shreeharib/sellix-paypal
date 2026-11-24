-- Instagram login gives two ids for the shop's account: the professional account id
-- (`user_id` from /me, used by webhooks; kept in external_account_id) and the app-scoped user id
-- (`id` from /me). Meta's data-deletion callback names the app-scoped one, so keep it too.
ALTER TABLE channel_connections ADD COLUMN IF NOT EXISTS app_user_id TEXT;
CREATE INDEX IF NOT EXISTS channel_connections_app_user_idx
    ON channel_connections (app_user_id) WHERE app_user_id IS NOT NULL;
