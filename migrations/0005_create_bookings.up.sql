-- 0005_create_bookings.up.sql
CREATE TABLE IF NOT EXISTS bookings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id           UUID        NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    hall_id             UUID        NOT NULL REFERENCES halls (id) ON DELETE CASCADE,
    user_id             UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    start_date          TIMESTAMPTZ NOT NULL,
    end_date            TIMESTAMPTZ NOT NULL,
    purpose             TEXT,
    notes               TEXT,
    status              TEXT        NOT NULL DEFAULT 'pending',
    admin_notes         TEXT,
    cancellation_reason TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bookings_church_id ON bookings (church_id);
CREATE INDEX IF NOT EXISTS idx_bookings_hall_id ON bookings (hall_id);
CREATE INDEX IF NOT EXISTS idx_bookings_user_id ON bookings (user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings (status);
