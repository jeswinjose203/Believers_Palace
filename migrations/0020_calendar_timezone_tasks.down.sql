ALTER TABLE calendar_tasks
    ALTER COLUMN due_date TYPE DATE
    USING ((due_date AT TIME ZONE 'Asia/Kolkata')::date);

ALTER TABLE user_calendar_preferences
    DROP COLUMN IF EXISTS timezone;