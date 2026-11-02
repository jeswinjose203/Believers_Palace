-- 0002_create_churches.up.sql
CREATE TABLE IF NOT EXISTS churches (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                  TEXT        NOT NULL,
    address               TEXT,
    phone                 TEXT,
    email                 TEXT,
    logo                  TEXT,
    priest                JSONB,
    associate_priest      JSONB,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_churches_name ON churches (name);

-- Now that churches exist, add the FK from users.church_id.
ALTER TABLE users
    ADD CONSTRAINT fk_users_church
    FOREIGN KEY (church_id) REFERENCES churches (id) ON DELETE SET NULL;
