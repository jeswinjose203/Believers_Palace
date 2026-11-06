package chat

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// Handler handles event chat HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates a chat handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// EventRoutes returns routes nested under /events/{eventId}/messages.
func (h *Handler) EventRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Post("/", h.post)
	r.Delete("/{messageId}", h.delete)
	return r
}

// parseCursorQuery reads the cursor parameters (before, after, limit). The
// second return value reports whether cursor mode was requested at all, which
// is the case when any of before, after or latest is present.
func parseCursorQuery(r *http.Request) (CursorQuery, bool, error) {
	v := r.URL.Query()
	if !v.Has("before") && !v.Has("after") && !v.Has("latest") {
		return CursorQuery{}, false, nil
	}
	q := CursorQuery{Limit: DefaultCursorLimit}
	parse := func(name string) (int64, error) {
		if !v.Has(name) {
			return 0, nil
		}
		n, err := strconv.ParseInt(v.Get(name), 10, 64)
		if err != nil || n < 1 {
			return 0, invalid(name + " must be a positive integer")
		}
		return n, nil
	}
	var err error
	if q.Before, err = parse("before"); err != nil {
		return q, true, err
	}
	if q.After, err = parse("after"); err != nil {
		return q, true, err
	}
	if v.Has("limit") {
		n, err := strconv.Atoi(v.Get("limit"))
		if err != nil || n < 1 {
			return q, true, invalid("limit must be a positive integer")
		}
		q.Limit = n
	}
	return q, true, nil
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	eventID := chi.URLParam(r, "eventId")

	// Cursor mode: GET ...?latest=1 | ?before=<seq> | ?after=<seq> [&limit=n]
	if cq, ok, err := parseCursorQuery(r); ok {
		if err != nil {
			h.writeError(w, err)
			return
		}
		page, err := h.svc.ListCursor(r.Context(), id, eventID, cq)
		if err != nil {
			h.writeError(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, page)
		return
	}

	pp := httpx.ParsePageParams(r)

	items, total, err := h.svc.List(r.Context(), id, eventID, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) post(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	eventID := chi.URLParam(r, "eventId")

	var in CreateRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	msg, err := h.svc.Post(r.Context(), id, eventID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, msg)
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	eventID := chi.URLParam(r, "eventId")
	messageID := chi.URLParam(r, "messageId")

	if err := h.svc.Delete(r.Context(), id, eventID, messageID); err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) writeError(w http.ResponseWriter, err error) {
	var ve *ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.ErrorCode(w, http.StatusBadRequest, ve.Message, "bad_request")
	case errors.Is(err, ErrForbidden):
		httpx.ErrorCode(w, http.StatusForbidden, "insufficient permissions", "forbidden")
	case errors.Is(err, ErrNotRegistered):
		httpx.ErrorCode(w, http.StatusForbidden, ErrNotRegistered.Error(), "not_registered")
	case errors.Is(err, ErrEventNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "event not found", "not_found")
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "message not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
