package personalcalendar

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// EventListQuery filters and ordering for GET /users/me/calendar/events.
type EventListQuery struct {
	Search   string
	Category string
	From     *time.Time
	To       *time.Time
	OrderAsc bool
}

// ParseEventListQuery reads list query parameters from the request.
func ParseEventListQuery(r *http.Request) (EventListQuery, error) {
	q := EventListQuery{
		Search:   strings.TrimSpace(r.URL.Query().Get("search")),
		Category: strings.TrimSpace(r.URL.Query().Get("category")),
	}
	order := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("order")))
	switch order {
	case "", "desc":
		q.OrderAsc = false
	case "asc":
		q.OrderAsc = true
	default:
		return EventListQuery{}, errors.New("order must be asc or desc")
	}

	now := time.Now().UTC()
	if daysS := strings.TrimSpace(r.URL.Query().Get("upcomingDays")); daysS != "" {
		days, err := strconv.Atoi(daysS)
		if err != nil || days < 1 || days > 366 {
			return EventListQuery{}, errors.New("invalid upcomingDays")
		}
		from := now
		to := now.AddDate(0, 0, days)
		q.From = &from
		q.To = &to
		return q, nil
	}

	fromDay := strings.TrimSpace(r.URL.Query().Get("fromDate"))
	toDay := strings.TrimSpace(r.URL.Query().Get("toDate"))
	if fromDay != "" || toDay != "" {
		if fromDay == "" || toDay == "" {
			return EventListQuery{}, errors.New("fromDate and toDate must both be set")
		}
		from, err := time.Parse("2006-01-02", fromDay)
		if err != nil {
			return EventListQuery{}, errors.New("invalid fromDate")
		}
		to, err := time.Parse("2006-01-02", toDay)
		if err != nil {
			return EventListQuery{}, errors.New("invalid toDate")
		}
		if to.Before(from) {
			return EventListQuery{}, errors.New("toDate must be on or after fromDate")
		}
		// Inclusive end of calendar day UTC for filtering start_at.
		end := to.Add(24*time.Hour - time.Nanosecond)
		q.From = &from
		q.To = &end
	}
	return q, nil
}