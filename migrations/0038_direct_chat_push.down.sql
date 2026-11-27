DROP TRIGGER direct_chat_push ON direct_messages;
DROP FUNCTION queue_direct_chat_push();
ALTER TABLE direct_messages DROP COLUMN push_id;

DELETE FROM chat_push_deliveries WHERE kind = 'direct';
DELETE FROM chat_push_jobs WHERE kind = 'direct';
ALTER TABLE chat_push_jobs DROP CONSTRAINT chat_push_jobs_kind_check;
ALTER TABLE chat_push_jobs ADD CONSTRAINT chat_push_jobs_kind_check
    CHECK (kind IN ('community', 'event'));
