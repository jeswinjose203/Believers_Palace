ALTER TABLE chat_push_jobs DROP CONSTRAINT chat_push_jobs_kind_check;
ALTER TABLE chat_push_jobs ADD CONSTRAINT chat_push_jobs_kind_check
    CHECK (kind IN ('community', 'event', 'direct'));

ALTER TABLE direct_messages ADD COLUMN push_id UUID;
ALTER TABLE direct_messages ALTER COLUMN push_id SET DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX direct_messages_push_id ON direct_messages (push_id)
    WHERE push_id IS NOT NULL;

CREATE FUNCTION queue_direct_chat_push() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM direct_threads t JOIN chat_push_devices d
            ON d.user_id = CASE WHEN t.user_a = NEW.sender_id THEN t.user_b ELSE t.user_a END
        WHERE t.id = NEW.thread_id AND NEW.sender_id IN (t.user_a, t.user_b)
    ) THEN
        INSERT INTO chat_push_jobs (message_id, kind, room_id, sender_id)
        VALUES (NEW.push_id, 'direct', NEW.thread_id, NEW.sender_id);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER direct_chat_push AFTER INSERT ON direct_messages
    FOR EACH ROW EXECUTE FUNCTION queue_direct_chat_push();
