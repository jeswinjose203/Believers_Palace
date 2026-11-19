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
