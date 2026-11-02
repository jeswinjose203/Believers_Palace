package cemetery

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// Handler handles cemetery HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates a cemetery handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// PlotChurchRoutes returns routes under /churches/{churchId}/cemetery-plots.
func (h *Handler) PlotChurchRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.listPlots)
	r.Post("/", h.createPlot)
	return r
}

// PlotRoutes returns routes under /cemetery-plots/{plotId}.
func (h *Handler) PlotRoutes() chi.Router {
	r := chi.NewRouter()
	r.Put("/{plotId}", h.updatePlot)
	r.Delete("/{plotId}", h.deletePlot)
	return r
}

// RequestChurchRoutes returns routes under /churches/{churchId}/cemetery-service-requests.
func (h *Handler) RequestChurchRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.listRequests)
	r.Post("/", h.createRequest)
	return r
}

// RequestRoutes returns routes under /cemetery-service-requests/{requestId}.
func (h *Handler) RequestRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/{requestId}", h.getRequest)
	r.Patch("/{requestId}/status", h.updateRequestStatus)
	return r
}

func (h *Handler) listPlots(w http.ResponseWriter, r *http.Request) {
	churchID := chi.URLParam(r, "churchId")
	pp := httpx.ParsePageParams(r)
	status := PlotStatus(r.URL.Query().Get("status"))
	search := r.URL.Query().Get("search")
	items, total, err := h.svc.ListPlots(r.Context(), churchID, status, search, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) createPlot(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")

	var in PlotCreateRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	p, err := h.svc.CreatePlot(r.Context(), id, churchID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, p)
}

func (h *Handler) updatePlot(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	plotID := chi.URLParam(r, "plotId")

	var in PlotUpdateRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	p, err := h.svc.UpdatePlot(r.Context(), id, plotID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

func (h *Handler) deletePlot(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	if err := h.svc.DeletePlot(r.Context(), id, chi.URLParam(r, "plotId")); err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) listRequests(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")
	pp := httpx.ParsePageParams(r)
	status := RequestStatus(r.URL.Query().Get("status"))
	typ := ServiceType(r.URL.Query().Get("type"))
	search := r.URL.Query().Get("search")

	items, total, err := h.svc.ListRequests(r.Context(), id, churchID, status, typ, search, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) createRequest(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")

	var in ServiceRequestCreate
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	sr, err := h.svc.CreateRequest(r.Context(), id, churchID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, sr)
}

func (h *Handler) getRequest(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	sr, err := h.svc.GetRequest(r.Context(), id, chi.URLParam(r, "requestId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, sr)
}

func (h *Handler) updateRequestStatus(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	requestID := chi.URLParam(r, "requestId")

	var in RequestStatusUpdate
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	sr, err := h.svc.UpdateRequestStatus(r.Context(), id, requestID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, sr)
}

func (h *Handler) writeError(w http.ResponseWriter, err error) {
	var ve *ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.ErrorCode(w, http.StatusBadRequest, ve.Message, "bad_request")
	case errors.Is(err, ErrForbidden):
		httpx.ErrorCode(w, http.StatusForbidden, "insufficient permissions", "forbidden")
	case errors.Is(err, ErrPlotNumberExists):
		httpx.ErrorCode(w, http.StatusConflict, "plot number already exists", "conflict")
	case errors.Is(err, ErrPlotUnavailable):
		httpx.ErrorCode(w, http.StatusConflict, "requested plot is not available", "conflict")
	case errors.Is(err, ErrPlotNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "cemetery plot not found", "not_found")
	case errors.Is(err, ErrRequestNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "cemetery service request not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
