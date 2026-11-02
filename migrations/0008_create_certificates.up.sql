-- 0008_create_certificates.up.sql
CREATE TABLE IF NOT EXISTS certificates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    uploaded_by_user_id UUID        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    type                TEXT        NOT NULL,
    certificate_number  TEXT        NOT NULL,
    full_name           TEXT        NOT NULL,
    issue_date          DATE,
    file_name           TEXT        NOT NULL,
    stored_path         TEXT        NOT NULL,
    mime_type           TEXT        NOT NULL,
    file_size           BIGINT      NOT NULL,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_certificate_number UNIQUE (user_id, certificate_number)
);

CREATE INDEX IF NOT EXISTS idx_certificates_user_id ON certificates (user_id);
CREATE INDEX IF NOT EXISTS idx_certificates_type ON certificates (type);
