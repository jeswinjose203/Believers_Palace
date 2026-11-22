DROP TABLE direct_messages, direct_threads, social_media, social_likes, social_posts;
DROP INDEX users_username_idx;
ALTER TABLE users DROP COLUMN username;
ALTER TABLE communities DROP COLUMN church_id;
