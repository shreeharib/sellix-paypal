-- Migration: 20261027210000_stock_modes_and_rollover.sql
-- Goal: Universal stock modes, shelf-life attributes, and nightly ledger rollover

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS stock_mode VARCHAR(20) DEFAULT 'daily' 
CHECK (stock_mode IN ('daily', 'inventory', 'made_to_order', 'unlimited'));

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS shelf_life_days INT DEFAULT NULL;

ALTER TABLE product_variants 
ADD COLUMN IF NOT EXISTS stock_mode VARCHAR(20) DEFAULT NULL 
CHECK (stock_mode IS NULL OR stock_mode IN ('daily', 'inventory', 'made_to_order', 'unlimited'));

ALTER TABLE product_variants 
ADD COLUMN IF NOT EXISTS shelf_life_days INT DEFAULT NULL;

-- Stored procedure to roll forward perpetual and multi-day stock from yesterday to today
CREATE OR REPLACE FUNCTION rollover_daily_stock(
    p_merchant_id UUID, 
    p_from_date DATE, 
    p_to_date DATE
) RETURNS INT AS $$
DECLARE
    v_rolled_count INT := 0;
    r RECORD;
    v_effective_mode VARCHAR(20);
    v_effective_shelf_life INT;
BEGIN
    FOR r IN
        SELECT 
            ds.variant_id, 
            ds.available,
            p.stock_mode AS prod_stock_mode,
            pv.stock_mode AS var_stock_mode,
            p.shelf_life_days AS prod_shelf_life,
            pv.shelf_life_days AS var_shelf_life
        FROM daily_stock ds
        JOIN product_variants pv ON pv.id = ds.variant_id
        JOIN products p ON p.id = pv.product_id
        WHERE ds.merchant_id = p_merchant_id
          AND ds.business_date = p_from_date
          AND ds.available > 0
          AND pv.is_active = TRUE
          AND p.is_active = TRUE
    LOOP
        v_effective_mode := COALESCE(r.var_stock_mode, r.prod_stock_mode, 'daily');
        v_effective_shelf_life := COALESCE(r.var_shelf_life, r.prod_shelf_life);

        -- Carry forward if perpetual 'inventory' OR if multi-day fresh (shelf_life_days > 1)
        IF v_effective_mode = 'inventory' OR (v_effective_shelf_life IS NOT NULL AND v_effective_shelf_life > 1) THEN
            -- Do not overwrite or double-count if merchant already initialized today's stock
            IF NOT EXISTS (
                SELECT 1 FROM daily_stock 
                WHERE variant_id = r.variant_id AND business_date = p_to_date
            ) THEN
                INSERT INTO daily_stock (
                    merchant_id, variant_id, business_date, opening
                ) VALUES (
                    p_merchant_id, r.variant_id, p_to_date, r.available
                );

                v_rolled_count := v_rolled_count + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN v_rolled_count;
END;
$$ LANGUAGE plpgsql;
