DROP TRIGGER community_chat_push ON community_messages;
DROP TRIGGER event_chat_push ON event_messages;
DROP FUNCTION queue_chat_push();
DROP TABLE chat_push_deliveries;
DROP TABLE chat_push_jobs;
DROP TABLE chat_push_devices;
