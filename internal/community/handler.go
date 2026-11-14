package community

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Post("/", h.create)
	r.Post("/{communityId}/requests", h.request)
	r.Get("/{communityId}/requests", h.requests)
	r.Post("/{communityId}/requests/{requestId}/approve", h.approve)
	r.Post("/{communityId}/requests/{requestId}/decline", h.decline)
	r.Get("/{communityId}/members", h.members)
	r.Delete("/{communityId}/members/{userId}", h.remove)
	r.Delete("/{communityId}/leave", h.leave)
	r.Get("/{communityId}/messages", h.listMessages)
	r.Post("/{communityId}/messages", h.postMessage)
	r.Delete("/{communityId}/messages/{messageId}", h.deleteMessage)
	return r
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.List(r.Context(), auth.MustFromContext(r.Context()))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"data": items})
}
func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var in CreateRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	c, err := h.svc.Create(r.Context(), auth.MustFromContext(r.Context()), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, c)
}
func (h *Handler) request(w http.ResponseWriter, r *http.Request) {
	m, err := h.svc.Request(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, m)
}
func (h *Handler) requests(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.Requests(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"data": items})
}
func (h *Handler) review(w http.ResponseWriter, r *http.Request, approve bool) {
	err := h.svc.Review(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"), chi.URLParam(r, "requestId"), approve)
	if err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
func (h *Handler) approve(w http.ResponseWriter, r *http.Request) { h.review(w, r, true) }
func (h *Handler) decline(w http.ResponseWriter, r *http.Request) { h.review(w, r, false) }
func (h *Handler) members(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.Members(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"data": items})
}
func (h *Handler) remove(w http.ResponseWriter, r *http.Request) {
	err := h.svc.Remove(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"), chi.URLParam(r, "userId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
func (h *Handler) leave(w http.ResponseWriter, r *http.Request) {
	err := h.svc.Leave(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
func (h *Handler) listMessages(w http.ResponseWriter, r *http.Request) {
	v := r.URL.Query()
	q := CursorQuery{Limit: defaultCursorLimit}
	parse := func(key string) (int64, error) {
		if !v.Has(key) {
			return 0, nil
		}
		n, e := strconv.ParseInt(v.Get(key), 10, 64)
		if e != nil || n < 1 {
			return 0, &ValidationError{key + " must be a positive integer"}
		}
		return n, nil
	}
	var err error
	if q.Before, err = parse("before"); err == nil {
		q.After, err = parse("after")
	}
	if err == nil && v.Has("limit") {
		q.Limit, err = strconv.Atoi(v.Get("limit"))
		if err != nil || q.Limit < 1 {
			err = &ValidationError{"limit must be a positive integer"}
		}
	}
	if err != nil {
		h.writeError(w, err)
		return
	}
	page, err := h.svc.ListMessages(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"), q)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, page)
}
func (h *Handler) postMessage(w http.ResponseWriter, r *http.Request) {
	var in MessageRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	m, err := h.svc.Post(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, m)
}
func (h *Handler) deleteMessage(w http.ResponseWriter, r *http.Request) {
	err := h.svc.DeleteMessage(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "communityId"), chi.URLParam(r, "messageId"))
	if err != nil {
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
	case errors.Is(err, ErrNotMember):
		httpx.ErrorCode(w, http.StatusForbidden, ErrNotMember.Error(), "not_member")
	case errors.Is(err, ErrConflict):
		httpx.ErrorCode(w, http.StatusConflict, ErrConflict.Error(), "conflict")
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, ErrNotFound.Error(), "not_found")
	case errors.Is(err, ErrLastAdmin):
		httpx.ErrorCode(w, http.StatusForbidden, ErrLastAdmin.Error(), "forbidden")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
