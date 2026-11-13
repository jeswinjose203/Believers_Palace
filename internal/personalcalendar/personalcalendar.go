// Package personalcalendar implements per-user calendar events, tasks, goals,
// preferences, and an aggregated schedule feed.
package personalcalendar
 
import "time"
 
// Category is an event category.
type Category string
 
const (
    CategoryPersonal Category = "personal"
    CategoryWork     Category = "work"
    CategoryFamily   Category = "family"
    CategoryMeetings Category = "meetings"
)
 
func ValidCategory(c Category) bool {
    switch c {
    case CategoryPersonal, CategoryWork, CategoryFamily, CategoryMeetings:
        return true
    default:
        return false
    }
}
 
// Recurrence describes how a personal event repeats.
type Recurrence string
 
const (
    RecurrenceNone    Recurrence = "none"
    RecurrenceDaily   Recurrence = "daily"
    RecurrenceWeekly  Recurrence = "weekly"
    RecurrenceMonthly Recurrence = "monthly"
)
 
func ValidRecurrence(r Recurrence) bool {
    switch r {
    case RecurrenceNone, RecurrenceDaily, RecurrenceWeekly, RecurrenceMonthly:
        return true
    default:
        return false
    }
}
 
// Preferences holds per-user calendar UI settings.
type Preferences struct {
    Theme          string            `json:"theme"`
    DateFormat     string            `json:"dateFormat"`
    WeekStartsOn   string            `json:"weekStartsOn"`
    HolidayCountry string            `json:"holidayCountry"`
    CategoryColors map[string]string `json:"categoryColors"`
}
 
// PreferencesPatch is a partial update for preferences.
type PreferencesPatch struct {
    Theme          *string            `json:"theme"`
    DateFormat     *string            `json:"dateFormat"`
    WeekStartsOn   *string            `json:"weekStartsOn"`
    HolidayCountry *string            `json:"holidayCountry"`
    CategoryColors *map[string]string `json:"categoryColors"`
}
 
// Event is a user-owned calendar event (possibly recurring).
type Event struct {
    ID                  string     `json:"id"`
    Title               string     `json:"title"`
    Description         string     `json:"description,omitempty"`
    Category            Category   `json:"category"`
    Color               string     `json:"color,omitempty"`
    StartAt             time.Time  `json:"startAt"`
    EndAt               time.Time  `json:"endAt"`
    AllDay              bool       `json:"allDay"`
    Recurrence          Recurrence `json:"recurrence"`
    RecurrenceInterval  int        `json:"recurrenceInterval"`
    RecurrenceUntil     *time.Time `json:"recurrenceUntil,omitempty"`
    ReminderMinutes     []int      `json:"reminderMinutes"`
    CreatedAt           time.Time  `json:"createdAt"`
    UpdatedAt           time.Time  `json:"updatedAt"`
    OccurrenceStart     *time.Time `json:"occurrenceStart,omitempty"`
    OccurrenceEnd       *time.Time `json:"occurrenceEnd,omitempty"`
    SeriesID            string     `json:"seriesId,omitempty"`
}
 
// EventRequest is create/update payload for events.
type EventRequest struct {
    Title              string      `json:"title"`
    Description        string      `json:"description"`
    Category           Category    `json:"category"`
    Color              string      `json:"color"`
    StartAt            *time.Time  `json:"startAt"`
    EndAt              *time.Time  `json:"endAt"`
    AllDay             *bool       `json:"allDay"`
    Recurrence         *Recurrence `json:"recurrence"`
    RecurrenceInterval *int        `json:"recurrenceInterval"`
    RecurrenceUntil    *time.Time  `json:"recurrenceUntil"`
    ReminderMinutes    []int       `json:"reminderMinutes"`
}
 
// Task is a due-date todo item.
type Task struct {
    ID          string    `json:"id"`
    Title       string    `json:"title"`
    Description string    `json:"description,omitempty"`
    DueDate     time.Time `json:"dueDate"`
    Completed   bool      `json:"completed"`
    CreatedAt   time.Time `json:"createdAt"`
    UpdatedAt   time.Time `json:"updatedAt"`
}
 
// TaskRequest is create payload for tasks.
type TaskRequest struct {
    Title       string     `json:"title"`
    Description string     `json:"description"`
    DueDate     *time.Time `json:"dueDate"`
}
 
// TaskPatch updates a task.
type TaskPatch struct {
    Title       *string `json:"title"`
    Description *string `json:"description"`
    DueDate     *time.Time `json:"dueDate"`
    Completed   *bool   `json:"completed"`
}
 
// TrackingMode is how goal progress is measured.
type TrackingMode string
 
const (
    TrackingTotal  TrackingMode = "total"
    TrackingStreak TrackingMode = "streak"
)
 
// GoalStatus is the lifecycle of a goal.
type GoalStatus string
 
const (
    GoalActive    GoalStatus = "active"
    GoalCompleted GoalStatus = "completed"
    GoalArchived  GoalStatus = "archived"
)
 
// Goal is a habit/goal with daily check-ins.
type Goal struct {
    ID            string       `json:"id"`
    Title         string       `json:"title"`
    Description   string       `json:"description,omitempty"`
    TargetDays    int          `json:"targetDays"`
    TrackingMode  TrackingMode `json:"trackingMode"`
    StartDate     *time.Time   `json:"startDate,omitempty"`
    EndDate       *time.Time   `json:"endDate,omitempty"`
    Status        GoalStatus   `json:"status"`
    CompletedAt   *time.Time   `json:"completedAt,omitempty"`
    CheckInCount  int          `json:"checkInCount"`
    CurrentStreak int          `json:"currentStreak"`
    CreatedAt     time.Time    `json:"createdAt"`
    UpdatedAt     time.Time    `json:"updatedAt"`
}
 
// GoalRequest creates or updates a goal.
type GoalRequest struct {
    Title        string        `json:"title"`
    Description  string        `json:"description"`
    TargetDays   *int          `json:"targetDays"`
    TrackingMode *TrackingMode `json:"trackingMode"`
    StartDate    *time.Time    `json:"startDate"`
    EndDate      *time.Time    `json:"endDate"`
    Status       *GoalStatus   `json:"status"`
}
 
// CheckInRequest is an optional body when checking in.
type CheckInRequest struct {
    Note string `json:"note"`
}
 
// CheckInResponse returns progress after check-in.
type CheckInResponse struct {
    Goal            Goal          `json:"goal"`
    NewAchievements []Achievement `json:"newAchievements,omitempty"`
}
 
// AchievementDefinition is a catalog badge.
type AchievementDefinition struct {
    Code        string `json:"code"`
    Title       string `json:"title"`
    Description string `json:"description"`
    Icon        string `json:"icon"`
}
 
// Achievement is an unlocked badge for a user.
type Achievement struct {
    Code        string     `json:"code"`
    Title       string     `json:"title"`
    Description string     `json:"description"`
    Icon        string     `json:"icon"`
    GoalID      *string    `json:"goalId,omitempty"`
    UnlockedAt  *time.Time `json:"unlockedAt,omitempty"`
    Unlocked    bool       `json:"unlocked"`
}
 
// ScheduleItem is a discriminated union item for the unified feed.
type ScheduleItem struct {
    Kind string `json:"kind"`
 
    // personal_event
    ID          string     `json:"id,omitempty"`
    SeriesID    string     `json:"seriesId,omitempty"`
    Title       string     `json:"title,omitempty"`
    Description string     `json:"description,omitempty"`
    StartAt     *time.Time `json:"startAt,omitempty"`
    EndAt       *time.Time `json:"endAt,omitempty"`
    Category    Category   `json:"category,omitempty"`
    Color       string     `json:"color,omitempty"`
    AllDay      bool       `json:"allDay,omitempty"`
 
    // task
    DueDate   *time.Time `json:"dueDate,omitempty"`
    Completed *bool      `json:"completed,omitempty"`
 
    // booking
    BookingID string `json:"bookingId,omitempty"`
    Status    string `json:"status,omitempty"`
 
    // church_event
    EventID  string `json:"eventId,omitempty"`
    ChurchID string `json:"churchId,omitempty"`
 
    // holiday
    Name string     `json:"name,omitempty"`
    Date *time.Time `json:"date,omitempty"`
 
    // goal_checkin_due
    GoalID         string `json:"goalId,omitempty"`
    CheckedInToday *bool  `json:"checkedInToday,omitempty"`
}
 
// Holiday is a public holiday entry.
type Holiday struct {
    Date string `json:"date"`
    Name string `json:"name"`
}
 
// DefaultCategoryColors returns hex colors for built-in categories.
func DefaultCategoryColors() map[string]string {
    return map[string]string{
        string(CategoryPersonal): "#5B2A91",
        string(CategoryWork):     "#1565C0",
        string(CategoryFamily):   "#2E7D32",
        string(CategoryMeetings): "#C62828",
    }
}
 