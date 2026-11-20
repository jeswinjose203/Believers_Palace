CREATE TABLE email_verification_codes (
    user_id UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    code_hash TEXT NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attempts_remaining INTEGER NOT NULL DEFAULT 5
);
