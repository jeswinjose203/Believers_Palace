package personalcalendar

import (
    "context"
    "testing"
    "time"
)

type fakeChurchResolver struct {
    churchID string
    ok       bool
    err      error
}

func (f *fakeChurchResolver) ChurchIDOf(_ context.Context, _ string) (string, bool, error) {
    return f.churchID, f.ok, f.err
}

func TestScheduleChurchIDFromResolver(t *testing.T) {
    t.Run("uses profile church", func(t *testing.T) {
        svc := &Service{userChurch: &fakeChurchResolver{churchID: "church-abc", ok: true}}
        if got := svc.scheduleChurchID(context.Background(), "user-1"); got != "church-abc" {
            t.Fatalf("got %q, want church-abc", got)
        }
    })
    t.Run("empty when no church", func(t *testing.T) {
        svc := &Service{userChurch: &fakeChurchResolver{ok: true, churchID: ""}}
        if got := svc.scheduleChurchID(context.Background(), "user-1"); got != "" {
            t.Fatalf("got %q, want empty", got)
        }
    })
    t.Run("empty when resolver nil", func(t *testing.T) {
        svc := &Service{}
        if got := svc.scheduleChurchID(context.Background(), "user-1"); got != "" {
            t.Fatalf("got %q, want empty", got)
        }
    })
}
 
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
 
func TestGoalCheckInWindow(t *testing.T) {
    start := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
    g := Goal{
        Status:     GoalActive,
        TargetDays: 7,
        StartDate:  &start,
        CreatedAt:  start,
    }
    gStart, gEnd, ok := goalCheckInWindow(g)
    if !ok {
        t.Fatal("expected active window")
    }
    wantEnd := time.Date(2026, 3, 7, 0, 0, 0, 0, time.UTC)
    if !gStart.Equal(start) || !gEnd.Equal(wantEnd) {
        t.Fatalf("window %v..%v want %v..%v", gStart, gEnd, start, wantEnd)
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
 