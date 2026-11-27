CREATE TABLE chat_push_devices (
    token TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX chat_push_devices_user ON chat_push_devices (user_id);

CREATE TABLE chat_push_jobs (
    message_id UUID PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN ('community', 'event')),
    room_id UUID NOT NULL,
    sender_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX chat_push_jobs_created ON chat_push_jobs (created_at, message_id);

CREATE TABLE chat_push_deliveries (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message_id UUID NOT NULL,
    kind TEXT NOT NULL,
    room_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL REFERENCES chat_push_devices(token) ON DELETE CASCADE,
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX chat_push_deliveries_due ON chat_push_deliveries (next_attempt, id);
CREATE INDEX chat_push_deliveries_token ON chat_push_deliveries (token);

CREATE FUNCTION queue_chat_push() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM chat_push_devices) THEN
        INSERT INTO chat_push_jobs (message_id, kind, room_id, sender_id)
        VALUES (NEW.id, TG_ARGV[0], (to_jsonb(NEW) ->> TG_ARGV[1])::uuid, NEW.user_id);
    END IF;
    RETURN NULL;
END;
$$;
CREATE TRIGGER event_chat_push AFTER INSERT ON event_messages
    FOR EACH ROW EXECUTE FUNCTION queue_chat_push('event', 'event_id');
CREATE TRIGGER community_chat_push AFTER INSERT ON community_messages
    FOR EACH ROW EXECUTE FUNCTION queue_chat_push('community', 'community_id');
