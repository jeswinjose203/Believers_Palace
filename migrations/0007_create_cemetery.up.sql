-- 0007_create_cemetery.up.sql
CREATE TABLE IF NOT EXISTS cemetery_plots (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id            UUID        NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    plot_number          TEXT        NOT NULL,
    section              TEXT,
    location_description TEXT,
    status               TEXT        NOT NULL DEFAULT 'available',
    notes                TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_cemetery_plot_number UNIQUE (church_id, plot_number)
);

CREATE INDEX IF NOT EXISTS idx_cemetery_plots_church_id ON cemetery_plots (church_id);
CREATE INDEX IF NOT EXISTS idx_cemetery_plots_status ON cemetery_plots (status);

CREATE TABLE IF NOT EXISTS cemetery_service_requests (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID        NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    user_id        UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    type           TEXT        NOT NULL,
    status         TEXT        NOT NULL DEFAULT 'pending',
    full_name      TEXT        NOT NULL,
    contact_phone  TEXT,
    contact_email  TEXT,
    deceased_name  TEXT,
    requested_date TIMESTAMPTZ,
    plot_id        UUID        REFERENCES cemetery_plots (id) ON DELETE SET NULL,
    description    TEXT,
    notes          TEXT,
    admin_notes    TEXT,
    scheduled_date TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cemetery_requests_church_id ON cemetery_service_requests (church_id);
CREATE INDEX IF NOT EXISTS idx_cemetery_requests_user_id ON cemetery_service_requests (user_id);
CREATE INDEX IF NOT EXISTS idx_cemetery_requests_status ON cemetery_service_requests (status);
