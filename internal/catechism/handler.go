package catechism

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// Handler handles catechism HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates a catechism handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// ChurchRoutes returns routes nested under /churches/{churchId}/catechism-classes.
func (h *Handler) ChurchRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.listClasses)
	r.Post("/", h.createClass)
	return r
}

// ClassRoutes returns routes under /catechism-classes/{classId}.
func (h *Handler) ClassRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/{classId}", h.getClass)
	r.Put("/{classId}", h.updateClass)
	r.Delete("/{classId}", h.deleteClass)
	r.Get("/{classId}/enrollments", h.listEnrollments)
	r.Post("/{classId}/enrollments", h.createEnrollment)
	r.Get("/{classId}/sessions", h.listSessions)
	r.Post("/{classId}/sessions", h.createSession)
	return r
}

// EnrollmentRoutes returns routes under /catechism-enrollments.
func (h *Handler) EnrollmentRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.listMyEnrollments)
	r.Patch("/{enrollmentId}/status", h.updateEnrollmentStatus)
	r.Patch("/{enrollmentId}/withdraw", h.withdrawEnrollment)
	return r
}

// SessionRoutes returns routes under /catechism-sessions/{sessionId}.
func (h *Handler) SessionRoutes() chi.Router {
	r := chi.NewRouter()
	r.Put("/{sessionId}", h.updateSession)
	r.Delete("/{sessionId}", h.deleteSession)
	return r
}

func (h *Handler) listClasses(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")
	pp := httpx.ParsePageParams(r)
	search := r.URL.Query().Get("search")
	status := ClassStatus(r.URL.Query().Get("status"))
	level := ClassLevel(r.URL.Query().Get("level"))
	items, total, err := h.svc.ListClasses(r.Context(), id, churchID, search, status, level, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) createClass(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")
	var in ClassRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	c, err := h.svc.CreateClass(r.Context(), id, churchID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, c)
}

func (h *Handler) getClass(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	c, err := h.svc.GetClass(r.Context(), id, chi.URLParam(r, "classId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, c)
}

func (h *Handler) updateClass(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	var in ClassRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	c, err := h.svc.UpdateClass(r.Context(), id, chi.URLParam(r, "classId"), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, c)
}

func (h *Handler) deleteClass(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	if err := h.svc.DeleteClass(r.Context(), id, chi.URLParam(r, "classId")); err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) listEnrollments(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	classID := chi.URLParam(r, "classId")
	pp := httpx.ParsePageParams(r)
	search := r.URL.Query().Get("search")
	items, total, err := h.svc.ListEnrollmentsByClass(r.Context(), id, classID, search, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) createEnrollment(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	classID := chi.URLParam(r, "classId")
	var in EnrollmentRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	e, err := h.svc.CreateEnrollment(r.Context(), id, classID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, e)
}

func (h *Handler) listMyEnrollments(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	pp := httpx.ParsePageParams(r)
	search := r.URL.Query().Get("search")
	items, total, err := h.svc.ListMyEnrollments(r.Context(), id, search, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) updateEnrollmentStatus(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	var in EnrollmentStatusRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	e, err := h.svc.UpdateEnrollmentStatus(r.Context(), id, chi.URLParam(r, "enrollmentId"), in.Status)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, e)
}

func (h *Handler) withdrawEnrollment(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	e, err := h.svc.WithdrawEnrollment(r.Context(), id, chi.URLParam(r, "enrollmentId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, e)
}

func (h *Handler) listSessions(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	classID := chi.URLParam(r, "classId")
	pp := httpx.ParsePageParams(r)
	search := r.URL.Query().Get("search")
	items, total, err := h.svc.ListSessions(r.Context(), id, classID, search, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) createSession(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	classID := chi.URLParam(r, "classId")
	var in SessionRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	s, err := h.svc.CreateSession(r.Context(), id, classID, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, s)
}

func (h *Handler) updateSession(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	var in SessionRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	s, err := h.svc.UpdateSession(r.Context(), id, chi.URLParam(r, "sessionId"), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, s)
}

func (h *Handler) deleteSession(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	if err := h.svc.DeleteSession(r.Context(), id, chi.URLParam(r, "sessionId")); err != nil {
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
	case errors.Is(err, ErrClassFull), errors.Is(err, ErrDuplicateEnrollment):
		httpx.ErrorCode(w, http.StatusConflict, err.Error(), "conflict")
	case errors.Is(err, ErrClassNotOpen):
		httpx.ErrorCode(w, http.StatusBadRequest, err.Error(), "bad_request")
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "resource not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}