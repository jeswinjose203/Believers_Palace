package personalcalendar
 
import "time"
 
// goalCheckInWindow returns inclusive calendar dates when check-ins are expected.
func goalCheckInWindow(g Goal) (start, end time.Time, active bool) {
    if g.Status != GoalActive {
        return time.Time{}, time.Time{}, false
    }
    start = time.Date(g.CreatedAt.Year(), g.CreatedAt.Month(), g.CreatedAt.Day(), 0, 0, 0, 0, time.UTC)
    if g.StartDate != nil {
        start = time.Date(g.StartDate.Year(), g.StartDate.Month(), g.StartDate.Day(), 0, 0, 0, 0, time.UTC)
    }
    if g.TargetDays < 1 {
        return time.Time{}, time.Time{}, false
    }
    end = start.AddDate(0, 0, g.TargetDays-1)
    if g.EndDate != nil {
        cap := time.Date(g.EndDate.Year(), g.EndDate.Month(), g.EndDate.Day(), 0, 0, 0, 0, time.UTC)
        if cap.Before(end) {
            end = cap
        }
    }
    return start, end, true
}
 
func dayUTC(t time.Time) time.Time {
    return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}
 