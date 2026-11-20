package user

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// ErrTokenInvalid is returned when a refresh or reset token is unknown,
// expired, already used, or revoked.
var ErrTokenInvalid = errors.New("token is invalid or expired")

// StoreRefreshToken persists the hash of a refresh token for a user.
func (r *Repository) StoreRefreshToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	const q = `
		INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		VALUES ($1, $2, $3)`
	if _, err := r.pool.Exec(ctx, q, userID, tokenHash, expiresAt); err != nil {
		return fmt.Errorf("store refresh token: %w", err)
	}
	return nil
}

// refreshToken is the subset of a stored refresh-token row used for validation.
type refreshToken struct {
	ID     string
	UserID string
}

// ConsumeRefreshToken validates a refresh token by its hash and atomically
// revokes it (rotation). It returns the owning user ID on success. A token that
// is unknown, expired, or already revoked yields ErrTokenInvalid.
func (r *Repository) ConsumeRefreshToken(ctx context.Context, tokenHash string) (userID string, err error) {
	const q = `
		UPDATE refresh_tokens
		SET revoked_at = now()
		WHERE token_hash = $1
		  AND revoked_at IS NULL
		  AND expires_at > now()
		RETURNING user_id`
	err = r.pool.QueryRow(ctx, q, tokenHash).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrTokenInvalid
	}
	if err != nil {
		return "", fmt.Errorf("consume refresh token: %w", err)
	}
	return userID, nil
}

// RevokeRefreshToken revokes a single refresh token by its hash. It is
// idempotent: revoking an unknown or already-revoked token is not an error.
func (r *Repository) RevokeRefreshToken(ctx context.Context, tokenHash string) error {
	const q = `
		UPDATE refresh_tokens
		SET revoked_at = now()
		WHERE token_hash = $1 AND revoked_at IS NULL`
	if _, err := r.pool.Exec(ctx, q, tokenHash); err != nil {
		return fmt.Errorf("revoke refresh token: %w", err)
	}
	return nil
}

// RevokeAllRefreshTokens revokes every active refresh token for a user
// (log out everywhere).
func (r *Repository) RevokeAllRefreshTokens(ctx context.Context, userID string) error {
	const q = `
		UPDATE refresh_tokens
		SET revoked_at = now()
		WHERE user_id = $1 AND revoked_at IS NULL`
	if _, err := r.pool.Exec(ctx, q, userID); err != nil {
		return fmt.Errorf("revoke all refresh tokens: %w", err)
	}
	return nil
}

// StorePasswordResetToken persists the hash of a single-use reset token.
func (r *Repository) StorePasswordResetToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	const q = `
		INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
		VALUES ($1, $2, $3)`
	if _, err := r.pool.Exec(ctx, q, userID, tokenHash, expiresAt); err != nil {
		return fmt.Errorf("store password reset token: %w", err)
	}
	return nil
}

// ConsumePasswordResetToken validates a reset token by its hash and atomically
// marks it used. It returns the owning user ID on success. A token that is
// unknown, expired, or already used yields ErrTokenInvalid.
func (r *Repository) ConsumePasswordResetToken(ctx context.Context, tokenHash string) (userID string, err error) {
	const q = `
		UPDATE password_reset_tokens
		SET used_at = now()
		WHERE token_hash = $1
		  AND used_at IS NULL
		  AND expires_at > now()
		RETURNING user_id`
	err = r.pool.QueryRow(ctx, q, tokenHash).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrTokenInvalid
	}
	if err != nil {
		return "", fmt.Errorf("consume password reset token: %w", err)
	}
	return userID, nil
}

// UpdatePassword sets a user's password hash.
func (r *Repository) UpdatePassword(ctx context.Context, userID, passwordHash string) error {
	const q = `UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2`
	tag, err := r.pool.Exec(ctx, q, passwordHash, userID)
	if err != nil {
		return fmt.Errorf("update password: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// StoreEmailVerificationCode replaces the previous code after a one-minute cooldown.
func (r *Repository) StoreEmailVerificationCode(ctx context.Context, userID, hash string) (bool, error) {
	const q = `
		INSERT INTO email_verification_codes (user_id, code_hash)
		VALUES ($1, $2)
		ON CONFLICT (user_id) DO UPDATE
		SET code_hash = EXCLUDED.code_hash, issued_at = now(), attempts_remaining = 5
		WHERE email_verification_codes.issued_at <= now() - interval '1 minute'`
	tag, err := r.pool.Exec(ctx, q, userID, hash)
	if err != nil {
		return false, fmt.Errorf("store email verification code: %w", err)
	}
	return tag.RowsAffected() == 1, nil
}

func (r *Repository) DeleteEmailVerificationCode(ctx context.Context, userID, hash string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM email_verification_codes WHERE user_id = $1 AND code_hash = $2`, userID, hash)
	return err
}

// VerifyEmailCode records each attempt and verifies the account in one statement.
func (r *Repository) VerifyEmailCode(ctx context.Context, email, hash string) error {
	const q = `
		WITH attempt AS (
			UPDATE email_verification_codes AS c
			SET attempts_remaining = CASE WHEN c.code_hash = $2 THEN 0 ELSE c.attempts_remaining - 1 END
			FROM users AS u
			WHERE u.id = c.user_id AND u.email = $1
			  AND c.attempts_remaining > 0 AND c.issued_at > now() - interval '10 minutes'
			RETURNING c.user_id, c.code_hash
		)
		UPDATE users AS u SET email_verified = true, updated_at = now()
		FROM attempt
		WHERE u.id = attempt.user_id AND u.email = $1 AND attempt.code_hash = $2`
	tag, err := r.pool.Exec(ctx, q, email, hash)
	if err != nil {
		return fmt.Errorf("verify email code: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrTokenInvalid
	}
	return nil
}

// ConsumeEmailVerificationToken validates a verification token by its hash and
// atomically marks it used, returning the owning user ID. Unknown, expired, or
// already-used tokens yield ErrTokenInvalid.
func (r *Repository) ConsumeEmailVerificationToken(ctx context.Context, tokenHash string) (userID string, err error) {
	const q = `
		UPDATE email_verification_tokens
		SET used_at = now()
		WHERE token_hash = $1
		  AND used_at IS NULL
		  AND expires_at > now()
		RETURNING user_id`
	err = r.pool.QueryRow(ctx, q, tokenHash).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrTokenInvalid
	}
	if err != nil {
		return "", fmt.Errorf("consume email verification token: %w", err)
	}
	return userID, nil
}

// MarkEmailVerified sets a user's email_verified flag to true.
func (r *Repository) MarkEmailVerified(ctx context.Context, userID string) error {
	const q = `UPDATE users SET email_verified = true, updated_at = now() WHERE id = $1`
	tag, err := r.pool.Exec(ctx, q, userID)
	if err != nil {
		return fmt.Errorf("mark email verified: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
