-- 0016_church_location_about.up.sql
-- Adds map coordinates and a longer "about" text to churches.
ALTER TABLE churches
    ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS about     TEXT;
