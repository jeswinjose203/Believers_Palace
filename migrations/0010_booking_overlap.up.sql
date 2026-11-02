-- 0010_booking_overlap.up.sql
-- Prevent double-booking a hall for overlapping time ranges at the database
-- level (race-proof). Only "pending" and "approved" bookings block a slot;
-- rejected/cancelled/completed bookings do not.

CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_no_overlap
    EXCLUDE USING gist (
        hall_id WITH =,
        tstzrange(start_date, end_date) WITH &&
    )
    WHERE (status IN ('pending', 'approved'));
