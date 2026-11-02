-- 0006_create_events.up.sql
CREATE TABLE IF NOT EXISTS events (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id             UUID        NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    title                 TEXT        NOT NULL,
    description           TEXT,
    location              TEXT,
    start_date            TIMESTAMPTZ NOT NULL,
    end_date              TIMESTAMPTZ,
    image                 TEXT,
    capacity              INTEGER,
    registration_required BOOLEAN     NOT NULL DEFAULT false,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_events_church_id ON events (church_id);
CREATE INDEX IF NOT EXISTS idx_events_start_date ON events (start_date);

CREATE TABLE IF NOT EXISTS event_registrations (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id       UUID        NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    user_id        UUID        REFERENCES users (id) ON DELETE SET NULL,
    attendee_name  TEXT,
    attendee_email TEXT,
    attendee_phone TEXT,
    notes          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_event_registrations_event_id ON event_registrations (event_id);

-- A signed-in user may register for a given event at most once.
CREATE UNIQUE INDEX IF NOT EXISTS uq_event_registration_user
    ON event_registrations (event_id, user_id)
    WHERE user_id IS NOT NULL;
