// Package cemetery implements cemetery plots and cemetery service requests.
// Administrators manage plots and request statuses; users submit and view
// their own service requests.
package cemetery

import "time"

// PlotStatus is the availability state of a cemetery plot.
type PlotStatus string

const (
	PlotAvailable   PlotStatus = "available"
	PlotReserved    PlotStatus = "reserved"
	PlotOccupied    PlotStatus = "occupied"
	PlotUnavailable PlotStatus = "unavailable"
)

// ValidPlotStatus reports whether s is a recognized plot status.
func ValidPlotStatus(s PlotStatus) bool {
	switch s {
	case PlotAvailable, PlotReserved, PlotOccupied, PlotUnavailable:
		return true
	default:
		return false
	}
}

// ServiceType is the category of a cemetery service request.
type ServiceType string

const (
	ServiceBurial          ServiceType = "burial"
	ServicePlotReservation ServiceType = "plot_reservation"
	ServiceGraveMaint      ServiceType = "grave_maintenance"
	ServiceMemorial        ServiceType = "memorial_service"
	ServiceOther           ServiceType = "other"
)

// ValidServiceType reports whether t is a recognized service type.
func ValidServiceType(t ServiceType) bool {
	switch t {
	case ServiceBurial, ServicePlotReservation, ServiceGraveMaint, ServiceMemorial, ServiceOther:
		return true
	default:
		return false
	}
}

// RequestStatus is the lifecycle state of a service request.
type RequestStatus string

const (
	RequestPending   RequestStatus = "pending"
	RequestApproved  RequestStatus = "approved"
	RequestRejected  RequestStatus = "rejected"
	RequestScheduled RequestStatus = "scheduled"
	RequestCompleted RequestStatus = "completed"
	RequestCancelled RequestStatus = "cancelled"
)

// ValidRequestStatus reports whether s is a recognized request status.
func ValidRequestStatus(s RequestStatus) bool {
	switch s {
	case RequestPending, RequestApproved, RequestRejected, RequestScheduled, RequestCompleted, RequestCancelled:
		return true
	default:
		return false
	}
}

// Plot is a cemetery plot record.
type Plot struct {
	ID                  string     `json:"id"`
	ChurchID            string     `json:"churchId"`
	PlotNumber          string     `json:"plotNumber"`
	Section             string     `json:"section,omitempty"`
	LocationDescription string     `json:"locationDescription,omitempty"`
	Status              PlotStatus `json:"status"`
	Notes               string     `json:"notes,omitempty"`
	CreatedAt           time.Time  `json:"createdAt"`
}

// PlotCreateRequest is the payload for creating a cemetery plot.
type PlotCreateRequest struct {
	PlotNumber          string     `json:"plotNumber"`
	Section             string     `json:"section"`
	LocationDescription string     `json:"locationDescription"`
	Status              PlotStatus `json:"status"`
	Notes               string     `json:"notes"`
}

// PlotUpdateRequest is the payload for updating a cemetery plot. All fields are
// optional; only the provided (non-nil) fields are changed.
type PlotUpdateRequest struct {
	PlotNumber          *string     `json:"plotNumber"`
	Section             *string     `json:"section"`
	LocationDescription *string     `json:"locationDescription"`
	Status              *PlotStatus `json:"status"`
	Notes               *string     `json:"notes"`
}

// ServiceRequest is a cemetery service request record.
type ServiceRequest struct {
	ID            string        `json:"id"`
	ChurchID      string        `json:"churchId"`
	UserID        string        `json:"userId"`
	Type          ServiceType   `json:"type"`
	Status        RequestStatus `json:"status"`
	FullName      string        `json:"fullName"`
	ContactPhone  string        `json:"contactPhone,omitempty"`
	ContactEmail  string        `json:"contactEmail,omitempty"`
	DeceasedName  string        `json:"deceasedName,omitempty"`
	RequestedDate *time.Time    `json:"requestedDate,omitempty"`
	PlotID        *string       `json:"plotId"`
	Description   string        `json:"description,omitempty"`
	Notes         string        `json:"notes,omitempty"`
	AdminNotes    string        `json:"adminNotes,omitempty"`
	ScheduledDate *time.Time    `json:"scheduledDate"`
	CreatedAt     time.Time     `json:"createdAt"`
	UpdatedAt     time.Time     `json:"updatedAt"`
}

// ServiceRequestCreate is the payload for submitting a service request.
type ServiceRequestCreate struct {
	Type          ServiceType `json:"type"`
	FullName      string      `json:"fullName"`
	ContactPhone  string      `json:"contactPhone"`
	ContactEmail  string      `json:"contactEmail"`
	DeceasedName  string      `json:"deceasedName"`
	RequestedDate *time.Time  `json:"requestedDate"`
	PlotID        *string     `json:"plotId"`
	Description   string      `json:"description"`
	Notes         string      `json:"notes"`
}

// RequestStatusUpdate is the payload for an administrator updating a request.
type RequestStatusUpdate struct {
	Status        RequestStatus `json:"status"`
	AdminNotes    string        `json:"adminNotes"`
	ScheduledDate *time.Time    `json:"scheduledDate"`
}
