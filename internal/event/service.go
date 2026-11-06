package event

import (
	"context"
	"errors"
	"strings"

	"believers_palace/internal/auth"
)

// ErrForbidden is returned when the caller lacks permission for the operation.
var ErrForbidden = errors.New("insufficient permissions")

// ErrRegistrationUnavailable is returned when an event is full or otherwise
// not accepting registrations.
var ErrRegistrationUnavailable = errors.New("event registration unavailable")

// ValidationError describes a request validation failure.
type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

// churchGetter verifies a church exists.
type churchGetter interface {
	Exists(ctx context.Context, churchID string) (bool, error)
}

// Service holds event business logic and authorization.
type Service struct {
	repo     *Repository
	churches churchGetter
}

// NewService creates an event service.
func NewService(repo *Repository, churches churchGetter) *Service {
	return &Service{repo: repo, churches: churches}
}

// List returns a page of events for a church, each flagged with whether the
// calling user is registered.
func (s *Service) List(ctx context.Context, id auth.Identity, churchID, search string, limit, offset int) ([]Event, int, error) {
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, 0, err
	}
	items, total, err := s.repo.ListByChurch(ctx, churchID, strings.TrimSpace(search), limit, offset)
	if err != nil {
		return nil, 0, err
	}
	ids := make([]string, len(items))
	for i := range items {
		ids[i] = items[i].ID
	}
	registered, err := s.repo.RegisteredEventIDs(ctx, id.UserID, ids)
	if err != nil {
		return nil, 0, err
	}
	for i := range items {
		v := registered[items[i].ID]
		items[i].Registered = &v
	}
	return items, total, nil
}

// Unregister cancels the calling user's registration for an event.
func (s *Service) Unregister(ctx context.Context, id auth.Identity, eventID string) error {
	if _, err := s.repo.GetByID(ctx, eventID); err != nil {
		return err
	}
	if id.UserID == "" {
		return ErrNotRegistered
	}
	return s.repo.DeleteRegistration(ctx, eventID, id.UserID)
}

// Get returns an event by ID.
func (s *Service) Get(ctx context.Context, id string) (*Event, error) {
	return s.repo.GetByID(ctx, id)
}

// Create adds an event. Caller must manage the church.
func (s *Service) Create(ctx context.Context, id auth.Identity, churchID string, in Request) (*Event, error) {
	if !canManageChurch(id, churchID) {
		return nil, ErrForbidden
	}
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, err
	}
	if err := validate(in); err != nil {
		return nil, err
	}
	return s.repo.Create(ctx, churchID, in)
}

// Update modifies an event. Caller must manage the event's church.
func (s *Service) Update(ctx context.Context, id auth.Identity, eventID string, in Request) (*Event, error) {
	existing, err := s.repo.GetByID(ctx, eventID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return nil, ErrForbidden
	}
	if err := validate(in); err != nil {
		return nil, err
	}
	return s.repo.Update(ctx, eventID, in)
}

// Delete removes an event. Caller must manage the event's church.
func (s *Service) Delete(ctx context.Context, id auth.Identity, eventID string) error {
	existing, err := s.repo.GetByID(ctx, eventID)
	if err != nil {
		return err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return ErrForbidden
	}
	return s.repo.Delete(ctx, eventID)
}

// Register registers the calling user (or a named attendee) for an event.
// Enforces capacity when set.
func (s *Service) Register(ctx context.Context, id auth.Identity, eventID string, in RegistrationRequest) (*Registration, error) {
	ev, err := s.repo.GetByID(ctx, eventID)
	if err != nil {
		return nil, err
	}

	if ev.Capacity != nil {
		count, err := s.repo.CountRegistrations(ctx, eventID)
		if err != nil {
			return nil, err
		}
		if count >= *ev.Capacity {
			return nil, ErrRegistrationUnavailable
		}
	}

	var userID *string
	if id.UserID != "" {
		userID = &id.UserID
	}
	return s.repo.CreateRegistration(ctx, eventID, userID, in)
}

// ListRegistrations returns a page of attendee registrations for an event.
// Only administrators of the event's church (or a super admin) may view them.
func (s *Service) ListRegistrations(ctx context.Context, id auth.Identity, eventID string, limit, offset int) ([]Registration, int, error) {
	ev, err := s.repo.GetByID(ctx, eventID)
	if err != nil {
		return nil, 0, err
	}
	if !canManageChurch(id, ev.ChurchID) {
		return nil, 0, ErrForbidden
	}
	return s.repo.ListRegistrations(ctx, eventID, limit, offset)
}

func (s *Service) ensureChurch(ctx context.Context, churchID string) error {
	ok, err := s.churches.Exists(ctx, churchID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}
	return nil
}

func validate(in Request) error {
	if strings.TrimSpace(in.Title) == "" {
		return invalid("title is required")
	}
	if in.StartDate == nil {
		return invalid("startDate is required")
	}
	if in.EndDate != nil && in.EndDate.Before(*in.StartDate) {
		return invalid("endDate cannot be before startDate")
	}
	if in.Capacity != nil && *in.Capacity < 1 {
		return invalid("capacity must be at least 1")
	}
	return nil
}

// canManageChurch reports whether the identity may manage pastoral content
// (events) for the given church: super_admin, or church staff (priest,
// associate_priest, church_admin) scoped to their own church.
func canManageChurch(id auth.Identity, churchID string) bool {
	return auth.CanManageChurchContent(id, churchID)
}
