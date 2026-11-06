-- 0015_event_messages_seq_commit_order.up.sql
-- Make `seq` a per-event, commit-ordered value so the chat's `after` cursor can
-- never skip a message. The sequence default assigned `seq` at INSERT time,
-- which under concurrent posts could become visible out of order (a lower seq
-- committing after a higher one), leaving a polling gap. We instead assign
-- seq = max(seq)+1 per event under a per-event advisory lock held until commit,
-- so visibility order always equals seq order.
--
-- Drop the global default/sequence; seq is now set only by the application
-- inside the locked Create path.
ALTER TABLE event_messages ALTER COLUMN seq DROP DEFAULT;
DROP SEQUENCE IF EXISTS event_messages_seq_seq;

-- Renumber existing rows per event (chronological) so each event starts at 1
-- and has no gaps. Keeps the (event_id, seq) unique index valid.
WITH renum AS (
    SELECT id,
           row_number() OVER (PARTITION BY event_id ORDER BY seq, created_at, id) AS rn
    FROM event_messages
)
UPDATE event_messages m
SET seq = r.rn
FROM renum r
WHERE m.id = r.id;
