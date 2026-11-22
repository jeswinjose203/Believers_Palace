package social

import (
	"errors"
	"log"
	"net/http"
	"regexp"
	"strings"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
	"believers_palace/internal/media"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Handler struct {
	db    *pgxpool.Pool
	media *media.Service
}

func New(db *pgxpool.Pool, mediaService *media.Service) *Handler {
	return &Handler{db: db, media: mediaService}
}

func (h *Handler) Routes(verifiedEmail func(http.Handler) http.Handler) chi.Router {
	r := chi.NewRouter()
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			w.Header().Set("Cache-Control", "private, no-store")
			next.ServeHTTP(w, req)
		})
	})
	r.Get("/feed", h.feed)
	r.Post("/posts", h.createPost)
	r.Put("/posts/{id}/like", h.like)
	r.Delete("/posts/{id}/like", h.unlike)
	r.Post("/media", h.upload)
	r.Get("/me", h.me)
	r.Put("/me", h.changeUsername)
	r.Group(func(r chi.Router) {
		r.Use(verifiedEmail)
		r.Get("/people", h.people)
		r.Get("/people/{id}/thread", h.findThread)
		r.Get("/threads", h.inbox)
		r.Post("/messages", h.send)
		r.Get("/threads/{id}/messages", h.messages)
		r.Delete("/threads/{id}", h.hide)
	})
	return r
}

func viewer(r *http.Request) string {
	return auth.MustFromContext(r.Context()).UserID
}

var (
	usernamePattern = regexp.MustCompile(`^[a-z0-9_]{3,32}$`)
	clientPattern   = regexp.MustCompile(`^[a-f0-9]{32}$`)
	mediaPattern    = regexp.MustCompile(`^[a-f0-9]{32}\.(jpg|png|gif|webp|mp4|webm)$`)
)

func validUUID(s string) bool {
	var id pgtype.UUID
	return len(s) == 36 && id.Scan(s) == nil && id.Valid
}

func bad(w http.ResponseWriter, message string) {
	httpx.ErrorCode(w, http.StatusBadRequest, message, "bad_request")
}

func failure(w http.ResponseWriter, err error) {
	var pg *pgconn.PgError
	switch {
	case errors.Is(err, pgx.ErrNoRows), errors.As(err, &pg) && pg.Code == "23503":
		httpx.ErrorCode(w, 404, "Resource not found.", "not_found")
	case errors.As(err, &pg) && pg.Code == "23505":
		httpx.ErrorCode(w, 409, "That username is already taken.", "conflict")
	default:
		log.Printf("social request failed: %v", err)
		httpx.ErrorCode(w, 500, "Request failed.", "internal_error")
	}
}

func decode(w http.ResponseWriter, r *http.Request, value any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 32<<10)
	if httpx.DecodeJSON(r, value) != nil {
		bad(w, "Invalid request body.")
		return false
	}
	return true
}

type person struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Username string `json:"username"`
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	var p person
	err := h.db.QueryRow(r.Context(), `SELECT id,name,username FROM users WHERE id=$1`, viewer(r)).Scan(&p.ID, &p.Name, &p.Username)
	if err != nil {
		failure(w, err)
		return
	}
	httpx.JSON(w, 200, p)
}

func (h *Handler) changeUsername(w http.ResponseWriter, r *http.Request) {
	var in struct{ Username string }
	if !decode(w, r, &in) {
		return
	}
	name := strings.ToLower(strings.TrimPrefix(strings.TrimSpace(in.Username), "@"))
	if !usernamePattern.MatchString(name) {
		bad(w, "Use 3�32 letters, digits or underscores.")
		return
	}
	var p person
	err := h.db.QueryRow(r.Context(), `UPDATE users SET username=$2 WHERE id=$1 RETURNING id,name,username`, viewer(r), name).Scan(&p.ID, &p.Name, &p.Username)
	if err != nil {
		failure(w, err)
		return
	}
	httpx.JSON(w, 200, p)
}

func (h *Handler) people(w http.ResponseWriter, r *http.Request) {
	prefix := strings.ToLower(strings.TrimPrefix(strings.TrimSpace(r.URL.Query().Get("q")), "@"))
	if !usernamePattern.MatchString(prefix) {
		bad(w, "Enter at least 3 username characters.")
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT id,name,username FROM users
        WHERE id<>$1 AND email_verified AND username LIKE $2 ESCAPE '!' ORDER BY username USING ~<~ LIMIT 20`,
		viewer(r), strings.ReplaceAll(prefix, "_", "!_")+"%")
	if err != nil {
		failure(w, err)
		return
	}
	items, err := pgx.CollectRows(rows, pgx.RowToStructByPos[person])
	if err != nil {
		failure(w, err)
		return
	}
	httpx.JSON(w, 200, map[string]any{"data": items})
}
