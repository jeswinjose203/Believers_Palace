package catechism

import (
	"strings"
	"time"
)

// ValidClassLevel reports whether l is a recognized class level.
func ValidClassLevel(l ClassLevel) bool {
	switch l {
	case LevelFirstCommunion, LevelConfirmation, LevelBaptismPrep,
		LevelSundaySchool, LevelAdult, LevelOther:
		return true
	default:
		return false
	}
}

// ValidClassStatus reports whether s is a recognized class status.
func ValidClassStatus(s ClassStatus) bool {
	switch s {
	case StatusDraft, StatusOpen, StatusClosed, StatusCompleted:
		return true
	default:
		return false
	}
}

// ValidEnrollmentStatus reports whether s is a recognized enrollment status.
func ValidEnrollmentStatus(s EnrollmentStatus) bool {
	switch s {
	case EnrollPending, EnrollApproved, EnrollRejected, EnrollWithdrawn, EnrollCompleted:
		return true
	default:
		return false
	}
}

func validateClassRequest(in ClassRequest) error {
	if strings.TrimSpace(in.Name) == "" {
		return invalid("name is required")
	}
	if in.Level == "" || !ValidClassLevel(in.Level) {
		return invalid("invalid level")
	}
	if in.StartDate == nil {
		return invalid("startDate is required")
	}
	if in.EndDate == nil {
		return invalid("endDate is required")
	}
	if in.EndDate.Before(*in.StartDate) {
		return invalid("endDate cannot be before startDate")
	}
	if in.Capacity == nil || *in.Capacity < 1 {
		return invalid("capacity must be at least 1")
	}
	if in.Status != "" && !ValidClassStatus(in.Status) {
		return invalid("invalid status")
	}
	if in.MinAge != nil && *in.MinAge < 0 {
		return invalid("minAge cannot be negative")
	}
	if in.MaxAge != nil && *in.MaxAge < 0 {
		return invalid("maxAge cannot be negative")
	}
	if in.MinAge != nil && in.MaxAge != nil && *in.MaxAge < *in.MinAge {
		return invalid("maxAge cannot be less than minAge")
	}
	return nil
}

func validateEnrollmentRequest(in EnrollmentRequest, cls *Class) error {
	if strings.TrimSpace(in.StudentName) == "" {
		return invalid("studentName is required")
	}
	if in.DateOfBirth == nil {
		return invalid("dateOfBirth is required")
	}
	dob := in.DateOfBirth.Truncate(24 * time.Hour)
	today := time.Now().Truncate(24 * time.Hour)
	if dob.After(today) {
		return invalid("dateOfBirth cannot be in the future")
	}
	age := ageAt(dob, today)
	if cls.MinAge != nil && age < *cls.MinAge {
		return invalid("student age is below the class minimum")
	}
	if cls.MaxAge != nil && age > *cls.MaxAge {
		return invalid("student age is above the class maximum")
	}
	return nil
}

func validateSessionRequest(in SessionRequest) error {
	if strings.TrimSpace(in.Title) == "" {
		return invalid("title is required")
	}
	if in.SessionDate == nil {
		return invalid("sessionDate is required")
	}
	if strings.TrimSpace(in.StartTime) == "" {
		return invalid("startTime is required")
	}
	if strings.TrimSpace(in.EndTime) == "" {
		return invalid("endTime is required")
	}
	if in.StartTime >= in.EndTime {
		return invalid("endTime must be after startTime")
	}
	return nil
}

func ageAt(dob, on time.Time) int {
	years := on.Year() - dob.Year()
	birthday := time.Date(on.Year(), dob.Month(), dob.Day(), 0, 0, 0, 0, time.UTC)
	if on.Before(birthday) {
		years--
	}
	return years
}