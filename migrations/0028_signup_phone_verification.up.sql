ALTER TABLE users ADD COLUMN phone_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD CONSTRAINT verified_phone_format
    CHECK (NOT phone_verified OR (phone IS NOT NULL AND phone ~ '^\+[1-9][0-9]{7,14}$'));
CREATE UNIQUE INDEX users_verified_phone_unique ON users (phone) WHERE phone_verified;

CREATE TABLE signup_phone_codes (
    phone_key TEXT PRIMARY KEY,
    challenge TEXT NOT NULL,
    code_hash TEXT,
    sent_at TIMESTAMPTZ NOT NULL,
    window_start TIMESTAMPTZ NOT NULL,
    send_count INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX signup_phone_codes_window_idx ON signup_phone_codes (window_start);
