package chatlive

import (
	"net/http"
	"strings"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

func (p Postgres) PushDevice(enabled, remove bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var input struct {
			Token string `json:"token"`
		}
		if httpx.DecodeJSON(r, &input) != nil || input.Token == "" || len(input.Token) > 512 ||
			strings.TrimSpace(input.Token) != input.Token {
			httpx.Error(w, http.StatusBadRequest, "valid device token required")
			return
		}
		id := auth.MustFromContext(r.Context())
		var err error
		switch {
		case remove:
			_, err = p.Pool.Exec(r.Context(), "DELETE FROM chat_push_devices WHERE token=$1 AND user_id=$2", input.Token, id.UserID)
		case enabled:
			_, err = p.Pool.Exec(r.Context(), `INSERT INTO chat_push_devices (token, user_id) VALUES ($1,$2)
				ON CONFLICT (token) DO UPDATE SET user_id=EXCLUDED.user_id, updated_at=now()`, input.Token, id.UserID)
		default:
			httpx.Error(w, http.StatusServiceUnavailable, "push notifications are not configured")
			return
		}
		if err != nil {
			httpx.Error(w, http.StatusServiceUnavailable, "could not update push registration")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}
