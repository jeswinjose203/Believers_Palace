-- 0001_init.up.sql
-- Core extensions and the users table.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT        NOT NULL,
    email         TEXT        NOT NULL UNIQUE,
    password_hash TEXT        NOT NULL,
    phone         TEXT,
    unit          TEXT,
    profile_pic   TEXT,
    role          TEXT        NOT NULL DEFAULT 'user',
    church_id     UUID,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_church_id ON users (church_id);
CREATE INDEX IF NOT EXISTS idx_users_role ON users (role);
