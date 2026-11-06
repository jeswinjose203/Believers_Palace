package chat

import (
	"errors"
	"net/http"

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

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	eventID := chi.URLParam(r, "eventId")
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
	httpx.JSON(w, http.StatusNoContent, nil)
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
