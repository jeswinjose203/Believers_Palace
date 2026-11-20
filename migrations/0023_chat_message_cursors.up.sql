ALTER TABLE events ADD COLUMN chat_seq BIGINT NOT NULL DEFAULT 0;
ALTER TABLE communities ADD COLUMN chat_seq BIGINT NOT NULL DEFAULT 0;

UPDATE events AS e SET chat_seq = m.seq
FROM (SELECT event_id, max(seq) AS seq FROM event_messages GROUP BY event_id) AS m
WHERE e.id = m.event_id;

UPDATE communities AS c SET chat_seq = m.seq
FROM (SELECT community_id, max(seq) AS seq FROM community_messages GROUP BY community_id) AS m
WHERE c.id = m.community_id;

ALTER TABLE event_messages ADD COLUMN client_id TEXT,
    ADD UNIQUE (event_id, user_id, client_id);
ALTER TABLE community_messages ADD COLUMN client_id TEXT,
    ADD UNIQUE (community_id, user_id, client_id);
