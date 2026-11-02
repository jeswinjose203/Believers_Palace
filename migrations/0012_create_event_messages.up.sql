-- 0012_create_event_messages.up.sql
-- Per-event chat: any authenticated user may post messages to an event's chat.
CREATE TABLE IF NOT EXISTS event_messages (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID        NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    user_id     UUID        REFERENCES users (id) ON DELETE SET NULL,
    author_name TEXT        NOT NULL,
    author_pic  TEXT,
    content     TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_event_messages_event_id_created_at
    ON event_messages (event_id, created_at);
