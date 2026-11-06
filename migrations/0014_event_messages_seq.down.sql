-- 0014_event_messages_seq.down.sql
DROP INDEX IF EXISTS uq_event_messages_event_seq;
ALTER TABLE event_messages DROP COLUMN IF EXISTS seq;
DROP SEQUENCE IF EXISTS event_messages_seq_seq;
