package cemetery

import (
	"context"
	"errors"
	"strings"

	"believers_palace/internal/auth"
)

// ErrForbidden is returned when the caller lacks permission for the operation.
var ErrForbidden = errors.New("insufficient permissions")

// ErrPlotUnavailable is returned when a requested plot is not available.
var ErrPlotUnavailable = errors.New("requested plot is not available")

// ValidationError describes a request validation failure.
type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

// churchGetter verifies a church exists.
type churchGetter interface {
	Exists(ctx context.Context, churchID string) (bool, error)
}

// Service holds cemetery business logic and authorization.
type Service struct {
	repo     *Repository
	churches churchGetter
}

// NewService creates a cemetery service.
func NewService(repo *Repository, churches churchGetter) *Service {
	return &Service{repo: repo, churches: churches}
}

// ----- Plots -----

// ListPlots returns a page of plots for a church. Available to authenticated users.
func (s *Service) ListPlots(ctx context.Context, churchID string, status PlotStatus, search string, limit, offset int) ([]Plot, int, error) {
	if status != "" && !ValidPlotStatus(status) {
		return nil, 0, invalid("invalid status filter")
	}
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, 0, err
	}
	return s.repo.ListPlots(ctx, PlotFilter{
		ChurchID: churchID,
		Status:   status,
		Search:   strings.TrimSpace(search),
		Limit:    limit,
		Offset:   offset,
	})
}

// CreatePlot adds a plot. Caller must manage the church.
func (s *Service) CreatePlot(ctx context.Context, id auth.Identity, churchID string, in PlotCreateRequest) (*Plot, error) {
	if !canManageChurch(id, churchID) {
		return nil, ErrForbidden
	}
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, err
	}
	if strings.TrimSpace(in.PlotNumber) == "" {
		return nil, invalid("plotNumber is required")
	}
	status := in.Status
	if status == "" {
		status = PlotAvailable
	}
	if !ValidPlotStatus(status) {
		return nil, invalid("invalid plot status")
	}
	return s.repo.CreatePlot(ctx, churchID, in, status)
}

// UpdatePlot modifies a plot. Caller must manage the plot's church.
func (s *Service) UpdatePlot(ctx context.Context, id auth.Identity, plotID string, in PlotUpdateRequest) (*Plot, error) {
	existing, err := s.repo.GetPlot(ctx, plotID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return nil, ErrForbidden
	}
	if in.PlotNumber != nil && strings.TrimSpace(*in.PlotNumber) == "" {
		return nil, invalid("plotNumber cannot be empty")
	}
	if in.Status != nil && !ValidPlotStatus(*in.Status) {
		return nil, invalid("invalid plot status")
	}
	return s.repo.UpdatePlot(ctx, plotID, in)
}

// DeletePlot removes a plot. Caller must manage the plot's church.
func (s *Service) DeletePlot(ctx context.Context, id auth.Identity, plotID string) error {
	existing, err := s.repo.GetPlot(ctx, plotID)
	if err != nil {
		return err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return ErrForbidden
	}
	return s.repo.DeletePlot(ctx, plotID)
}

// ----- Service requests -----

// ListRequests returns a page of service requests for a church. Administrators
// see all; regular users see only their own.
func (s *Service) ListRequests(ctx context.Context, id auth.Identity, churchID string, status RequestStatus, typ ServiceType, search string, limit, offset int) ([]ServiceRequest, int, error) {
	if status != "" && !ValidRequestStatus(status) {
		return nil, 0, invalid("invalid status filter")
	}
	if typ != "" && !ValidServiceType(typ) {
		return nil, 0, invalid("invalid type filter")
	}
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, 0, err
	}

	f := RequestFilter{ChurchID: churchID, Status: status, Type: typ, Search: strings.TrimSpace(search), Limit: limit, Offset: offset}
	if !canManageChurch(id, churchID) {
		f.UserID = id.UserID
	}
	return s.repo.ListRequests(ctx, f)
}

// CreateRequest submits a service request for the calling user.
func (s *Service) CreateRequest(ctx context.Context, id auth.Identity, churchID string, in ServiceRequestCreate) (*ServiceRequest, error) {
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, err
	}
	if !ValidServiceType(in.Type) {
		return nil, invalid("a valid type is required")
	}
	if strings.TrimSpace(in.FullName) == "" {
		return nil, invalid("fullName is required")
	}
	if strings.TrimSpace(in.ContactPhone) == "" {
		return nil, invalid("contactPhone is required")
	}
	if strings.TrimSpace(in.Description) == "" {
		return nil, invalid("description is required")
	}

	// If a plot is referenced, it must belong to the church and be available.
	if in.PlotID != nil && *in.PlotID != "" {
		available, err := s.repo.PlotAvailable(ctx, churchID, *in.PlotID)
		if err != nil {
			return nil, err
		}
		if !available {
			return nil, ErrPlotUnavailable
		}
	}

	return s.repo.CreateRequest(ctx, churchID, id.UserID, in)
}

// GetRequest returns a service request. Accessible to the owner or an
// administrator of its church.
func (s *Service) GetRequest(ctx context.Context, id auth.Identity, requestID string) (*ServiceRequest, error) {
	sr, err := s.repo.GetRequest(ctx, requestID)
	if err != nil {
		return nil, err
	}
	if sr.UserID != id.UserID && !canManageChurch(id, sr.ChurchID) {
		return nil, ErrForbidden
	}
	return sr, nil
}

// UpdateRequestStatus updates a request's status. Administrators only.
func (s *Service) UpdateRequestStatus(ctx context.Context, id auth.Identity, requestID string, in RequestStatusUpdate) (*ServiceRequest, error) {
	sr, err := s.repo.GetRequest(ctx, requestID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, sr.ChurchID) {
		return nil, ErrForbidden
	}
	if !ValidRequestStatus(in.Status) {
		return nil, invalid("invalid status")
	}
	return s.repo.UpdateRequestStatus(ctx, requestID, in)
}

func (s *Service) ensureChurch(ctx context.Context, churchID string) error {
	ok, err := s.churches.Exists(ctx, churchID)
	if err != nil {
		return err
	}
	if !ok {
		// Church-scoped not-found surfaces as a plot/request not-found at the
		// handler; use the request variant as the generic 404 for this domain.
		return ErrRequestNotFound
	}
	return nil
}

// canManageChurch reports whether the identity administers the given church.
func canManageChurch(id auth.Identity, churchID string) bool {
	if id.Role.IsSuperAdmin() {
		return true
	}
	return id.Role == auth.RoleChurchAdmin && id.ChurchID != "" && id.ChurchID == churchID
}
