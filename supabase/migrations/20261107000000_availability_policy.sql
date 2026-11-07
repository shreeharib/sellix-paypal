-- Migration: 20261107000000_availability_policy.sql
-- Goal: sell an item on one fixed day (a Diwali cake for pickup on 9 Nov) and stop taking
--       orders on a last order date the merchant picks. Quantity stays in daily_stock: the
--       total for a fixed-date item is that day's opening stock.

ALTER TABLE products ADD COLUMN IF NOT EXISTS available_on DATE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS order_by_date DATE;

ALTER TABLE products DROP CONSTRAINT IF EXISTS products_order_by_before_available_check;
ALTER TABLE products ADD CONSTRAINT products_order_by_before_available_check
    CHECK (order_by_date IS NULL OR available_on IS NULL OR order_by_date <= available_on);

-- Customers' menus and the order check look the policy up by product.
CREATE INDEX IF NOT EXISTS products_available_on_idx
    ON products (merchant_id, available_on) WHERE available_on IS NOT NULL;
