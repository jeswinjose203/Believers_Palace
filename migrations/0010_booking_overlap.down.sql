-- 0010_booking_overlap.down.sql
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_no_overlap;
