package user

import (
	"errors"
	"net/http"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
	"github.com/jackc/pgx/v5"
)

// RequireVerifiedEmail checks the current account so verification takes effect
// on existing sessions immediately.
func (r *Repository) RequireVerifiedEmail(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		id := auth.MustFromContext(req.Context())
		var verified bool
		err := r.pool.QueryRow(req.Context(), "SELECT email_verified FROM users WHERE id=$1", id.UserID).Scan(&verified)
		switch {
		case err != nil && !errors.Is(err, pgx.ErrNoRows):
			httpx.ErrorCode(w, http.StatusInternalServerError, "could not check email verification", "internal_error")
		case !verified:
			httpx.ErrorCode(w, http.StatusForbidden, "Verify your email to access chat.", "email_verification_required")
		default:
			next.ServeHTTP(w, req)
		}
	})
}
