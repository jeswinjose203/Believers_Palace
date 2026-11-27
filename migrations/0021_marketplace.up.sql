CREATE TABLE marketplace_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    scope TEXT NOT NULL CHECK (scope IN ('community', 'shop')),
    sort_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (name, scope)
);

CREATE INDEX idx_marketplace_categories_scope ON marketplace_categories(scope, active, sort_order);

CREATE TABLE community_advertisements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES marketplace_categories(id),
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    images JSONB NOT NULL DEFAULT '[]'::jsonb,
    price_cents INT NOT NULL CHECK (price_cents > 0),
    condition TEXT NOT NULL CHECK (condition IN ('new', 'used')),
    location TEXT NOT NULL,
    contact_phone TEXT,
    contact_email TEXT,
    status TEXT NOT NULL DEFAULT 'pending_approval' CHECK (
        status IN ('pending_approval', 'approved', 'rejected', 'sold', 'removed')
    ),
    rejection_reason TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_community_ads_browse ON community_advertisements(status, created_at DESC);
CREATE INDEX idx_community_ads_seller ON community_advertisements(seller_id, created_at DESC);
CREATE INDEX idx_community_ads_category ON community_advertisements(category_id);

CREATE TABLE shop_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID REFERENCES marketplace_categories(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    images JSONB NOT NULL DEFAULT '[]'::jsonb,
    price_cents INT NOT NULL CHECK (price_cents > 0),
    active BOOLEAN NOT NULL DEFAULT true,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_shop_products_browse ON shop_products(active, created_at DESC);