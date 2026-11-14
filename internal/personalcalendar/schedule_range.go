package personalcalendar

import (
	"errors"
	"net/http"
	"time"

	"believers_palace/internal/auth"
)

// ParseScheduleRange resolves an inclusive calendar range for the schedule feed.
// Prefer fromDate/toDate (YYYY-MM-DD) in the user's timezone; from/to RFC3339 are
// still accepted for older clients.
func (s *Service) ParseScheduleRange(r *http.Request) (time.Time, time.Time, error) {
	id := auth.MustFromContext(r.Context())
	prefs, err := s.GetOrCreatePreferences(r.Context(), id)
	if err != nil {
		return time.Time{}, time.Time{}, err
	}
	loc := loadLocation(prefs.Timezone)

	if fromDayS := r.URL.Query().Get("fromDate"); fromDayS != "" {
		toDayS := r.URL.Query().Get("toDate")
		if toDayS == "" {
			return time.Time{}, time.Time{}, errors.New("toDate is required with fromDate")
		}
		fromDay, err := time.ParseInLocation("2006-01-02", fromDayS, loc)
		if err != nil {
			return time.Time{}, time.Time{}, errors.New("invalid fromDate")
		}
		toDay, err := time.ParseInLocation("2006-01-02", toDayS, loc)
		if err != nil {
			return time.Time{}, time.Time{}, errors.New("invalid toDate")
		}
		if toDay.Before(fromDay) {
			return time.Time{}, time.Time{}, errors.New("invalid date range")
		}
		return dayRangeInLoc(fromDay, toDay, loc)
	}

	fromS := r.URL.Query().Get("from")
	toS := r.URL.Query().Get("to")
	if fromS == "" || toS == "" {
		return time.Time{}, time.Time{}, errors.New("fromDate and toDate are required (YYYY-MM-DD)")
	}
	from, err := time.Parse(time.RFC3339, fromS)
	if err != nil {
		return time.Time{}, time.Time{}, errors.New("invalid from")
	}
	to, err := time.Parse(time.RFC3339, toS)
	if err != nil {
		return time.Time{}, time.Time{}, errors.New("invalid to")
	}
	fromDay := calendarDateUTC(from, loc)
	toDay := calendarDateUTC(to, loc)
	if toDay.Before(fromDay) {
		return time.Time{}, time.Time{}, errors.New("invalid time range")
	}
	return dayRangeInLoc(
		time.Date(fromDay.Year(), fromDay.Month(), fromDay.Day(), 0, 0, 0, 0, loc),
		time.Date(toDay.Year(), toDay.Month(), toDay.Day(), 0, 0, 0, 0, loc),
		loc,
	)
}