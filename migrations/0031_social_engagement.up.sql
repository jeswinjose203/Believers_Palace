BEGIN;

ALTER TABLE users DROP CONSTRAINT users_username_format;
ALTER TABLE users ADD CONSTRAINT users_username_format CHECK (username ~ '^[A-Za-z0-9_]{3,32}$');
CREATE UNIQUE INDEX users_username_ci_idx ON users (lower(username COLLATE "C") text_pattern_ops);
DROP INDEX users_username_idx;

CREATE TABLE social_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES social_posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 1000),
    client_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (post_id, author_id, client_id)
);
CREATE INDEX social_comments_page_idx ON social_comments(post_id, created_at DESC, id DESC);
CREATE INDEX social_comments_author_idx ON social_comments(author_id);
CREATE INDEX social_likes_people_idx ON social_likes(post_id, created_at DESC, user_id DESC);

-- Serialize the backfill with like writes so every reaction is counted once.
LOCK TABLE social_likes IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE social_engagement_counts (
    post_id UUID NOT NULL REFERENCES social_posts(id) ON DELETE CASCADE,
    bucket SMALLINT NOT NULL CHECK (bucket BETWEEN 0 AND 31),
    kind TEXT NOT NULL CHECK (kind IN ('like', 'comment')),
    total BIGINT NOT NULL CHECK (total >= 0),
    PRIMARY KEY (post_id, kind, bucket)
);
INSERT INTO social_engagement_counts(post_id, bucket, kind, total)
SELECT post_id, get_byte(uuid_send(user_id),15)%32, 'like', count(*)
FROM social_likes GROUP BY 1,2;

CREATE FUNCTION social_update_engagement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    actor UUID;
    shard SMALLINT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        actor := (to_jsonb(NEW)->>TG_ARGV[1])::uuid;
        shard := get_byte(uuid_send(actor),15)%32;
        INSERT INTO social_engagement_counts AS counts(post_id, bucket, kind, total)
        VALUES (NEW.post_id, shard, TG_ARGV[0], 1)
        ON CONFLICT (post_id, kind, bucket) DO UPDATE SET total=counts.total+1;
    ELSE
        actor := (to_jsonb(OLD)->>TG_ARGV[1])::uuid;
        shard := get_byte(uuid_send(actor),15)%32;
        UPDATE social_engagement_counts SET total=total-1
        WHERE post_id=OLD.post_id AND kind=TG_ARGV[0] AND bucket=shard;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER social_likes_counts AFTER INSERT OR DELETE ON social_likes
FOR EACH ROW EXECUTE FUNCTION social_update_engagement('like', 'user_id');
CREATE TRIGGER social_comments_counts AFTER INSERT OR DELETE ON social_comments
FOR EACH ROW EXECUTE FUNCTION social_update_engagement('comment', 'author_id');

COMMIT;
