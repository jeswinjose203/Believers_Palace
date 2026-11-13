package personalcalendar
 
import "time"
 
const maxRecurrenceHorizon = 24 * 30 * 24 * time.Hour // ~24 months
 
// expandEventOccurrences returns event instances overlapping [from, to].
func expandEventOccurrences(e Event, from, to time.Time) []Event {
    if e.Recurrence == RecurrenceNone {
        if e.EndAt.Before(from) || e.StartAt.After(to) {
            return nil
        }
        out := e
        out.SeriesID = e.ID
        return []Event{out}
    }
 
    interval := e.RecurrenceInterval
    if interval < 1 {
        interval = 1
    }
 
    until := to
    if e.RecurrenceUntil != nil && e.RecurrenceUntil.Before(until) {
        until = *e.RecurrenceUntil
    }
    maxEnd := e.StartAt.Add(maxRecurrenceHorizon)
    if until.After(maxEnd) {
        until = maxEnd
    }
 
    duration := e.EndAt.Sub(e.StartAt)
    var out []Event
    curStart := e.StartAt
 
    for !curStart.After(until) && !curStart.After(to.Add(duration)) {
        curEnd := curStart.Add(duration)
        if !curEnd.Before(from) && !curStart.After(to) {
            occ := e
            occ.SeriesID = e.ID
            occ.StartAt = curStart
            occ.EndAt = curEnd
            os, oe := curStart, curEnd
            occ.OccurrenceStart = &os
            occ.OccurrenceEnd = &oe
            out = append(out, occ)
        }
        switch e.Recurrence {
        case RecurrenceDaily:
            curStart = curStart.AddDate(0, 0, interval)
        case RecurrenceWeekly:
            curStart = curStart.AddDate(0, 0, 7*interval)
        case RecurrenceMonthly:
            curStart = curStart.AddDate(0, interval, 0)
        default:
            return out
        }
        if e.RecurrenceUntil != nil && curStart.After(*e.RecurrenceUntil) {
            break
        }
    }
    return out
}
 
// currentStreakEndingOn computes consecutive check-in days ending on end (inclusive).
func currentStreakEndingOn(dates []time.Time, end time.Time) int {
    if len(dates) == 0 {
        return 0
    }
    daySet := make(map[string]struct{}, len(dates))
    for _, d := range dates {
        daySet[d.Format("2006-01-02")] = struct{}{}
    }
    streak := 0
    cur := end.UTC()
    for {
        key := cur.Format("2006-01-02")
        if _, ok := daySet[key]; !ok {
            break
        }
        streak++
        cur = cur.AddDate(0, 0, -1)
    }
    return streak
}
 
// progressForGoal returns progress count toward target based on tracking mode.
func progressForGoal(mode TrackingMode, checkInCount int, streak int) int {
    if mode == TrackingStreak {
        return streak
    }
    return checkInCount
}
 