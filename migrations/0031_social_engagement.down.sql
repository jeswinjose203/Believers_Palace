DROP TRIGGER social_likes_counts ON social_likes;
DROP TRIGGER social_comments_counts ON social_comments;
DROP FUNCTION social_update_engagement();
DROP TABLE social_engagement_counts;
DROP TABLE social_comments;
DROP INDEX social_likes_people_idx;

ALTER TABLE users DROP CONSTRAINT users_username_format;
UPDATE users SET username=lower(username COLLATE "C") WHERE username<>lower(username COLLATE "C");
ALTER TABLE users ADD CONSTRAINT users_username_format CHECK (username ~ '^[a-z0-9_]{3,32}$');
CREATE UNIQUE INDEX users_username_idx ON users(username text_pattern_ops);
DROP INDEX users_username_ci_idx;
