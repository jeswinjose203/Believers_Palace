package personalcalendar

import "time"

const defaultTimezone = "Asia/Kolkata"

func loadLocation(name string) *time.Location {
	if name == "" {
		name = defaultTimezone
	}
	loc, err := time.LoadLocation(name)
	if err != nil {
		loc, _ = time.LoadLocation(defaultTimezone)
	}
	return loc
}

// calendarDateUTC returns a UTC midnight timestamp whose Y-M-D match the
// calendar date of t in loc (for DATE columns and goal check-ins).
func calendarDateUTC(t time.Time, loc *time.Location) time.Time {
	l := t.In(loc)
	return time.Date(l.Year(), l.Month(), l.Day(), 0, 0, 0, 0, time.UTC)
}

func dayRangeInLoc(fromDay, toDay time.Time, loc *time.Location) (start, end time.Time) {
	start = time.Date(fromDay.Year(), fromDay.Month(), fromDay.Day(), 0, 0, 0, 0, loc)
	end = time.Date(toDay.Year(), toDay.Month(), toDay.Day(), 23, 59, 59, 999999999, loc)
	return start, end
}