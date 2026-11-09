-- The built-in payment simulator (a hosted page with Accept / Reject buttons that sends a webhook)
-- records its payments with provider = 'simulator' and method = 'simulator', and its webhook
-- deliveries with source = 'simulator'. The app only offers it outside production
-- (PAYMENT_PROVIDER=simulator and APP_ENV not prod); the database just has to allow the values.
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_provider_check;
ALTER TABLE payments ADD CONSTRAINT payments_provider_check
    CHECK (provider IN ('paypal', 'razorpay', 'cashfree', 'upi_manual', 'manual', 'cash', 'stripe', 'simulator'));

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE payments ADD CONSTRAINT payments_method_check
    CHECK (method IN ('upi', 'card', 'paypal_wallet', 'cash', 'simulator'));

ALTER TABLE webhook_events DROP CONSTRAINT IF EXISTS webhook_events_source_check;
ALTER TABLE webhook_events ADD CONSTRAINT webhook_events_source_check
    CHECK (source IN ('meta', 'paypal', 'simulator'));

-- Orders paid through the simulator are recorded in the order's history as actor 'simulator'.
ALTER TABLE order_events DROP CONSTRAINT IF EXISTS order_events_actor_check;
ALTER TABLE order_events ADD CONSTRAINT order_events_actor_check
    CHECK (actor IN ('agent', 'customer', 'merchant', 'system', 'paypal', 'simulator'));
