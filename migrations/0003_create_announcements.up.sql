-- 0003_create_announcements.up.sql
CREATE TABLE IF NOT EXISTS announcements (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id    UUID        NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    title        TEXT        NOT NULL,
    content      TEXT        NOT NULL,
    image        TEXT,
    published_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_announcements_church_id ON announcements (church_id);
CREATE INDEX IF NOT EXISTS idx_announcements_published_at ON announcements (published_at);
