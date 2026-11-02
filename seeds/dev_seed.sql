-- dev_seed.sql
-- DEVELOPMENT-ONLY seed data. Do NOT run against production.
--
-- Inserts the fixed debug user referenced by auth.DebugUserID, which is the
-- default identity injected when SKIP_JWT_VALIDATION=true. Having a real row
-- lets foreign-key-bound operations (bookings, cemetery service requests,
-- certificates, event registrations) succeed while testing without a login.
--
-- The password hash is bcrypt for "password" so you can also log in as this
-- user normally if you wish. Safe to run repeatedly (idempotent).

INSERT INTO users (id, name, email, password_hash, role, email_verified)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Debug User',
    'debug@example.com',
    '$2a$10$QlgIj8yuSMtllEnXK3NHyetMjBWfqJgx8TXU1Z8YqH9IR07MrVyfC',
    'super_admin',
    true
)
ON CONFLICT (id) DO NOTHING;
