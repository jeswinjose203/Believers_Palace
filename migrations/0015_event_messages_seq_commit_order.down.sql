-- 0015_event_messages_seq_commit_order.down.sql
-- Restore a global sequence default for seq (best-effort; values remain whatever
-- the application assigned).
CREATE SEQUENCE IF NOT EXISTS event_messages_seq_seq;
SELECT setval('event_messages_seq_seq',
              COALESCE((SELECT max(seq) FROM event_messages), 0) + 1, false);
ALTER TABLE event_messages ALTER COLUMN seq SET DEFAULT nextval('event_messages_seq_seq');
ALTER SEQUENCE event_messages_seq_seq OWNED BY event_messages.seq;
