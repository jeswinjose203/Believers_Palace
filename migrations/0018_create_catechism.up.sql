-- 0018_create_catechism.up.sql

CREATE TABLE IF NOT EXISTS catechism_classes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID        NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    name            TEXT        NOT NULL,
    description     TEXT,
    level           TEXT        NOT NULL,
    min_age         INTEGER,
    max_age         INTEGER,
    teacher_user_id UUID        REFERENCES users (id) ON DELETE SET NULL,
    teacher_name    TEXT,
    schedule        JSONB       NOT NULL DEFAULT '[]'::jsonb,
    location        TEXT,
    start_date      DATE        NOT NULL,
    end_date        DATE        NOT NULL,
    capacity        INTEGER     NOT NULL,
    status          TEXT        NOT NULL DEFAULT 'draft',
    image           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT catechism_classes_level_check CHECK (
        level IN ('first_communion', 'confirmation', 'baptism_prep', 'sunday_school', 'adult', 'other')
    ),
    CONSTRAINT catechism_classes_status_check CHECK (
        status IN ('draft', 'open', 'closed', 'completed')
    ),
    CONSTRAINT catechism_classes_capacity_check CHECK (capacity >= 1),
    CONSTRAINT catechism_classes_dates_check CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_catechism_classes_church_id ON catechism_classes (church_id);
CREATE INDEX IF NOT EXISTS idx_catechism_classes_status ON catechism_classes (status);
CREATE INDEX IF NOT EXISTS idx_catechism_classes_level ON catechism_classes (level);

CREATE TABLE IF NOT EXISTS catechism_enrollments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id        UUID        NOT NULL REFERENCES catechism_classes (id) ON DELETE CASCADE,
    guardian_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    student_name    TEXT        NOT NULL,
    date_of_birth   DATE        NOT NULL,
    notes           TEXT,
    status          TEXT        NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT catechism_enrollments_status_check CHECK (
        status IN ('pending', 'approved', 'rejected', 'withdrawn', 'completed')
    )
);

CREATE INDEX IF NOT EXISTS idx_catechism_enrollments_class_id ON catechism_enrollments (class_id);
CREATE INDEX IF NOT EXISTS idx_catechism_enrollments_guardian_id ON catechism_enrollments (guardian_id);
CREATE INDEX IF NOT EXISTS idx_catechism_enrollments_status ON catechism_enrollments (status);

-- One active enrollment per student identity per class.
CREATE UNIQUE INDEX IF NOT EXISTS uq_catechism_enrollment_active_student
    ON catechism_enrollments (class_id, student_name, date_of_birth)
    WHERE status IN ('pending', 'approved');

CREATE TABLE IF NOT EXISTS catechism_sessions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id    UUID        NOT NULL REFERENCES catechism_classes (id) ON DELETE CASCADE,
    title       TEXT        NOT NULL,
    topic       TEXT,
    session_date DATE       NOT NULL,
    start_time  TIME        NOT NULL,
    end_time    TIME        NOT NULL,
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT catechism_sessions_times_check CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_catechism_sessions_class_id ON catechism_sessions (class_id);