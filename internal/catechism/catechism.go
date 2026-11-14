// Package catechism implements church faith-formation classes, enrollments,
// and lesson sessions.
package catechism

import (
	"encoding/json"
	"time"
)

// ClassLevel is the formation program type.
type ClassLevel string

const (
	LevelFirstCommunion ClassLevel = "first_communion"
	LevelConfirmation   ClassLevel = "confirmation"
	LevelBaptismPrep    ClassLevel = "baptism_prep"
	LevelSundaySchool   ClassLevel = "sunday_school"
	LevelAdult          ClassLevel = "adult"
	LevelOther          ClassLevel = "other"
)

// ClassStatus is the publication/lifecycle state of a class.
type ClassStatus string

const (
	StatusDraft     ClassStatus = "draft"
	StatusOpen      ClassStatus = "open"
	StatusClosed    ClassStatus = "closed"
	StatusCompleted ClassStatus = "completed"
)

// EnrollmentStatus tracks an enrollment through approval and completion.
type EnrollmentStatus string

const (
	EnrollPending   EnrollmentStatus = "pending"
	EnrollApproved  EnrollmentStatus = "approved"
	EnrollRejected  EnrollmentStatus = "rejected"
	EnrollWithdrawn EnrollmentStatus = "withdrawn"
	EnrollCompleted EnrollmentStatus = "completed"
)

// ScheduleSlot is one recurring meeting time entry stored in JSONB schedule.
type ScheduleSlot struct {
	Day  string `json:"day"`
	Time string `json:"time"`
}

// Class is a catechism class offered by a church.
type Class struct {
	ID            string         `json:"id"`
	ChurchID      string         `json:"churchId"`
	Name          string         `json:"name"`
	Description   string         `json:"description,omitempty"`
	Level         ClassLevel     `json:"level"`
	MinAge        *int           `json:"minAge,omitempty"`
	MaxAge        *int           `json:"maxAge,omitempty"`
	TeacherUserID *string        `json:"teacherUserId,omitempty"`
	TeacherName   string         `json:"teacherName,omitempty"`
	Schedule      []ScheduleSlot `json:"schedule"`
	Location      string         `json:"location,omitempty"`
	StartDate     time.Time      `json:"startDate"`
	EndDate       time.Time      `json:"endDate"`
	Capacity      int            `json:"capacity"`
	Status        ClassStatus    `json:"status"`
	Image         string         `json:"image,omitempty"`
	CreatedAt     time.Time      `json:"createdAt"`
	UpdatedAt     time.Time      `json:"updatedAt"`
	// List/get extras (caller-specific where noted).
	EnrolledCount  int  `json:"enrolledCount"`
	AvailableSeats int  `json:"availableSeats"`
	Enrolled       bool `json:"enrolled"`
}

// ClassRequest is the payload for creating or updating a class.
type ClassRequest struct {
	Name          string         `json:"name"`
	Description   string         `json:"description"`
	Level         ClassLevel     `json:"level"`
	MinAge        *int           `json:"minAge"`
	MaxAge        *int           `json:"maxAge"`
	TeacherUserID *string        `json:"teacherUserId"`
	TeacherName   string         `json:"teacherName"`
	Schedule      []ScheduleSlot `json:"schedule"`
	Location      string         `json:"location"`
	StartDate     *time.Time     `json:"startDate"`
	EndDate       *time.Time     `json:"endDate"`
	Capacity      *int           `json:"capacity"`
	Status        ClassStatus    `json:"status"`
	Image         string         `json:"image"`
}

// Enrollment is a student enrollment in a class.
type Enrollment struct {
	ID           string           `json:"id"`
	ClassID      string           `json:"classId"`
	GuardianID   string           `json:"guardianId"`
	StudentName  string           `json:"studentName"`
	DateOfBirth  time.Time        `json:"dateOfBirth"`
	Notes        string           `json:"notes,omitempty"`
	Status       EnrollmentStatus `json:"status"`
	CreatedAt    time.Time        `json:"createdAt"`
	UpdatedAt    time.Time        `json:"updatedAt"`
	ClassName    string           `json:"className,omitempty"`
	ClassLevel   ClassLevel       `json:"classLevel,omitempty"`
	ClassStatus  ClassStatus      `json:"classStatus,omitempty"`
}

// EnrollmentRequest is the payload for creating an enrollment.
type EnrollmentRequest struct {
	StudentName string     `json:"studentName"`
	DateOfBirth *time.Time `json:"dateOfBirth"`
	Notes       string     `json:"notes"`
}

// EnrollmentStatusRequest is the payload for staff status updates.
type EnrollmentStatusRequest struct {
	Status EnrollmentStatus `json:"status"`
}

// Session is a dated lesson for a class.
type Session struct {
	ID          string    `json:"id"`
	ClassID     string    `json:"classId"`
	Title       string    `json:"title"`
	Topic       string    `json:"topic,omitempty"`
	SessionDate time.Time `json:"sessionDate"`
	StartTime   string    `json:"startTime"`
	EndTime     string    `json:"endTime"`
	Notes       string    `json:"notes,omitempty"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

// SessionRequest is the payload for creating or updating a session.
type SessionRequest struct {
	Title       string     `json:"title"`
	Topic       string     `json:"topic"`
	SessionDate *time.Time `json:"sessionDate"`
	StartTime   string     `json:"startTime"`
	EndTime     string     `json:"endTime"`
	Notes       string     `json:"notes"`
}

func scheduleToJSON(slots []ScheduleSlot) ([]byte, error) {
	if slots == nil {
		slots = []ScheduleSlot{}
	}
	return json.Marshal(slots)
}

func scheduleFromJSON(data []byte) ([]ScheduleSlot, error) {
	if len(data) == 0 {
		return []ScheduleSlot{}, nil
	}
	var slots []ScheduleSlot
	if err := json.Unmarshal(data, &slots); err != nil {
		return nil, err
	}
	return slots, nil
}