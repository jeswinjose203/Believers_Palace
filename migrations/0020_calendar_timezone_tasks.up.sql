ALTER TABLE user_calendar_preferences
    ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata';

ALTER TABLE calendar_tasks
    ALTER COLUMN due_date TYPE TIMESTAMPTZ
    USING ((due_date::timestamp AT TIME ZONE 'Asia/Kolkata'));