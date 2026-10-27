-- Migration: 20261027200000_stock_holds_order_sync.sql
-- Goal: Make stock_holds the single source of truth for stock reservations,
--       linking holds to orders and making conversation_id optional.

ALTER TABLE stock_holds ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES orders(id) ON DELETE CASCADE;
ALTER TABLE stock_holds ALTER COLUMN conversation_id DROP NOT NULL;

-- Update release_expired_holds() to synchronize both daily_stock and orders
CREATE OR REPLACE FUNCTION release_expired_holds() 
RETURNS INT AS $$
DECLARE
    v_released_count INT := 0;
    r RECORD;
BEGIN
    FOR r IN 
        SELECT id, variant_id, quantity, order_id, created_at 
        FROM stock_holds 
        WHERE status = 'held' AND expires_at < NOW()
        FOR UPDATE
    LOOP
        UPDATE daily_stock
        SET held = held - r.quantity
        WHERE variant_id = r.variant_id 
          AND business_date = COALESCE(
              (SELECT o.business_date FROM orders o WHERE o.id = r.order_id),
              r.created_at::date,
              CURRENT_DATE
          );

        UPDATE stock_holds SET status = 'expired' WHERE id = r.id;

        IF r.order_id IS NOT NULL THEN
            UPDATE orders 
            SET status = 'expired', 
                hold_expires_at = NULL,
                updated_at = NOW()
            WHERE id = r.order_id AND status = 'awaiting_payment';
        END IF;

        v_released_count := v_released_count + 1;
    END LOOP;

    RETURN v_released_count;
END;
$$ LANGUAGE plpgsql;

-- Update convert_stock_hold(p_hold_id) to support order linkage
CREATE OR REPLACE FUNCTION convert_stock_hold(p_hold_id UUID) 
RETURNS VOID AS $$
DECLARE
    v_variant_id UUID;
    v_quantity INT;
    v_status VARCHAR(30);
    v_order_id UUID;
BEGIN
    SELECT variant_id, quantity, status, order_id 
    INTO v_variant_id, v_quantity, v_status, v_order_id
    FROM stock_holds WHERE id = p_hold_id FOR UPDATE;

    IF v_status <> 'held' THEN
        RAISE EXCEPTION 'Hold is already converted or expired';
    END IF;

    UPDATE daily_stock
    SET held = held - v_quantity,
        sold = sold + v_quantity
    WHERE variant_id = v_variant_id 
      AND business_date = COALESCE(
          (SELECT o.business_date FROM orders o WHERE o.id = v_order_id),
          CURRENT_DATE
      );

    UPDATE stock_holds SET status = 'converted' WHERE id = p_hold_id;
END;
$$ LANGUAGE plpgsql;

