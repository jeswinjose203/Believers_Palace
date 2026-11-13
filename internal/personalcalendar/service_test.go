package personalcalendar
 
import (
    "testing"
    "time"
)
 
func TestExpandDailyRecurrence(t *testing.T) {
    start := time.Date(2026, 1, 1, 9, 0, 0, 0, time.UTC)
    end := start.Add(time.Hour)
    e := Event{
        ID:                 "e1",
        StartAt:            start,
        EndAt:              end,
        Recurrence:         RecurrenceDaily,
        RecurrenceInterval: 1,
    }
    from := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
    to := time.Date(2026, 1, 5, 23, 59, 59, 0, time.UTC)
    occ := expandEventOccurrences(e, from, to)
    if len(occ) != 5 {
        t.Fatalf("got %d occurrences, want 5", len(occ))
    }
}
 
func TestCurrentStreak(t *testing.T) {
    dates := []time.Time{
        time.Date(2026, 1, 10, 0, 0, 0, 0, time.UTC),
        time.Date(2026, 1, 11, 0, 0, 0, 0, time.UTC),
        time.Date(2026, 1, 12, 0, 0, 0, 0, time.UTC),
    }
    end := time.Date(2026, 1, 12, 0, 0, 0, 0, time.UTC)
    if got := currentStreakEndingOn(dates, end); got != 3 {
        t.Fatalf("streak = %d, want 3", got)
    }
    end = time.Date(2026, 1, 13, 0, 0, 0, 0, time.UTC)
    if got := currentStreakEndingOn(dates, end); got != 0 {
        t.Fatalf("streak = %d, want 0", got)
    }
}
 
func TestProgressForGoal(t *testing.T) {
    if progressForGoal(TrackingTotal, 5, 2) != 5 {
        t.Fatal("total mode should use check-in count")
    }
    if progressForGoal(TrackingStreak, 5, 2) != 2 {
        t.Fatal("streak mode should use streak")
    }
}
 