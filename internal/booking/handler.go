package booking

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// Handler handles booking HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates a booking handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// ChurchRoutes returns routes nested under /churches/{churchId}/bookings.
func (h *Handler) ChurchRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Post("/", h.create)
	return r
}

// Routes returns routes under /bookings/{bookingId}.
func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.listMine)
	r.Get("/{bookingId}", h.get)
	r.Patch("/{bookingId}/status", h.updateStatus)
	r.Patch("/{bookingId}/cancel", h.cancel)
	return r
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")
	pp := httpx.ParsePageParams(r)
	status := Status(r.URL.Query().Get("status"))
	search := r.URL.Query().Get("search")

	items, total, err := h.svc.List(r.Context(), id, churchID, status, search, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

// listMine returns the calling user's bookings across all churches.
func (h *Handler) listMine(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	pp := httpx.ParsePageParams(r)
	status := Status(r.URL.Query().Get("status"))
	search := r.URL.Query().Get("search")

	items, total, err := h.svc.ListMine(r.Context(), id, status, search, pp.Limit, pp.Offset)
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

	b, err := h.svc.Create(r.Context(), id, churchID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, b)
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	b, err := h.svc.Get(r.Context(), id, chi.URLParam(r, "bookingId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, b)
}

func (h *Handler) updateStatus(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	bookingID := chi.URLParam(r, "bookingId")

	var in StatusUpdateRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	b, err := h.svc.UpdateStatus(r.Context(), id, bookingID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, b)
}

func (h *Handler) cancel(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	bookingID := chi.URLParam(r, "bookingId")

	// Body is optional; tolerate an empty body.
	var in CancelRequest
	if r.ContentLength != 0 {
		if err := httpx.DecodeJSON(r, &in); err != nil {
			httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
			return
		}
	}

	b, err := h.svc.Cancel(r.Context(), id, bookingID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, b)
}

func (h *Handler) writeError(w http.ResponseWriter, err error) {
	var ve *ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.ErrorCode(w, http.StatusBadRequest, ve.Message, "bad_request")
	case errors.Is(err, ErrForbidden):
		httpx.ErrorCode(w, http.StatusForbidden, "insufficient permissions", "forbidden")
	case errors.Is(err, ErrHallNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "hall not found", "not_found")
	case errors.Is(err, ErrOverlap):
		httpx.ErrorCode(w, http.StatusConflict, ErrOverlap.Error(), "conflict")
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "booking not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
