package announcement

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// Handler handles announcement HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates an announcement handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// ChurchRoutes returns routes nested under /churches/{churchId}/announcements.
// All routes assume the auth middleware has already run.
func (h *Handler) ChurchRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Post("/", h.create)
	return r
}

// Routes returns routes under /announcements/{announcementId}.
func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Put("/{announcementId}", h.update)
	r.Delete("/{announcementId}", h.delete)
	return r
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	churchID := chi.URLParam(r, "churchId")
	pp := httpx.ParsePageParams(r)
	search := r.URL.Query().Get("search")
	items, total, err := h.svc.List(r.Context(), churchID, search, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")

	var in CreateRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	a, err := h.svc.Create(r.Context(), id, churchID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, a)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	announcementID := chi.URLParam(r, "announcementId")

	var in UpdateRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	a, err := h.svc.Update(r.Context(), id, announcementID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, a)
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	if err := h.svc.Delete(r.Context(), id, chi.URLParam(r, "announcementId")); err != nil {
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
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "announcement not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
