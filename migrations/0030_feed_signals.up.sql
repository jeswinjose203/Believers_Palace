ALTER TABLE social_likes ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE INDEX social_likes_reader_recency ON social_likes(user_id,created_at DESC,post_id);
CREATE INDEX social_posts_author_recency ON social_posts(author_id,created_at DESC,id DESC);
