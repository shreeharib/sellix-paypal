-- Stories, photos and posts (agent-phase-2.md section 11).
--
-- Meta's rule: never store or cache story media on our servers. story_registry keeps the CDN
-- link and what code derived from the story (which products it shows), never the image.

ALTER TABLE story_registry
    ADD COLUMN cdn_url TEXT,
    ADD COLUMN products JSONB NOT NULL DEFAULT '[]',  -- variant ids the story shows
    ADD COLUMN confidence NUMERIC(3, 2),
    ADD COLUMN caption TEXT,
    -- false: guessed by the vision model on a first reply; the merchant confirms on Today
    ADD COLUMN confirmed_by_merchant BOOLEAN NOT NULL DEFAULT false;

-- Vision results for customer photos, keyed by a hash of the media link: a photo is sent to
-- the vision model at most once.
CREATE TABLE media_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    media_key TEXT NOT NULL,
    result JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (merchant_id, media_key)
);

-- The shop's own Instagram post for a product, shared with MEDIA_SHARE (share_post).
CREATE TABLE product_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    ig_media_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (merchant_id, product_id)
);

-- Today's menu photo, uploaded by the merchant (their own upload: storing it is fine).
ALTER TABLE merchants ADD COLUMN menu_image_url TEXT;

ALTER TABLE media_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_posts ENABLE ROW LEVEL SECURITY;
