package user

import (
	"errors"
	"net/http"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// RequireVerifiedEmail checks the current account so verification takes effect
// on existing sessions immediately.
func (r *Repository) RequireVerifiedEmail(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		id := auth.MustFromContext(req.Context())
		account, err := r.GetByID(req.Context(), id.UserID)
		switch {
		case err != nil && !errors.Is(err, ErrNotFound):
			httpx.ErrorCode(w, http.StatusInternalServerError, "could not check email verification", "internal_error")
		case account == nil || !account.EmailVerified:
			httpx.ErrorCode(w, http.StatusForbidden, "Verify your email to access chat.", "email_verification_required")
		default:
			next.ServeHTTP(w, req)
		}
	})
}
