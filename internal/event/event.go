// Package event implements church events and event registrations. Events
// support list, create, get, update, and delete; authenticated users may
// register to attend events.
package event

import "time"

// Event is a church event record.
type Event struct {
	ID                   string     `json:"id"`
	ChurchID             string     `json:"churchId"`
	Title                string     `json:"title"`
	Description          string     `json:"description,omitempty"`
	Location             string     `json:"location,omitempty"`
	StartDate            time.Time  `json:"startDate"`
	EndDate              *time.Time `json:"endDate,omitempty"`
	Image                string     `json:"image,omitempty"`
	Capacity             *int       `json:"capacity,omitempty"`
	RegistrationRequired bool       `json:"registrationRequired"`
	CreatedAt            time.Time  `json:"createdAt"`
	// Registered reports whether the calling user is registered for the event.
	// It is only populated on list responses.
	Registered *bool `json:"registered,omitempty"`
}

// Registration is an attendee registration for an event.
type Registration struct {
	ID            string    `json:"id"`
	EventID       string    `json:"eventId"`
	UserID        *string   `json:"userId"`
	AttendeeName  string    `json:"attendeeName,omitempty"`
	AttendeeEmail string    `json:"attendeeEmail,omitempty"`
	AttendeePhone string    `json:"attendeePhone,omitempty"`
	Notes         string    `json:"notes,omitempty"`
	CreatedAt     time.Time `json:"createdAt"`
}

// Request is the payload for creating or updating an event.
type Request struct {
	Title                string     `json:"title"`
	Description          string     `json:"description"`
	Location             string     `json:"location"`
	StartDate            *time.Time `json:"startDate"`
	EndDate              *time.Time `json:"endDate"`
	Image                string     `json:"image"`
	Capacity             *int       `json:"capacity"`
	RegistrationRequired *bool      `json:"registrationRequired"`
}

// RegistrationRequest is the payload for registering for an event.
type RegistrationRequest struct {
	AttendeeName  string `json:"attendeeName"`
	AttendeeEmail string `json:"attendeeEmail"`
	AttendeePhone string `json:"attendeePhone"`
	Notes         string `json:"notes"`
}
