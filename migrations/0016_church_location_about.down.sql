-- 0016_church_location_about.down.sql
ALTER TABLE churches
    DROP COLUMN IF EXISTS latitude,
    DROP COLUMN IF EXISTS longitude,
    DROP COLUMN IF EXISTS about;
