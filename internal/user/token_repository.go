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

// StoreEmailVerificationToken persists the hash of a single-use verification token.
func (r *Repository) StoreEmailVerificationToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	const q = `
		INSERT INTO email_verification_tokens (user_id, token_hash, expires_at)
		VALUES ($1, $2, $3)`
	if _, err := r.pool.Exec(ctx, q, userID, tokenHash, expiresAt); err != nil {
		return fmt.Errorf("store email verification token: %w", err)
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
