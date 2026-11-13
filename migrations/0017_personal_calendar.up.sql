-- 0017_personal_calendar.up.sql
CREATE TABLE IF NOT EXISTS user_calendar_preferences (
    user_id           UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    theme             TEXT        NOT NULL DEFAULT 'system',
    date_format       TEXT        NOT NULL DEFAULT 'dmy',
    week_starts_on    TEXT        NOT NULL DEFAULT 'monday',
    holiday_country   TEXT        NOT NULL DEFAULT 'IN',
    category_colors   JSONB       NOT NULL DEFAULT '{}',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_calendar_prefs_theme CHECK (theme IN ('system', 'light', 'dark')),
    CONSTRAINT chk_calendar_prefs_date_format CHECK (date_format IN ('mdy', 'dmy', 'ymd')),
    CONSTRAINT chk_calendar_prefs_week CHECK (week_starts_on IN ('sunday', 'monday'))
);
 
CREATE TABLE IF NOT EXISTS calendar_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title               TEXT        NOT NULL,
    description         TEXT,
    category            TEXT        NOT NULL DEFAULT 'personal',
    color               TEXT,
    start_at            TIMESTAMPTZ NOT NULL,
    end_at              TIMESTAMPTZ NOT NULL,
    all_day             BOOLEAN     NOT NULL DEFAULT false,
    recurrence          TEXT        NOT NULL DEFAULT 'none',
    recurrence_interval INT         NOT NULL DEFAULT 1,
    recurrence_until    TIMESTAMPTZ,
    reminder_minutes    INT[]       NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_calendar_events_category CHECK (
        category IN ('personal', 'work', 'family', 'meetings')
    ),
    CONSTRAINT chk_calendar_events_recurrence CHECK (
        recurrence IN ('none', 'daily', 'weekly', 'monthly')
    ),
    CONSTRAINT chk_calendar_events_range CHECK (end_at >= start_at)
);
 
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_start ON calendar_events (user_id, start_at);
 
CREATE TABLE IF NOT EXISTS calendar_tasks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title       TEXT        NOT NULL,
    description TEXT,
    due_date    DATE        NOT NULL,
    completed   BOOLEAN     NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
 
CREATE INDEX IF NOT EXISTS idx_calendar_tasks_user_due ON calendar_tasks (user_id, due_date);
 
CREATE TABLE IF NOT EXISTS calendar_goals (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title          TEXT        NOT NULL,
    description    TEXT,
    target_days    INT         NOT NULL,
    tracking_mode  TEXT        NOT NULL DEFAULT 'total',
    start_date     DATE,
    end_date       DATE,
    status         TEXT        NOT NULL DEFAULT 'active',
    completed_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_calendar_goals_target CHECK (target_days > 0),
    CONSTRAINT chk_calendar_goals_mode CHECK (tracking_mode IN ('total', 'streak')),
    CONSTRAINT chk_calendar_goals_status CHECK (status IN ('active', 'completed', 'archived'))
);
 
CREATE INDEX IF NOT EXISTS idx_calendar_goals_user ON calendar_goals (user_id, status);
 
CREATE TABLE IF NOT EXISTS calendar_goal_checkins (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    goal_id      UUID        NOT NULL REFERENCES calendar_goals (id) ON DELETE CASCADE,
    checkin_date DATE        NOT NULL,
    note         TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (goal_id, checkin_date)
);
 
CREATE TABLE IF NOT EXISTS achievement_definitions (
    code        TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    description TEXT NOT NULL,
    icon        TEXT NOT NULL DEFAULT 'emoji_events'
);
 
INSERT INTO achievement_definitions (code, title, description, icon) VALUES
    ('goal_complete', 'Goal completed', 'You finished a personal goal', 'emoji_events'),
    ('first_goal', 'First steps', 'Completed your first goal', 'military_tech'),
    ('streak_7', 'Week warrior', 'Completed a 7-day streak goal', 'local_fire_department')
ON CONFLICT (code) DO NOTHING;
 
CREATE TABLE IF NOT EXISTS user_achievements (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    achievement_code TEXT        NOT NULL REFERENCES achievement_definitions (code),
    goal_id          UUID        REFERENCES calendar_goals (id) ON DELETE SET NULL,
    unlocked_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
 
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_achievements_goal_badge
    ON user_achievements (user_id, achievement_code, goal_id)
    NULLS NOT DISTINCT;
 
CREATE INDEX IF NOT EXISTS idx_user_achievements_user ON user_achievements (user_id);
 