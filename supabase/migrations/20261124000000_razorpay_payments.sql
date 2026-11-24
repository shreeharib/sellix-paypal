-- Razorpay replaces PayPal (24 Nov 2026).
--
-- Each shop connects its own Razorpay account: its key id, key secret (encrypted with
-- TOKEN_ENCRYPTION_KEYS, like channel tokens) and the webhook secret sellix makes for it. The
-- shop's webhook address is /webhooks/razorpay/<webhook_token>, so a delivery says whose secret
-- checks it. Money goes straight to the shop's own account.
CREATE TABLE payment_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'razorpay' CHECK (provider IN ('razorpay')),
    key_id TEXT NOT NULL,
    key_secret_encrypted TEXT NOT NULL,
    webhook_secret_encrypted TEXT NOT NULL,
    webhook_token TEXT NOT NULL UNIQUE,
    mode TEXT NOT NULL CHECK (mode IN ('test', 'live')),
    verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_webhook_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (merchant_id, provider)
);
ALTER TABLE payment_accounts ENABLE ROW LEVEL SECURITY;

-- A Razorpay payment row: provider_order_id is the Payment Link id (plink_...),
-- provider_capture_id the payment id (pay_...), provider_checkout_id Razorpay's own order behind
-- the link (order_..., which a payment.failed event names), provider_account the key id the link
-- was made with (so a later look-up uses the same account even after the shop changes keys).
ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider_checkout_id TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider_account TEXT;
CREATE INDEX IF NOT EXISTS payments_checkout_idx
    ON payments (provider, provider_checkout_id) WHERE provider_checkout_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS payments_open_idx
    ON payments (provider, created_at) WHERE status = 'created';

-- A link can also end unpaid: cancelled by sellix (the order expired or was cancelled) or
-- expired by Razorpay.
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_status_check;
ALTER TABLE payments ADD CONSTRAINT payments_status_check
    CHECK (status IN ('created', 'approved', 'completed', 'denied', 'refunded', 'failed',
                      'cancelled', 'expired'));

-- The method is unknown until the customer pays (then Razorpay says which), so a new link's row
-- has none. 'paypal_wallet' stays allowed for rows made before the switch.
ALTER TABLE payments ALTER COLUMN method DROP DEFAULT;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE payments ADD CONSTRAINT payments_method_check
    CHECK (method IN ('upi', 'card', 'netbanking', 'wallet', 'emi', 'cardless_emi', 'paylater',
                      'bank_transfer', 'app', 'other', 'cash', 'simulator', 'paypal_wallet'));

ALTER TABLE webhook_events DROP CONSTRAINT IF EXISTS webhook_events_source_check;
ALTER TABLE webhook_events ADD CONSTRAINT webhook_events_source_check
    CHECK (source IN ('meta', 'paypal', 'simulator', 'razorpay'));

ALTER TABLE order_events DROP CONSTRAINT IF EXISTS order_events_actor_check;
ALTER TABLE order_events ADD CONSTRAINT order_events_actor_check
    CHECK (actor IN ('agent', 'customer', 'merchant', 'system', 'paypal', 'simulator', 'razorpay'));
