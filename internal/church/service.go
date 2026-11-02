package church

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

// Service holds church business logic and authorization.
type Service struct {
	repo *Repository
}

// NewService creates a church service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// List returns a page of churches with the total count.
func (s *Service) List(ctx context.Context, search string, limit, offset int) ([]ListItem, int, error) {
	return s.repo.List(ctx, strings.TrimSpace(search), limit, offset)
}

// Get returns a church by ID.
func (s *Service) Get(ctx context.Context, id string) (*Church, error) {
	return s.repo.GetByID(ctx, id)
}

// Create creates a church. Caller must be super_admin (enforced at route level,
// re-checked here for defense in depth).
func (s *Service) Create(ctx context.Context, id auth.Identity, in Request) (*Church, error) {
	if !id.Role.IsSuperAdmin() {
		return nil, ErrForbidden
	}
	if err := validate(in); err != nil {
		return nil, err
	}
	return s.repo.Create(ctx, in)
}

// Update updates a church. Caller must be super_admin or the church_admin of
// this specific church.
func (s *Service) Update(ctx context.Context, id auth.Identity, churchID string, in Request) (*Church, error) {
	if !s.canManage(id, churchID) {
		return nil, ErrForbidden
	}
	if err := validate(in); err != nil {
		return nil, err
	}
	return s.repo.Update(ctx, churchID, in)
}

// Delete removes a church. Caller must be super_admin.
func (s *Service) Delete(ctx context.Context, id auth.Identity, churchID string) error {
	if !id.Role.IsSuperAdmin() {
		return ErrForbidden
	}
	return s.repo.Delete(ctx, churchID)
}

// canManage reports whether the identity may administer the given church:
// super_admin anywhere, or church_admin scoped to their own church.
func (s *Service) canManage(id auth.Identity, churchID string) bool {
	if id.Role.IsSuperAdmin() {
		return true
	}
	if id.Role == auth.RoleChurchAdmin && id.ChurchID != "" && id.ChurchID == churchID {
		return true
	}
	return false
}

func validate(in Request) error {
	if strings.TrimSpace(in.Name) == "" {
		return invalid("name is required")
	}
	return nil
}
