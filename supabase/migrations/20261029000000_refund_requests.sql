-- A refund is recorded as a request before PayPal is called (D4), so money PayPal sends back
-- is always on record:
--   pending   -> PayPal not yet confirmed (its response, the PAYMENT.CAPTURE.REFUNDED webhook
--                or the reconcile job settles it)
--   completed -> PayPal confirmed; the order is refunded and a `refunds` row written
--   failed    -> PayPal refused; the order stays paid
-- `refunds` keeps meaning "money returned", so reports reading it need no change.

CREATE TABLE refund_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    amount_minor BIGINT NOT NULL CHECK (amount_minor >= 0),
    reason TEXT,
    is_restocked BOOLEAN NOT NULL DEFAULT true,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed')),
    provider_refund_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One refund per order at a time: a double-click reuses the open request.
CREATE UNIQUE INDEX refund_requests_one_open_per_order
    ON refund_requests (order_id) WHERE status IN ('pending', 'completed');
CREATE UNIQUE INDEX refund_requests_provider_idx
    ON refund_requests (provider_refund_id) WHERE provider_refund_id IS NOT NULL;
CREATE INDEX refund_requests_pending_idx ON refund_requests (created_at) WHERE status = 'pending';

ALTER TABLE refund_requests ENABLE ROW LEVEL SECURITY;
