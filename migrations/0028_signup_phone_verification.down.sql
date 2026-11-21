DROP TABLE signup_phone_codes;
DROP INDEX users_verified_phone_unique;
ALTER TABLE users DROP CONSTRAINT verified_phone_format, DROP COLUMN phone_verified;
