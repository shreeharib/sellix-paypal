-- Refresh-token grace (24 Nov 2026).
--
-- A refresh token that was rotated out less than 2 minutes ago is still accepted once more: it
-- answers with a new access token and the session's current refresh token, so a refresh response
-- lost on a mobile connection (or two refreshes sent at once) no longer signs the merchant out.
-- After the 2 minutes, reusing it still revokes the session.
--
-- refresh_rotated_at: when the previous token was rotated out.
-- refresh_token_encrypted: the current refresh token, encrypted with TOKEN_ENCRYPTION_KEYS, so the
-- grace answer can repeat it; it is replaced on every rotation and cleared when the session ends.
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS refresh_rotated_at TIMESTAMPTZ;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS refresh_token_encrypted TEXT;
CREATE INDEX IF NOT EXISTS sessions_previous_refresh_idx
    ON sessions (previous_refresh_token_hash) WHERE previous_refresh_token_hash IS NOT NULL;
