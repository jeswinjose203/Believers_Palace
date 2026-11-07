// Package booking implements hall bookings: a user reserves a church hall for
// a date range. Bookings move through a status lifecycle managed by church
// administrators, and may be cancelled by the owner or an administrator.
package booking

import "time"

// Status is the lifecycle state of a booking.
type Status string

const (
	StatusPending   Status = "pending"
	StatusApproved  Status = "approved"
	StatusRejected  Status = "rejected"
	StatusCancelled Status = "cancelled"
	StatusCompleted Status = "completed"
)

// ValidStatus reports whether s is a recognized booking status.
func ValidStatus(s Status) bool {
	switch s {
	case StatusPending, StatusApproved, StatusRejected, StatusCancelled, StatusCompleted:
		return true
	default:
		return false
	}
}

// Requester holds the public profile of the user who made a booking, included
// in admin-facing responses so staff can see who requested the hall.
type Requester struct {
	ID         string  `json:"id"`
	Name       string  `json:"name"`
	Email      string  `json:"email"`
	Phone      *string `json:"phone,omitempty"`
	ProfilePic *string `json:"profilePic,omitempty"`
}

// Booking is a hall booking record.
type Booking struct {
	ID                 string     `json:"id"`
	ChurchID           string     `json:"churchId"`
	HallID             string     `json:"hallId"`
	UserID             string     `json:"userId"`
	StartDate          time.Time  `json:"startDate"`
	EndDate            time.Time  `json:"endDate"`
	Purpose            string     `json:"purpose,omitempty"`
	Notes              string     `json:"notes,omitempty"`
	Status             Status     `json:"status"`
	AdminNotes         string     `json:"adminNotes,omitempty"`
	CancellationReason string     `json:"cancellationReason,omitempty"`
	CreatedAt          time.Time  `json:"createdAt"`
	// User is the requester's public profile. Populated on list/get responses.
	User *Requester `json:"user,omitempty"`
}

// CreateRequest is the payload for creating a booking.
type CreateRequest struct {
	HallID    string     `json:"hallId"`
	StartDate *time.Time `json:"startDate"`
	EndDate   *time.Time `json:"endDate"`
	Purpose   string     `json:"purpose"`
	Notes     string     `json:"notes"`
}

// StatusUpdateRequest is the payload for an administrator updating booking status.
type StatusUpdateRequest struct {
	Status     Status `json:"status"`
	AdminNotes string `json:"adminNotes"`
}

// CancelRequest is the optional payload for cancelling a booking.
type CancelRequest struct {
	Reason string `json:"reason"`
}
