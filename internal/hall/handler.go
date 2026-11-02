package hall

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// Handler handles hall HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates a hall handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// ChurchRoutes returns routes nested under /churches/{churchId}/halls.
func (h *Handler) ChurchRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Post("/", h.create)
	return r
}

// Routes returns routes under /halls/{hallId}.
func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/{hallId}", h.get)
	r.Put("/{hallId}", h.update)
	r.Delete("/{hallId}", h.delete)
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

	hall, err := h.svc.Create(r.Context(), id, churchID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, hall)
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	hall, err := h.svc.Get(r.Context(), chi.URLParam(r, "hallId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, hall)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	hallID := chi.URLParam(r, "hallId")

	var in UpdateRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	hall, err := h.svc.Update(r.Context(), id, hallID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, hall)
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	if err := h.svc.Delete(r.Context(), id, chi.URLParam(r, "hallId")); err != nil {
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
		httpx.ErrorCode(w, http.StatusNotFound, "hall not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
