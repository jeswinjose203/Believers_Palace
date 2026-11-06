-- 0013_church_description_images.down.sql
ALTER TABLE churches
    DROP COLUMN IF EXISTS images,
    DROP COLUMN IF EXISTS description;
