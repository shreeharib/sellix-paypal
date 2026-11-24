-- Migration: 20261124010001_order_items_stock_counted.sql
-- Goal: made-to-order and always-available items are sold without a count.
--
-- An order line for such an item takes no stock: no hold, no daily_stock change when it is
-- placed, paid, expired, cancelled or refunded. The line records which kind it was when the
-- order was placed, so a later change of the item's stock mode can't make paying or expiring
-- the order touch stock it never held. Existing lines were all counted.

ALTER TABLE order_items
    ADD COLUMN IF NOT EXISTS stock_counted BOOLEAN NOT NULL DEFAULT TRUE;
