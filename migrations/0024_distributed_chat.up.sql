CREATE TABLE chat_live_tickets (
    token_hash TEXT PRIMARY KEY,
    user_id UUID NOT NULL,
    role TEXT NOT NULL,
    church_id TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '30 seconds'
);
CREATE INDEX chat_live_tickets_expires ON chat_live_tickets (expires_at);

CREATE TABLE chat_notification_preferences (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('community', 'event')),
    room_id UUID NOT NULL,
    muted BOOLEAN NOT NULL,
    PRIMARY KEY (user_id, kind, room_id)
);
CREATE INDEX chat_notification_event_followers
    ON chat_notification_preferences (room_id, user_id)
    WHERE kind = 'event' AND muted = false;

CREATE FUNCTION signal_chat_change() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    row_data jsonb;
    room uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN row_data := to_jsonb(OLD);
    ELSE row_data := to_jsonb(NEW);
    END IF;
    room := (row_data ->> TG_ARGV[1])::uuid;
    PERFORM pg_notify('chat_changes', jsonb_build_object(
        'kind', TG_ARGV[0], 'id', room, 'deleted',
        CASE WHEN TG_OP = 'DELETE' THEN row_data ->> 'id' ELSE '' END
    )::text);
    RETURN NULL;
END;
$$;
CREATE TRIGGER event_chat_change AFTER INSERT OR DELETE ON event_messages
    FOR EACH ROW EXECUTE FUNCTION signal_chat_change('event', 'event_id');
CREATE TRIGGER community_chat_change AFTER INSERT OR DELETE ON community_messages
    FOR EACH ROW EXECUTE FUNCTION signal_chat_change('community', 'community_id');
