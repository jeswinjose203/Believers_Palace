-- 0014_event_messages_seq.up.sql
-- Monotonic per-table sequence used as a stable cursor for chat paging and
-- polling. Unlike timestamps it has no precision/tie issues, and unlike
-- message IDs it keeps working when the cursor message has been deleted.
CREATE SEQUENCE IF NOT EXISTS event_messages_seq_seq;

ALTER TABLE event_messages ADD COLUMN IF NOT EXISTS seq BIGINT;

-- Backfill existing rows in chronological order.
WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM event_messages
)
UPDATE event_messages m
SET seq = o.rn
FROM ordered o
WHERE m.id = o.id AND m.seq IS NULL;

SELECT setval('event_messages_seq_seq',
              COALESCE((SELECT max(seq) FROM event_messages), 0) + 1, false);

ALTER TABLE event_messages
    ALTER COLUMN seq SET DEFAULT nextval('event_messages_seq_seq'),
    ALTER COLUMN seq SET NOT NULL;

ALTER SEQUENCE event_messages_seq_seq OWNED BY event_messages.seq;

CREATE UNIQUE INDEX IF NOT EXISTS uq_event_messages_event_seq
    ON event_messages (event_id, seq);
