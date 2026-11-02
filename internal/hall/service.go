package hall

import (
	"context"
	"errors"
	"strings"

	"believers_palace/internal/auth"
)

// ErrForbidden is returned when the caller lacks permission for the operation.
var ErrForbidden = errors.New("insufficient permissions")

// ValidationError describes a request validation failure.
type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

// churchGetter verifies a church exists.
type churchGetter interface {
	Exists(ctx context.Context, churchID string) (bool, error)
}

// Service holds hall business logic and authorization.
type Service struct {
	repo     *Repository
	churches churchGetter
}

// NewService creates a hall service.
func NewService(repo *Repository, churches churchGetter) *Service {
	return &Service{repo: repo, churches: churches}
}

// List returns a page of halls for a church.
func (s *Service) List(ctx context.Context, churchID, search string, limit, offset int) ([]Hall, int, error) {
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, 0, err
	}
	return s.repo.ListByChurch(ctx, churchID, strings.TrimSpace(search), limit, offset)
}

// Get returns a hall by ID.
func (s *Service) Get(ctx context.Context, id string) (*Hall, error) {
	return s.repo.GetByID(ctx, id)
}

// Create adds a hall. Caller must manage the church.
func (s *Service) Create(ctx context.Context, id auth.Identity, churchID string, in CreateRequest) (*Hall, error) {
	if !canManageChurch(id, churchID) {
		return nil, ErrForbidden
	}
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, err
	}
	in.Name = strings.TrimSpace(in.Name)
	if in.Name == "" {
		return nil, invalid("name is required")
	}
	if in.Capacity != nil && *in.Capacity < 1 {
		return nil, invalid("capacity must be at least 1")
	}
	if in.Price != nil && *in.Price < 0 {
		return nil, invalid("price cannot be negative")
	}
	return s.repo.Create(ctx, churchID, in)
}

// Update modifies a hall. Caller must manage the hall's church.
func (s *Service) Update(ctx context.Context, id auth.Identity, hallID string, in UpdateRequest) (*Hall, error) {
	existing, err := s.repo.GetByID(ctx, hallID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return nil, ErrForbidden
	}
	if in.Name != nil && strings.TrimSpace(*in.Name) == "" {
		return nil, invalid("name cannot be empty")
	}
	if in.Capacity != nil && *in.Capacity < 1 {
		return nil, invalid("capacity must be at least 1")
	}
	if in.Price != nil && *in.Price < 0 {
		return nil, invalid("price cannot be negative")
	}
	return s.repo.Update(ctx, hallID, in)
}

// Delete removes a hall. Caller must manage the hall's church.
func (s *Service) Delete(ctx context.Context, id auth.Identity, hallID string) error {
	existing, err := s.repo.GetByID(ctx, hallID)
	if err != nil {
		return err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return ErrForbidden
	}
	return s.repo.Delete(ctx, hallID)
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

// canManageChurch reports whether the identity may administer the given church.
func canManageChurch(id auth.Identity, churchID string) bool {
	if id.Role.IsSuperAdmin() {
		return true
	}
	return id.Role == auth.RoleChurchAdmin && id.ChurchID != "" && id.ChurchID == churchID
}
