ALTER TABLE community_messages DROP COLUMN client_id;
ALTER TABLE event_messages DROP COLUMN client_id;
ALTER TABLE communities DROP COLUMN chat_seq;
ALTER TABLE events DROP COLUMN chat_seq;
