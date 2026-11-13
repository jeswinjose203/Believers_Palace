package personalcalendar
 
import (
    "errors"
    "net/http"
    "strconv"
    "time"
 
    "github.com/go-chi/chi/v5"
 
    "believers_palace/internal/auth"
    "believers_palace/internal/httpx"
)
 
// Handler handles personal calendar HTTP requests.
type Handler struct {
    svc *Service
}
 
// NewHandler creates a calendar handler.
func NewHandler(svc *Service) *Handler {
    return &Handler{svc: svc}
}
 
// Routes returns routes mounted at /users/me/calendar.
func (h *Handler) Routes() chi.Router {
    r := chi.NewRouter()
    r.Get("/preferences", h.getPreferences)
    r.Patch("/preferences", h.patchPreferences)
    r.Get("/events", h.listEvents)
    r.Post("/events", h.createEvent)
    r.Route("/events/{eventId}", func(er chi.Router) {
        er.Get("/", h.getEvent)
        er.Patch("/", h.updateEvent)
        er.Delete("/", h.deleteEvent)
    })
    r.Get("/tasks", h.listTasks)
    r.Post("/tasks", h.createTask)
    r.Route("/tasks/{taskId}", func(tr chi.Router) {
        tr.Patch("/", h.patchTask)
        tr.Delete("/", h.deleteTask)
    })
    r.Get("/schedule", h.schedule)
    r.Get("/goals", h.listGoals)
    r.Post("/goals", h.createGoal)
    r.Route("/goals/{goalId}", func(gr chi.Router) {
        gr.Patch("/", h.updateGoal)
        gr.Delete("/", h.deleteGoal)
        gr.Put("/checkins/{date}", h.checkIn)
        gr.Delete("/checkins/{date}", h.removeCheckIn)
    })
    r.Get("/achievements", h.listAchievements)
    return r
}
 
// HolidayRoutes returns GET /calendar/holidays.
func (h *Handler) HolidayRoutes() chi.Router {
    r := chi.NewRouter()
    r.Get("/", h.holidays)
    return r
}
 
func (h *Handler) getPreferences(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    p, err := h.svc.GetOrCreatePreferences(r.Context(), id)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, p)
}
 
func (h *Handler) patchPreferences(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    var patch PreferencesPatch
    if err := httpx.DecodeJSON(r, &patch); err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
        return
    }
    p, err := h.svc.PatchPreferences(r.Context(), id, patch)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, p)
}
 
func (h *Handler) listEvents(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    pp := httpx.ParsePageParams(r)
    items, total, err := h.svc.ListEvents(r.Context(), id, r.URL.Query().Get("search"), r.URL.Query().Get("category"), pp.Limit, pp.Offset)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.Paged(w, items, pp.Page, pp.Limit, total)
}
 
func (h *Handler) createEvent(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    var in EventRequest
    if err := httpx.DecodeJSON(r, &in); err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
        return
    }
    e, err := h.svc.CreateEvent(r.Context(), id, in)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusCreated, e)
}
 
func (h *Handler) getEvent(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    e, err := h.svc.GetEvent(r.Context(), id, chi.URLParam(r, "eventId"))
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, e)
}
 
func (h *Handler) updateEvent(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    var in EventRequest
    if err := httpx.DecodeJSON(r, &in); err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
        return
    }
    e, err := h.svc.UpdateEvent(r.Context(), id, chi.URLParam(r, "eventId"), in)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, e)
}
 
func (h *Handler) deleteEvent(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    if err := h.svc.DeleteEvent(r.Context(), id, chi.URLParam(r, "eventId")); err != nil {
        h.writeError(w, err)
        return
    }
    w.WriteHeader(http.StatusNoContent)
}
 
func (h *Handler) listTasks(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    pp := httpx.ParsePageParams(r)
    items, total, err := h.svc.ListTasks(r.Context(), id, pp.Limit, pp.Offset)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.Paged(w, items, pp.Page, pp.Limit, total)
}
 
func (h *Handler) createTask(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    var in TaskRequest
    if err := httpx.DecodeJSON(r, &in); err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
        return
    }
    t, err := h.svc.CreateTask(r.Context(), id, in)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusCreated, t)
}
 
func (h *Handler) patchTask(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    var in TaskPatch
    if err := httpx.DecodeJSON(r, &in); err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
        return
    }
    t, err := h.svc.PatchTask(r.Context(), id, chi.URLParam(r, "taskId"), in)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, t)
}
 
func (h *Handler) deleteTask(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    if err := h.svc.DeleteTask(r.Context(), id, chi.URLParam(r, "taskId")); err != nil {
        h.writeError(w, err)
        return
    }
    w.WriteHeader(http.StatusNoContent)
}
 
func (h *Handler) schedule(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    from, to, err := parseRange(r)
    if err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, err.Error(), "bad_request")
        return
    }
    items, err := h.svc.Schedule(r.Context(), id, from, to)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, map[string]any{"data": items})
}
 
func (h *Handler) listGoals(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    pp := httpx.ParsePageParams(r)
    items, total, err := h.svc.ListGoals(r.Context(), id, r.URL.Query().Get("status"), pp.Limit, pp.Offset)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.Paged(w, items, pp.Page, pp.Limit, total)
}
 
func (h *Handler) createGoal(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    var in GoalRequest
    if err := httpx.DecodeJSON(r, &in); err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
        return
    }
    g, err := h.svc.CreateGoal(r.Context(), id, in)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusCreated, g)
}
 
func (h *Handler) updateGoal(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    var in GoalRequest
    if err := httpx.DecodeJSON(r, &in); err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
        return
    }
    g, err := h.svc.UpdateGoal(r.Context(), id, chi.URLParam(r, "goalId"), in)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, g)
}
 
func (h *Handler) deleteGoal(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    if err := h.svc.DeleteGoal(r.Context(), id, chi.URLParam(r, "goalId")); err != nil {
        h.writeError(w, err)
        return
    }
    w.WriteHeader(http.StatusNoContent)
}
 
func (h *Handler) checkIn(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    day, err := time.Parse("2006-01-02", chi.URLParam(r, "date"))
    if err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid date", "bad_request")
        return
    }
    var note string
    if r.ContentLength > 0 {
        var in CheckInRequest
        if err := httpx.DecodeJSON(r, &in); err == nil {
            note = in.Note
        }
    }
    resp, err := h.svc.CheckIn(r.Context(), id, chi.URLParam(r, "goalId"), day, note)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, resp)
}
 
func (h *Handler) removeCheckIn(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    day, err := time.Parse("2006-01-02", chi.URLParam(r, "date"))
    if err != nil {
        httpx.ErrorCode(w, http.StatusBadRequest, "invalid date", "bad_request")
        return
    }
    g, err := h.svc.RemoveCheckIn(r.Context(), id, chi.URLParam(r, "goalId"), day)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, g)
}
 
func (h *Handler) listAchievements(w http.ResponseWriter, r *http.Request) {
    id := auth.MustFromContext(r.Context())
    items, err := h.svc.ListAchievements(r.Context(), id)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, map[string]any{"data": items})
}
 
func (h *Handler) holidays(w http.ResponseWriter, r *http.Request) {
    year := time.Now().Year()
    if y := r.URL.Query().Get("year"); y != "" {
        v, err := strconv.Atoi(y)
        if err != nil {
            httpx.ErrorCode(w, http.StatusBadRequest, "invalid year", "bad_request")
            return
        }
        year = v
    }
    country := r.URL.Query().Get("country")
    items, err := h.svc.Holidays(r.Context(), year, country)
    if err != nil {
        h.writeError(w, err)
        return
    }
    httpx.JSON(w, http.StatusOK, map[string]any{"data": items})
}
 
func parseRange(r *http.Request) (time.Time, time.Time, error) {
    fromS := r.URL.Query().Get("from")
    toS := r.URL.Query().Get("to")
    if fromS == "" || toS == "" {
        return time.Time{}, time.Time{}, errors.New("from and to are required (RFC3339)")
    }
    from, err := time.Parse(time.RFC3339, fromS)
    if err != nil {
        return time.Time{}, time.Time{}, errors.New("invalid from")
    }
    to, err := time.Parse(time.RFC3339, toS)
    if err != nil {
        return time.Time{}, time.Time{}, errors.New("invalid to")
    }
    return from, to, nil
}
 
func (h *Handler) writeError(w http.ResponseWriter, err error) {
    var ve *ValidationError
    if errors.As(err, &ve) {
        httpx.ErrorCode(w, http.StatusBadRequest, ve.Message, "bad_request")
        return
    }
    if errors.Is(err, ErrNotFound) {
        httpx.ErrorCode(w, http.StatusNotFound, "not found", "not_found")
        return
    }
    httpx.Error(w, http.StatusInternalServerError, "internal error")
}
 