ALTER TABLE communities ADD COLUMN church_id UUID REFERENCES churches(id) ON DELETE SET NULL;
UPDATE communities c SET church_id=u.church_id FROM users u WHERE u.id=c.creator_id;
CREATE INDEX communities_church_page_idx ON communities(church_id, created_at DESC, id DESC);

ALTER TABLE users ADD COLUMN username TEXT NOT NULL DEFAULT ('member_' || encode(gen_random_bytes(12), 'hex'));
ALTER TABLE users ADD CONSTRAINT users_username_format CHECK (username ~ '^[a-z0-9_]{3,32}$');
CREATE UNIQUE INDEX users_username_idx ON users(username text_pattern_ops);

CREATE TABLE social_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    church_id UUID REFERENCES churches(id) ON DELETE SET NULL,
    body TEXT NOT NULL CHECK (length(body) <= 4000),
    media_key TEXT,
    client_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(author_id,client_id),
    CHECK (body <> '' OR media_key IS NOT NULL)
);
CREATE INDEX social_posts_page_idx ON social_posts(created_at DESC,id DESC);
CREATE TABLE social_likes (
    post_id UUID REFERENCES social_posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY(post_id,user_id)
);
CREATE TABLE social_media (
    key TEXT PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE direct_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_seq BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    hidden_a BIGINT NOT NULL DEFAULT 0,
    hidden_b BIGINT NOT NULL DEFAULT 0,
    UNIQUE(user_a,user_b),
    CHECK (user_a < user_b)
);
CREATE INDEX direct_threads_a_idx ON direct_threads(user_a,updated_at DESC,id DESC) WHERE last_seq > hidden_a;
CREATE INDEX direct_threads_b_idx ON direct_threads(user_b,updated_at DESC,id DESC) WHERE last_seq > hidden_b;

CREATE TABLE direct_messages (
    thread_id UUID NOT NULL REFERENCES direct_threads(id) ON DELETE CASCADE,
    seq BIGINT NOT NULL,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 4000),
    client_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(thread_id,seq),
    UNIQUE(thread_id,sender_id,client_id)
);
