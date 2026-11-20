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

-- Sample church for local catechism testing (fixed ID).
INSERT INTO churches (id, name, address)
VALUES (
    '00000000-0000-0000-0000-000000000010',
    'St. Mary Parish (Dev)',
    '1 Faith Way'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO catechism_classes (
    id, church_id, name, description, level, min_age, max_age,
    teacher_name, schedule, location, start_date, end_date, capacity, status
)
VALUES (
    '00000000-0000-0000-0000-000000000020',
    '00000000-0000-0000-0000-000000000010',
    'First Communion 2026',
    'Preparation classes for first Holy Communion.',
    'first_communion',
    7,
    10,
    'Fr. Sample',
    '[{"day":"Saturday","time":"10:00"}]'::jsonb,
    'Parish hall',
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '180 days',
    25,
    'open'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO catechism_enrollments (
    id, class_id, guardian_id, student_name, date_of_birth, notes, status
)
VALUES (
    '00000000-0000-0000-0000-000000000021',
    '00000000-0000-0000-0000-000000000020',
    '00000000-0000-0000-0000-000000000001',
    'Sample Child',
    '2016-05-15',
    'Dev seed enrollment',
    'pending'
-- Marketplace sample categories (idempotent).
INSERT INTO marketplace_categories (id, name, scope, sort_order, active)
VALUES
    ('00000000-0000-0000-0001-000000000001', 'General', 'community', 0, true),
    ('00000000-0000-0000-0001-000000000002', 'Books & Media', 'community', 1, true),
    ('00000000-0000-0000-0001-000000000010', 'Church Store', 'shop', 0, true)
ON CONFLICT (name, scope) DO NOTHING;

INSERT INTO shop_products (id, category_id, title, description, images, price_cents, active, created_by)
VALUES (
    '00000000-0000-0000-0002-000000000001',
    '00000000-0000-0000-0001-000000000010',
    'Sample Worship Hymnal',
    'Development seed product for the official shop catalog.',
    '[]'::jsonb,
    1999,
    true,
    '00000000-0000-0000-0000-000000000001'
)
ON CONFLICT (id) DO NOTHING;
