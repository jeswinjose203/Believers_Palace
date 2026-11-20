package chatlive

import (
	"net/http"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

type preference struct {
	Room
	Muted bool `json:"muted"`
}

func (p Postgres) ListJoinedCommunities(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	rows, err := p.Pool.Query(r.Context(), `SELECT c.id,c.name FROM community_memberships m
		JOIN communities c ON c.id=m.community_id WHERE m.user_id=$1 AND m.status='active'`, id.UserID)
	if err != nil {
		httpx.Error(w, http.StatusServiceUnavailable, "could not load joined communities")
		return
	}
	defer rows.Close()
	result := map[string]string{}
	for rows.Next() {
		var id, name string
		if rows.Scan(&id, &name) != nil {
			httpx.Error(w, http.StatusServiceUnavailable, "could not load joined communities")
			return
		}
		result[id] = name
	}
	if rows.Err() != nil {
		httpx.Error(w, http.StatusServiceUnavailable, "could not load joined communities")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"data": result})
}

func (p Postgres) ListPreferences(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	rows, err := p.Pool.Query(r.Context(), `SELECT kind,room_id,muted
		FROM chat_notification_preferences WHERE user_id=$1`, id.UserID)
	if err != nil {
		httpx.Error(w, http.StatusServiceUnavailable, "could not load chat preferences")
		return
	}
	defer rows.Close()
	result := make([]preference, 0)
	for rows.Next() {
		var item preference
		if rows.Scan(&item.Kind, &item.ID, &item.Muted) != nil {
			httpx.Error(w, http.StatusServiceUnavailable, "could not load chat preferences")
			return
		}
		result = append(result, item)
	}
	if rows.Err() != nil {
		httpx.Error(w, http.StatusServiceUnavailable, "could not load chat preferences")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"data": result})
}

func (p Postgres) SetPreference(h *Hub) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		room := Room{Kind: chi.URLParam(r, "kind"), ID: chi.URLParam(r, "roomId")}
		var uuid pgtype.UUID
		var input struct {
			Muted      *bool `json:"muted"`
			FollowOnly bool  `json:"followOnly"`
		}
		if uuid.Scan(room.ID) != nil || httpx.DecodeJSON(r, &input) != nil ||
			(input.Muted == nil && (!input.FollowOnly || room.Kind != "event")) {
			httpx.Error(w, http.StatusBadRequest, "valid room and mute preference required")
			return
		}
		id := auth.MustFromContext(r.Context())
		if !h.authorize(r.Context(), id, room) {
			httpx.Error(w, http.StatusForbidden, "chat access is required")
			return
		}
		query := `INSERT INTO chat_notification_preferences
			(user_id, kind, room_id, muted) VALUES ($1,$2,$3,$4)
			ON CONFLICT (user_id, kind, room_id) `
		muted := false
		if input.Muted != nil {
			muted = *input.Muted
		}
		if input.FollowOnly {
			query += "DO NOTHING"
		} else {
			query += "DO UPDATE SET muted=EXCLUDED.muted"
		}
		_, err := p.Pool.Exec(r.Context(), query, id.UserID, room.Kind, room.ID, muted)
		if err != nil {
			httpx.Error(w, http.StatusServiceUnavailable, "could not save chat preferences")
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]bool{"saved": true})
	}
}
