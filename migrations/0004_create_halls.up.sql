-- 0004_create_halls.up.sql
CREATE TABLE IF NOT EXISTS halls (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID        NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    name        TEXT        NOT NULL,
    description TEXT,
    capacity    INTEGER,
    location    TEXT,
    images      JSONB       NOT NULL DEFAULT '[]'::jsonb,
    amenities   JSONB       NOT NULL DEFAULT '[]'::jsonb,
    price       NUMERIC(12,2),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_halls_church_id ON halls (church_id);
