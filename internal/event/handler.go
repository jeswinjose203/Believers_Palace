package event

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// Handler handles event HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates an event handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// ChurchRoutes returns routes nested under /churches/{churchId}/events.
func (h *Handler) ChurchRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Post("/", h.create)
	return r
}

// Routes returns routes under /events/{eventId}.
func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/{eventId}", h.get)
	r.Put("/{eventId}", h.update)
	r.Delete("/{eventId}", h.delete)
	r.Post("/{eventId}/register", h.register)
	r.Get("/{eventId}/registrations", h.listRegistrations)
	return r
}

// RoutesWith returns the event routes with an additional sub-router mounted at
// /{eventId}/messages (used to attach the per-event chat without coupling the
// event package to the chat package).
func (h *Handler) RoutesWith(messages chi.Router) chi.Router {
	r := h.Routes().(*chi.Mux)
	if messages != nil {
		r.Mount("/{eventId}/messages", messages)
	}
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

	var in Request
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	e, err := h.svc.Create(r.Context(), id, churchID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, e)
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	e, err := h.svc.Get(r.Context(), chi.URLParam(r, "eventId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, e)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	eventID := chi.URLParam(r, "eventId")

	var in Request
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	e, err := h.svc.Update(r.Context(), id, eventID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, e)
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	if err := h.svc.Delete(r.Context(), id, chi.URLParam(r, "eventId")); err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	eventID := chi.URLParam(r, "eventId")

	var in RegistrationRequest
	if r.ContentLength != 0 {
		if err := httpx.DecodeJSON(r, &in); err != nil {
			httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
			return
		}
	}

	reg, err := h.svc.Register(r.Context(), id, eventID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, reg)
}

func (h *Handler) listRegistrations(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	eventID := chi.URLParam(r, "eventId")
	pp := httpx.ParsePageParams(r)

	items, total, err := h.svc.ListRegistrations(r.Context(), id, eventID, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) writeError(w http.ResponseWriter, err error) {
	var ve *ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.ErrorCode(w, http.StatusBadRequest, ve.Message, "bad_request")
	case errors.Is(err, ErrForbidden):
		httpx.ErrorCode(w, http.StatusForbidden, "insufficient permissions", "forbidden")
	case errors.Is(err, ErrAlreadyRegistered):
		httpx.ErrorCode(w, http.StatusConflict, "already registered for this event", "conflict")
	case errors.Is(err, ErrRegistrationUnavailable):
		httpx.ErrorCode(w, http.StatusConflict, "event registration unavailable", "conflict")
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "event not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
