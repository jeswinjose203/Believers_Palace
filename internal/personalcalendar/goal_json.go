package personalcalendar

import (
	"errors"
	"strings"
	"time"
)

func parseFlexibleDate(s string) (time.Time, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return time.Time{}, errors.New("empty date")
	}
	if t, err := time.Parse("2006-01-02", s); err == nil {
		return t, nil
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t, nil
	}
	return time.Time{}, errors.New("invalid date")
}

// flexibleGoalRequest accepts YYYY-MM-DD or RFC3339 for date fields.
type flexibleGoalRequest struct {
	Title        string        `json:"title"`
	Description  string        `json:"description"`
	TargetDays   *int          `json:"targetDays"`
	TrackingMode *TrackingMode `json:"trackingMode"`
	StartDate    *string       `json:"startDate"`
	EndDate      *string       `json:"endDate"`
	Status       *GoalStatus   `json:"status"`
}

func (f flexibleGoalRequest) toGoalRequest() (GoalRequest, error) {
	in := GoalRequest{
		Title:        f.Title,
		Description:  f.Description,
		TargetDays:   f.TargetDays,
		TrackingMode: f.TrackingMode,
		Status:       f.Status,
	}
	if f.StartDate != nil && strings.TrimSpace(*f.StartDate) != "" {
		t, err := parseFlexibleDate(*f.StartDate)
		if err != nil {
			return GoalRequest{}, err
		}
		in.StartDate = &t
	}
	if f.EndDate != nil && strings.TrimSpace(*f.EndDate) != "" {
		t, err := parseFlexibleDate(*f.EndDate)
		if err != nil {
			return GoalRequest{}, err
		}
		in.EndDate = &t
	}
	return in, nil
}