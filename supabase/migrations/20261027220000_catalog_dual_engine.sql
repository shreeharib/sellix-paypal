-- Migration: 20261027220000_catalog_dual_engine.sql
-- Goal: Enriched attributes, compare-at MRP pricing, and fast trigram fuzzy alias search

CREATE EXTENSION IF NOT EXISTS pg_trgm;

ALTER TABLE products
ADD COLUMN IF NOT EXISTS attributes JSONB NOT NULL DEFAULT '{}';

ALTER TABLE product_variants
ADD COLUMN IF NOT EXISTS compare_at_price_minor BIGINT DEFAULT 0;

ALTER TABLE product_variants
ADD COLUMN IF NOT EXISTS attributes JSONB NOT NULL DEFAULT '{}';

-- Trigram index for ultra-fast customer slang & typo matching in DMs (< 1ms)
CREATE INDEX IF NOT EXISTS product_aliases_trgm 
ON product_aliases USING gin (alias_text gin_trgm_ops);

-- Prevent duplicate aliases per product
CREATE UNIQUE INDEX IF NOT EXISTS product_aliases_unique_idx 
ON product_aliases (product_id, lower(alias_text));
