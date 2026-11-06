-- 0013_church_description_images.up.sql
ALTER TABLE churches
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS images      JSONB NOT NULL DEFAULT '[]'::jsonb;
