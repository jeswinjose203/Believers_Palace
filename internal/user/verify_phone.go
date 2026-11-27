package user

import (
	"context"
	"errors"
	"net/http"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

func (h *Handler) verifyPhone(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Phone           string `json:"phone"`
		FirebaseIDToken string `json:"firebaseIdToken"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
	if httpx.DecodeJSON(r, &in) != nil {
		httpx.ErrorCode(w, 400, "Invalid verification request.", "bad_request")
		return
	}
	id := auth.MustFromContext(r.Context()).UserID
	if err := h.svc.verifyAccountPhone(r.Context(), id, in.Phone, in.FirebaseIDToken); err != nil {
		h.writeServiceError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Service) verifyAccountPhone(ctx context.Context, id, input, token string) error {
	phone, err := normalizeSignupPhone(input)
	if err != nil {
		return err
	}
	if s.verifySignupPhone == nil {
		return errSignupProofUnavailable
	}
	if err := s.verifySignupPhone(ctx, token, phone); err != nil {
		return err
	}
	var updated string
	err = s.repo.pool.QueryRow(ctx, `UPDATE users SET phone=$2,phone_verified=true,updated_at=now()
        WHERE id=$1 AND (NOT phone_verified OR phone=$2) RETURNING id`, id, phone).Scan(&updated)
	if errors.Is(err, pgx.ErrNoRows) {
		return invalid("This account already has a verified phone number.")
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.ConstraintName == "users_verified_phone_unique" {
		return ErrPhoneExists
	}
	return err
}
