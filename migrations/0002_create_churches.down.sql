-- 0002_create_churches.down.sql
ALTER TABLE users DROP CONSTRAINT IF EXISTS fk_users_church;
DROP TABLE IF EXISTS churches;
