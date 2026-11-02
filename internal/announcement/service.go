package announcement

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

// churchGetter verifies a church exists (returns ErrNotFound otherwise).
type churchGetter interface {
	Exists(ctx context.Context, churchID string) (bool, error)
}

// Service holds announcement business logic and authorization.
type Service struct {
	repo     *Repository
	churches churchGetter
}

// NewService creates an announcement service.
func NewService(repo *Repository, churches churchGetter) *Service {
	return &Service{repo: repo, churches: churches}
}

// List returns a page of announcements for a church.
func (s *Service) List(ctx context.Context, churchID, search string, limit, offset int) ([]Announcement, int, error) {
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, 0, err
	}
	return s.repo.ListByChurch(ctx, churchID, strings.TrimSpace(search), limit, offset)
}

// Create adds an announcement. Caller must manage the church.
func (s *Service) Create(ctx context.Context, id auth.Identity, churchID string, in CreateRequest) (*Announcement, error) {
	if !canManageChurch(id, churchID) {
		return nil, ErrForbidden
	}
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, err
	}
	in.Title = strings.TrimSpace(in.Title)
	in.Content = strings.TrimSpace(in.Content)
	if in.Title == "" {
		return nil, invalid("title is required")
	}
	if in.Content == "" {
		return nil, invalid("content is required")
	}
	return s.repo.Create(ctx, churchID, in)
}

// Update modifies an announcement. Caller must manage the announcement's church.
func (s *Service) Update(ctx context.Context, id auth.Identity, announcementID string, in UpdateRequest) (*Announcement, error) {
	existing, err := s.repo.GetByID(ctx, announcementID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return nil, ErrForbidden
	}
	if in.Title != nil && strings.TrimSpace(*in.Title) == "" {
		return nil, invalid("title cannot be empty")
	}
	if in.Content != nil && strings.TrimSpace(*in.Content) == "" {
		return nil, invalid("content cannot be empty")
	}
	return s.repo.Update(ctx, announcementID, in)
}

// Delete removes an announcement. Caller must manage the announcement's church.
func (s *Service) Delete(ctx context.Context, id auth.Identity, announcementID string) error {
	existing, err := s.repo.GetByID(ctx, announcementID)
	if err != nil {
		return err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return ErrForbidden
	}
	return s.repo.Delete(ctx, announcementID)
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

// canManageChurch reports whether the identity may manage pastoral content
// (announcements) for the given church: super_admin, or church staff (priest,
// associate_priest, church_admin) scoped to their own church.
func canManageChurch(id auth.Identity, churchID string) bool {
	return auth.CanManageChurchContent(id, churchID)
}
