package booking

import (
	"context"
	"errors"

	"believers_palace/internal/auth"
)

// ErrForbidden is returned when the caller lacks permission for the operation.
var ErrForbidden = errors.New("insufficient permissions")

// ErrHallNotFound is returned when the referenced hall does not exist.
var ErrHallNotFound = errors.New("hall not found")

// ValidationError describes a request validation failure.
type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

// hallResolver resolves the owning church of a hall.
type hallResolver interface {
	ChurchIDOf(ctx context.Context, hallID string) (churchID string, ok bool, err error)
}

// Service holds booking business logic and authorization.
type Service struct {
	repo  *Repository
	halls hallResolver
}

// NewService creates a booking service.
func NewService(repo *Repository, halls hallResolver) *Service {
	return &Service{repo: repo, halls: halls}
}

// Create books a hall for the calling user. The booking starts as pending.
func (s *Service) Create(ctx context.Context, id auth.Identity, churchID string, in CreateRequest) (*Booking, error) {
	if in.HallID == "" {
		return nil, invalid("hallId is required")
	}
	if in.StartDate == nil || in.EndDate == nil {
		return nil, invalid("startDate and endDate are required")
	}
	if !in.EndDate.After(*in.StartDate) {
		return nil, invalid("endDate must be after startDate")
	}

	hallChurch, ok, err := s.halls.ChurchIDOf(ctx, in.HallID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrHallNotFound
	}
	// The hall must belong to the church in the path.
	if hallChurch != churchID {
		return nil, invalid("hall does not belong to the specified church")
	}

	// Reject overlaps with existing active bookings. The database also enforces
	// this via an exclusion constraint (race-proof); this check yields a clean
	// error in the common case.
	overlaps, err := s.repo.HasOverlap(ctx, in.HallID, *in.StartDate, *in.EndDate)
	if err != nil {
		return nil, err
	}
	if overlaps {
		return nil, ErrOverlap
	}

	return s.repo.Create(ctx, churchID, in.HallID, id.UserID, in)
}

// List returns bookings for a church. Administrators see all church bookings;
// regular users see only their own.
func (s *Service) List(ctx context.Context, id auth.Identity, churchID string, status Status, search string, limit, offset int) ([]Booking, int, error) {
	if status != "" && !ValidStatus(status) {
		return nil, 0, invalid("invalid status filter")
	}

	f := ListFilter{ChurchID: churchID, Status: status, Search: search, Limit: limit, Offset: offset}
	if !canManageChurch(id, churchID) {
		// Non-admins may only see their own bookings.
		f.UserID = id.UserID
	}
	return s.repo.List(ctx, f)
}

// ListMine returns the calling user's bookings across all churches.
func (s *Service) ListMine(ctx context.Context, id auth.Identity, status Status, search string, limit, offset int) ([]Booking, int, error) {
	if status != "" && !ValidStatus(status) {
		return nil, 0, invalid("invalid status filter")
	}
	f := ListFilter{UserID: id.UserID, Status: status, Search: search, Limit: limit, Offset: offset}
	return s.repo.List(ctx, f)
}

// Get returns a booking. Accessible to the owner or an administrator of its church.
func (s *Service) Get(ctx context.Context, id auth.Identity, bookingID string) (*Booking, error) {
	b, err := s.repo.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if !s.canView(id, b) {
		return nil, ErrForbidden
	}
	return b, nil
}

// UpdateStatus changes a booking's status. Administrators only.
func (s *Service) UpdateStatus(ctx context.Context, id auth.Identity, bookingID string, in StatusUpdateRequest) (*Booking, error) {
	b, err := s.repo.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, b.ChurchID) {
		return nil, ErrForbidden
	}
	if !ValidStatus(in.Status) {
		return nil, invalid("invalid status")
	}
	return s.repo.UpdateStatus(ctx, bookingID, in.Status, in.AdminNotes)
}

// Cancel cancels a booking. Allowed for the booking owner or an administrator.
func (s *Service) Cancel(ctx context.Context, id auth.Identity, bookingID string, in CancelRequest) (*Booking, error) {
	b, err := s.repo.GetByID(ctx, bookingID)
	if err != nil {
		return nil, err
	}
	if !s.canView(id, b) {
		return nil, ErrForbidden
	}
	if b.Status == StatusCancelled {
		return b, nil
	}
	if b.Status == StatusCompleted {
		return nil, invalid("a completed booking cannot be cancelled")
	}
	return s.repo.Cancel(ctx, bookingID, in.Reason)
}

// canView reports whether the identity may view/cancel the booking: the owner,
// or an administrator of the booking's church.
func (s *Service) canView(id auth.Identity, b *Booking) bool {
	if b.UserID == id.UserID {
		return true
	}
	return canManageChurch(id, b.ChurchID)
}

// canManageChurch reports whether the identity administers the given church.
func canManageChurch(id auth.Identity, churchID string) bool {
	if id.Role.IsSuperAdmin() {
		return true
	}
	return id.Role == auth.RoleChurchAdmin && id.ChurchID != "" && id.ChurchID == churchID
}
