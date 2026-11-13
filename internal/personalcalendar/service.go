package personalcalendar
 
import (
    "context"
    "errors"
    "strings"
    "time"
 
    "believers_palace/internal/auth"
    "believers_palace/internal/booking"
    "believers_palace/internal/event"
)
 
// ValidationError is a client-visible validation failure.
type ValidationError struct{ Message string }
 
func (e *ValidationError) Error() string { return e.Message }
 
func invalid(msg string) error { return &ValidationError{Message: msg} }
 
type bookingLister interface {
    ListOverlappingForUser(ctx context.Context, userID string, from, to time.Time) ([]booking.Booking, error)
}
 
type eventLister interface {
    ListByChurchInRange(ctx context.Context, churchID string, from, to time.Time) ([]event.Event, error)
}
 
// Service holds personal calendar business logic.
type Service struct {
    repo     *Repository
    bookings bookingLister
    events   eventLister
}
 
// NewService creates a personal calendar service.
func NewService(repo *Repository, bookings bookingLister, events eventLister) *Service {
    return &Service{repo: repo, bookings: bookings, events: events}
}
 
// GetOrCreatePreferences returns preferences, inserting defaults on first access.
func (s *Service) GetOrCreatePreferences(ctx context.Context, id auth.Identity) (*Preferences, error) {
    p, err := s.repo.GetPreferences(ctx, id.UserID)
    if errors.Is(err, ErrNotFound) {
        def := Preferences{
            Theme:          "system",
            DateFormat:     "dmy",
            WeekStartsOn:   "monday",
            HolidayCountry: "IN",
            CategoryColors: DefaultCategoryColors(),
        }
        return s.repo.UpsertPreferences(ctx, id.UserID, def)
    }
    return p, err
}
 
// PatchPreferences updates user preferences.
func (s *Service) PatchPreferences(ctx context.Context, id auth.Identity, patch PreferencesPatch) (*Preferences, error) {
    cur, err := s.GetOrCreatePreferences(ctx, id)
    if err != nil {
        return nil, err
    }
    if patch.Theme != nil {
        cur.Theme = *patch.Theme
    }
    if patch.DateFormat != nil {
        cur.DateFormat = *patch.DateFormat
    }
    if patch.WeekStartsOn != nil {
        cur.WeekStartsOn = *patch.WeekStartsOn
    }
    if patch.HolidayCountry != nil {
        cur.HolidayCountry = strings.ToUpper(*patch.HolidayCountry)
    }
    if patch.CategoryColors != nil {
        cur.CategoryColors = *patch.CategoryColors
    }
    return s.repo.UpsertPreferences(ctx, id.UserID, *cur)
}
 
func (s *Service) validateEventRequest(in EventRequest, create bool) error {
    if create && strings.TrimSpace(in.Title) == "" {
        return invalid("title is required")
    }
    if in.Category != "" && !ValidCategory(in.Category) {
        return invalid("invalid category")
    }
    if in.Recurrence != nil && !ValidRecurrence(*in.Recurrence) {
        return invalid("invalid recurrence")
    }
    if create {
        if in.StartAt == nil || in.EndAt == nil {
            return invalid("startAt and endAt are required")
        }
        if in.EndAt.Before(*in.StartAt) {
            return invalid("endAt must be after startAt")
        }
    }
    return nil
}
 
// CreateEvent creates a personal calendar event.
func (s *Service) CreateEvent(ctx context.Context, id auth.Identity, in EventRequest) (*Event, error) {
    if in.Category == "" {
        in.Category = CategoryPersonal
    }
    if err := s.validateEventRequest(in, true); err != nil {
        return nil, err
    }
    return s.repo.CreateEvent(ctx, id.UserID, in)
}
 
// ListEvents lists events with optional search.
func (s *Service) ListEvents(ctx context.Context, id auth.Identity, search, category string, limit, offset int) ([]Event, int, error) {
    return s.repo.ListEvents(ctx, id.UserID, search, category, limit, offset)
}
 
// ListExpandedEvents returns occurrences in a time window.
func (s *Service) ListExpandedEvents(ctx context.Context, id auth.Identity, from, to time.Time) ([]Event, error) {
    raw, err := s.repo.ListEventsForUser(ctx, id.UserID)
    if err != nil {
        return nil, err
    }
    var out []Event
    for _, e := range raw {
        out = append(out, expandEventOccurrences(e, from, to)...)
    }
    return out, nil
}
 
// GetEvent returns one event series row.
func (s *Service) GetEvent(ctx context.Context, id auth.Identity, eventID string) (*Event, error) {
    return s.repo.GetEvent(ctx, id.UserID, eventID)
}
 
// UpdateEvent updates an event series.
func (s *Service) UpdateEvent(ctx context.Context, id auth.Identity, eventID string, in EventRequest) (*Event, error) {
    cur, err := s.repo.GetEvent(ctx, id.UserID, eventID)
    if err != nil {
        return nil, err
    }
    if strings.TrimSpace(in.Title) != "" {
        cur.Title = in.Title
    }
    if in.Description != "" || in.Description == "" {
        cur.Description = in.Description
    }
    if in.Category != "" {
        cur.Category = in.Category
    }
    cur.Color = in.Color
    if in.StartAt != nil {
        cur.StartAt = *in.StartAt
    }
    if in.EndAt != nil {
        cur.EndAt = *in.EndAt
    }
    if in.AllDay != nil {
        cur.AllDay = *in.AllDay
    }
    if in.Recurrence != nil {
        cur.Recurrence = *in.Recurrence
    }
    if in.RecurrenceInterval != nil {
        cur.RecurrenceInterval = *in.RecurrenceInterval
    }
    if in.RecurrenceUntil != nil {
        cur.RecurrenceUntil = in.RecurrenceUntil
    }
    if in.ReminderMinutes != nil {
        cur.ReminderMinutes = in.ReminderMinutes
    }
    merged := EventRequest{
        Title:              cur.Title,
        Description:        cur.Description,
        Category:           cur.Category,
        Color:              cur.Color,
        StartAt:            &cur.StartAt,
        EndAt:              &cur.EndAt,
        AllDay:             &cur.AllDay,
        Recurrence:         &cur.Recurrence,
        RecurrenceInterval: &cur.RecurrenceInterval,
        RecurrenceUntil:    cur.RecurrenceUntil,
        ReminderMinutes:    cur.ReminderMinutes,
    }
    if err := s.validateEventRequest(merged, true); err != nil {
        return nil, err
    }
    return s.repo.UpdateEvent(ctx, id.UserID, eventID, merged)
}
 
// DeleteEvent removes an event.
func (s *Service) DeleteEvent(ctx context.Context, id auth.Identity, eventID string) error {
    return s.repo.DeleteEvent(ctx, id.UserID, eventID)
}
 
// CreateTask creates a task.
func (s *Service) CreateTask(ctx context.Context, id auth.Identity, in TaskRequest) (*Task, error) {
    if strings.TrimSpace(in.Title) == "" {
        return nil, invalid("title is required")
    }
    if in.DueDate == nil {
        return nil, invalid("dueDate is required")
    }
    return s.repo.CreateTask(ctx, id.UserID, in)
}
 
// ListTasks lists tasks.
func (s *Service) ListTasks(ctx context.Context, id auth.Identity, limit, offset int) ([]Task, int, error) {
    return s.repo.ListTasks(ctx, id.UserID, limit, offset)
}
 
// PatchTask updates a task.
func (s *Service) PatchTask(ctx context.Context, id auth.Identity, taskID string, in TaskPatch) (*Task, error) {
    return s.repo.PatchTask(ctx, id.UserID, taskID, in)
}
 
// DeleteTask deletes a task.
func (s *Service) DeleteTask(ctx context.Context, id auth.Identity, taskID string) error {
    return s.repo.DeleteTask(ctx, id.UserID, taskID)
}
 
// CreateGoal creates a goal.
func (s *Service) CreateGoal(ctx context.Context, id auth.Identity, in GoalRequest) (*Goal, error) {
    if strings.TrimSpace(in.Title) == "" {
        return nil, invalid("title is required")
    }
    if in.TargetDays == nil || *in.TargetDays < 1 {
        return nil, invalid("targetDays must be at least 1")
    }
    g, err := s.repo.CreateGoal(ctx, id.UserID, in)
    if err != nil {
        return nil, err
    }
    return s.enrichGoal(ctx, g)
}
 
func (s *Service) enrichGoal(ctx context.Context, g *Goal) (*Goal, error) {
    dates, err := s.repo.ListCheckInDates(ctx, g.ID)
    if err != nil {
        return nil, err
    }
    count, err := s.repo.CountCheckIns(ctx, g.ID)
    if err != nil {
        return nil, err
    }
    g.CheckInCount = count
    g.CurrentStreak = currentStreakEndingOn(dates, time.Now().UTC())
    return g, nil
}
 
// ListGoals lists goals.
func (s *Service) ListGoals(ctx context.Context, id auth.Identity, status string, limit, offset int) ([]Goal, int, error) {
    items, total, err := s.repo.ListGoals(ctx, id.UserID, status, limit, offset)
    if err != nil {
        return nil, 0, err
    }
    for i := range items {
        g, err := s.enrichGoal(ctx, &items[i])
        if err != nil {
            return nil, 0, err
        }
        items[i] = *g
    }
    return items, total, nil
}
 
// UpdateGoal updates a goal.
func (s *Service) UpdateGoal(ctx context.Context, id auth.Identity, goalID string, in GoalRequest) (*Goal, error) {
    g, err := s.repo.UpdateGoal(ctx, id.UserID, goalID, in)
    if err != nil {
        return nil, err
    }
    return s.enrichGoal(ctx, g)
}
 
// DeleteGoal removes a goal.
func (s *Service) DeleteGoal(ctx context.Context, id auth.Identity, goalID string) error {
    return s.repo.DeleteGoal(ctx, id.UserID, goalID)
}
 
// CheckIn records a daily check-in for a goal.
func (s *Service) CheckIn(ctx context.Context, id auth.Identity, goalID string, day time.Time, note string) (*CheckInResponse, error) {
    g, err := s.repo.GetGoal(ctx, id.UserID, goalID)
    if err != nil {
        return nil, err
    }
    if g.Status != GoalActive {
        return nil, invalid("goal is not active")
    }
    day = time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, time.UTC)
    if err := s.repo.UpsertCheckIn(ctx, goalID, day, note); err != nil {
        return nil, err
    }
    g, err = s.enrichGoal(ctx, g)
    if err != nil {
        return nil, err
    }
 
    var newAch []Achievement
    progress := progressForGoal(g.TrackingMode, g.CheckInCount, g.CurrentStreak)
    if progress >= g.TargetDays && g.Status == GoalActive {
        now := time.Now().UTC()
        _ = s.repo.MarkGoalCompleted(ctx, goalID, now)
        g.Status = GoalCompleted
        g.CompletedAt = &now
 
        if ok, _ := s.repo.TryUnlockAchievement(ctx, id.UserID, "goal_complete", &goalID); ok {
            newAch = append(newAch, Achievement{Code: "goal_complete", Title: g.Title, Description: "Goal completed", Icon: "emoji_events", GoalID: &goalID, UnlockedAt: &now, Unlocked: true})
        }
        completed, _ := s.repo.CountCompletedGoals(ctx, id.UserID)
        if completed == 1 {
            if ok, _ := s.repo.TryUnlockAchievement(ctx, id.UserID, "first_goal", nil); ok {
                newAch = append(newAch, Achievement{Code: "first_goal", Title: "First steps", Description: "Completed your first goal", Icon: "military_tech", UnlockedAt: &now, Unlocked: true})
            }
        }
        if g.TrackingMode == TrackingStreak && g.TargetDays >= 7 {
            if ok, _ := s.repo.TryUnlockAchievement(ctx, id.UserID, "streak_7", nil); ok {
                newAch = append(newAch, Achievement{Code: "streak_7", Title: "Week warrior", Description: "Completed a 7-day streak goal", Icon: "local_fire_department", UnlockedAt: &now, Unlocked: true})
            }
        }
        g, err = s.repo.GetGoal(ctx, id.UserID, goalID)
        if err != nil {
            return nil, err
        }
        g, err = s.enrichGoal(ctx, g)
        if err != nil {
            return nil, err
        }
    }
    return &CheckInResponse{Goal: *g, NewAchievements: newAch}, nil
}
 
// RemoveCheckIn removes a check-in for a day.
func (s *Service) RemoveCheckIn(ctx context.Context, id auth.Identity, goalID string, day time.Time) (*Goal, error) {
    if _, err := s.repo.GetGoal(ctx, id.UserID, goalID); err != nil {
        return nil, err
    }
    day = time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, time.UTC)
    if err := s.repo.DeleteCheckIn(ctx, goalID, day); err != nil {
        return nil, err
    }
    g, err := s.repo.GetGoal(ctx, id.UserID, goalID)
    if err != nil {
        return nil, err
    }
    return s.enrichGoal(ctx, g)
}
 
// ListAchievements returns achievement catalog with unlock state.
func (s *Service) ListAchievements(ctx context.Context, id auth.Identity) ([]Achievement, error) {
    return s.repo.ListAchievements(ctx, id.UserID)
}
 
// Holidays proxies public holidays for a year/country.
func (s *Service) Holidays(ctx context.Context, year int, country string) ([]Holiday, error) {
    if year < 1900 || year > 2100 {
        return nil, invalid("invalid year")
    }
    return fetchPublicHolidays(ctx, year, country)
}
 
const maxScheduleRange = 90 * 24 * time.Hour
 
// Schedule builds the aggregated calendar feed.
func (s *Service) Schedule(ctx context.Context, id auth.Identity, from, to time.Time) ([]ScheduleItem, error) {
    if to.Before(from) {
        return nil, invalid("invalid time range")
    }
    if to.Sub(from) > maxScheduleRange {
        return nil, invalid("range must be at most 90 days")
    }
 
    prefs, err := s.GetOrCreatePreferences(ctx, id)
    if err != nil {
        return nil, err
    }
 
    var items []ScheduleItem
 
    occurrences, err := s.ListExpandedEvents(ctx, id, from, to)
    if err != nil {
        return nil, err
    }
    for _, e := range occurrences {
        color := e.Color
        if color == "" {
            if c, ok := prefs.CategoryColors[string(e.Category)]; ok {
                color = c
            }
        }
        st, en := e.StartAt, e.EndAt
        items = append(items, ScheduleItem{
            Kind:        "personal_event",
            ID:          e.ID,
            SeriesID:    e.SeriesID,
            Title:       e.Title,
            Description: e.Description,
            StartAt:     &st,
            EndAt:       &en,
            Category:    e.Category,
            Color:       color,
            AllDay:      e.AllDay,
        })
    }
 
    tasks, err := s.repo.ListTasksDueInRange(ctx, id.UserID, from, to)
    if err != nil {
        return nil, err
    }
    for _, t := range tasks {
        d := t.DueDate
        c := t.Completed
        items = append(items, ScheduleItem{
            Kind:        "task",
            ID:          t.ID,
            Title:       t.Title,
            Description: t.Description,
            DueDate:     &d,
            Completed:   &c,
        })
    }
 
    if s.bookings != nil {
        bookings, err := s.bookings.ListOverlappingForUser(ctx, id.UserID, from, to)
        if err != nil {
            return nil, err
        }
        for _, b := range bookings {
            st, en := b.StartDate, b.EndDate
            items = append(items, ScheduleItem{
                Kind:      "booking",
                BookingID: b.ID,
                Title:     b.Purpose,
                StartAt:   &st,
                EndAt:     &en,
                Status:    string(b.Status),
            })
        }
    }
 
    if s.events != nil && id.ChurchID != "" {
        chEvents, err := s.events.ListByChurchInRange(ctx, id.ChurchID, from, to)
        if err != nil {
            return nil, err
        }
        for _, ev := range chEvents {
            st := ev.StartDate
            items = append(items, ScheduleItem{
                Kind:     "church_event",
                EventID:  ev.ID,
                ChurchID: ev.ChurchID,
                Title:    ev.Title,
                StartAt:  &st,
            })
        }
    }
 
    holidays, err := holidaysInRange(ctx, prefs.HolidayCountry, from, to)
    if err == nil {
        for _, h := range holidays {
            d, _ := time.Parse("2006-01-02", h.Date)
            name := h.Name
            items = append(items, ScheduleItem{Kind: "holiday", Name: name, Date: &d, Title: name})
        }
    }
 
    goals, err := s.repo.ListActiveGoals(ctx, id.UserID)
    if err != nil {
        return nil, err
    }
    for d := from; !d.After(to); d = d.AddDate(0, 0, 1) {
        day := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, time.UTC)
        for _, g := range goals {
            checked, err := s.repo.HasCheckIn(ctx, g.ID, day)
            if err != nil {
                return nil, err
            }
            v := checked
            items = append(items, ScheduleItem{
                Kind:           "goal_checkin_due",
                GoalID:         g.ID,
                Title:          g.Title,
                Date:           &day,
                CheckedInToday: &v,
            })
        }
    }
 
    return items, nil
}
 