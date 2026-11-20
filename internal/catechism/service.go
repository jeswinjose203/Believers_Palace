package catechism

import (
	"context"
	"errors"
	"strings"

	"believers_palace/internal/auth"
)

// ErrForbidden is returned when the caller lacks permission for the operation.
var ErrForbidden = errors.New("insufficient permissions")

// ErrClassNotOpen is returned when enrolling in a class that is not open.
var ErrClassNotOpen = errors.New("class is not open for enrollment")

// ValidationError describes a request validation failure.
type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

type churchGetter interface {
	Exists(ctx context.Context, churchID string) (bool, error)
}

// Service holds catechism business logic and authorization.
type Service struct {
	repo     *Repository
	churches churchGetter
}

// NewService creates a catechism service.
func NewService(repo *Repository, churches churchGetter) *Service {
	return &Service{repo: repo, churches: churches}
}

func canManageChurch(id auth.Identity, churchID string) bool {
	return auth.CanManageChurchContent(id, churchID)
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

func (s *Service) attachClassStats(ctx context.Context, id auth.Identity, items []Class) error {
	for i := range items {
		count, err := s.repo.CountApprovedEnrollments(ctx, items[i].ID)
		if err != nil {
			return err
		}
		items[i].EnrolledCount = count
		items[i].AvailableSeats = items[i].Capacity - count
		if items[i].AvailableSeats < 0 {
			items[i].AvailableSeats = 0
		}
		if id.UserID != "" {
			enrolled, err := s.repo.GuardianEnrolledInClass(ctx, items[i].ID, id.UserID)
			if err != nil {
				return err
			}
			items[i].Enrolled = enrolled
		}
	}
	return nil
}

// ListClasses returns a page of classes for a church.
func (s *Service) ListClasses(
	ctx context.Context, id auth.Identity, churchID, search string,
	status ClassStatus, level ClassLevel, limit, offset int,
) ([]Class, int, error) {
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, 0, err
	}
	if status != "" && !ValidClassStatus(status) {
		return nil, 0, invalid("invalid status filter")
	}
	if level != "" && !ValidClassLevel(level) {
		return nil, 0, invalid("invalid level filter")
	}
	items, total, err := s.repo.ListClassesByChurch(ctx, churchID, strings.TrimSpace(search), status, level, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	if err := s.attachClassStats(ctx, id, items); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// GetClass returns a class by ID with enrollment stats for the caller.
func (s *Service) GetClass(ctx context.Context, id auth.Identity, classID string) (*Class, error) {
	c, err := s.repo.GetClassByID(ctx, classID)
	if err != nil {
		return nil, err
	}
	items := []Class{*c}
	if err := s.attachClassStats(ctx, id, items); err != nil {
		return nil, err
	}
	out := items[0]
	return &out, nil
}

// CreateClass adds a class. Caller must manage the church.
func (s *Service) CreateClass(ctx context.Context, id auth.Identity, churchID string, in ClassRequest) (*Class, error) {
	if !canManageChurch(id, churchID) {
		return nil, ErrForbidden
	}
	if err := s.ensureChurch(ctx, churchID); err != nil {
		return nil, err
	}
	if err := validateClassRequest(in); err != nil {
		return nil, err
	}
	return s.repo.CreateClass(ctx, churchID, in)
}

// UpdateClass modifies a class.
func (s *Service) UpdateClass(ctx context.Context, id auth.Identity, classID string, in ClassRequest) (*Class, error) {
	existing, err := s.repo.GetClassByID(ctx, classID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return nil, ErrForbidden
	}
	if err := validateClassRequest(in); err != nil {
		return nil, err
	}
	return s.repo.UpdateClass(ctx, classID, in)
}

// DeleteClass removes a class.
func (s *Service) DeleteClass(ctx context.Context, id auth.Identity, classID string) error {
	existing, err := s.repo.GetClassByID(ctx, classID)
	if err != nil {
		return err
	}
	if !canManageChurch(id, existing.ChurchID) {
		return ErrForbidden
	}
	return s.repo.DeleteClass(ctx, classID)
}

// CreateEnrollment enrolls a student in a class for the calling user.
func (s *Service) CreateEnrollment(ctx context.Context, id auth.Identity, classID string, in EnrollmentRequest) (*Enrollment, error) {
	if id.UserID == "" {
		return nil, ErrForbidden
	}
	cls, err := s.repo.GetClassByID(ctx, classID)
	if err != nil {
		return nil, err
	}
	if cls.Status != StatusOpen {
		return nil, ErrClassNotOpen
	}
	if err := validateEnrollmentRequest(in, cls); err != nil {
		return nil, err
	}
	return s.repo.CreateEnrollment(ctx, classID, id.UserID, in)
}

// ListEnrollmentsByClass lists enrollments; staff see all, users see only their own.
func (s *Service) ListEnrollmentsByClass(
	ctx context.Context, id auth.Identity, classID, search string, limit, offset int,
) ([]Enrollment, int, error) {
	cls, err := s.repo.GetClassByID(ctx, classID)
	if err != nil {
		return nil, 0, err
	}
	guardianFilter := ""
	if canManageChurch(id, cls.ChurchID) {
		// staff: all enrollments
	} else {
		guardianFilter = id.UserID
		if guardianFilter == "" {
			return nil, 0, ErrForbidden
		}
	}
	return s.repo.ListEnrollmentsByClass(ctx, classID, strings.TrimSpace(search), guardianFilter, limit, offset)
}

// ListMyEnrollments returns the calling user's enrollments.
func (s *Service) ListMyEnrollments(ctx context.Context, id auth.Identity, search string, limit, offset int) ([]Enrollment, int, error) {
	if id.UserID == "" {
		return nil, 0, ErrForbidden
	}
	return s.repo.ListEnrollmentsByGuardian(ctx, id.UserID, strings.TrimSpace(search), limit, offset)
}

// UpdateEnrollmentStatus updates enrollment status (staff).
func (s *Service) UpdateEnrollmentStatus(ctx context.Context, id auth.Identity, enrollmentID string, status EnrollmentStatus) (*Enrollment, error) {
	if !ValidEnrollmentStatus(status) {
		return nil, invalid("invalid status")
	}
	switch status {
	case EnrollApproved, EnrollRejected, EnrollCompleted:
	default:
		return nil, invalid("status must be approved, rejected, or completed")
	}

	enrollment, err := s.repo.GetEnrollmentByID(ctx, enrollmentID)
	if err != nil {
		return nil, err
	}
	cls, err := s.repo.GetClassByID(ctx, enrollment.ClassID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, cls.ChurchID) {
		return nil, ErrForbidden
	}
	if status == EnrollCompleted {
		if cls.Status != StatusCompleted {
			return nil, invalid("class must be completed before marking enrollments completed")
		}
		if enrollment.Status != EnrollApproved {
			return nil, invalid("only approved enrollments can be marked completed")
		}
	}
	if status == EnrollApproved || status == EnrollRejected {
		if enrollment.Status != EnrollPending {
			return nil, invalid("only pending enrollments can be approved or rejected")
		}
	}
	return s.repo.UpdateEnrollmentStatus(ctx, enrollmentID, status)
}

// WithdrawEnrollment marks an enrollment withdrawn (owner or staff).
func (s *Service) WithdrawEnrollment(ctx context.Context, id auth.Identity, enrollmentID string) (*Enrollment, error) {
	enrollment, err := s.repo.GetEnrollmentByID(ctx, enrollmentID)
	if err != nil {
		return nil, err
	}
	cls, err := s.repo.GetClassByID(ctx, enrollment.ClassID)
	if err != nil {
		return nil, err
	}
	isOwner := id.UserID != "" && id.UserID == enrollment.GuardianID
	if !isOwner && !canManageChurch(id, cls.ChurchID) {
		return nil, ErrForbidden
	}
	if enrollment.Status != EnrollPending && enrollment.Status != EnrollApproved {
		return nil, invalid("only pending or approved enrollments can be withdrawn")
	}
	return s.repo.UpdateEnrollmentStatus(ctx, enrollmentID, EnrollWithdrawn)
}

// ListSessions returns sessions for a class if the caller is staff or an approved guardian.
func (s *Service) ListSessions(ctx context.Context, id auth.Identity, classID, search string, limit, offset int) ([]Session, int, error) {
	cls, err := s.repo.GetClassByID(ctx, classID)
	if err != nil {
		return nil, 0, err
	}
	if canManageChurch(id, cls.ChurchID) {
		return s.repo.ListSessionsByClass(ctx, classID, strings.TrimSpace(search), limit, offset)
	}
	if id.UserID == "" {
		return nil, 0, ErrForbidden
	}
	ok, err := s.repo.GuardianHasApprovedEnrollment(ctx, classID, id.UserID)
	if err != nil {
		return nil, 0, err
	}
	if !ok {
		return nil, 0, ErrForbidden
	}
	return s.repo.ListSessionsByClass(ctx, classID, strings.TrimSpace(search), limit, offset)
}

// CreateSession adds a lesson session (staff).
func (s *Service) CreateSession(ctx context.Context, id auth.Identity, classID string, in SessionRequest) (*Session, error) {
	cls, err := s.repo.GetClassByID(ctx, classID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, cls.ChurchID) {
		return nil, ErrForbidden
	}
	if err := validateSessionRequest(in); err != nil {
		return nil, err
	}
	return s.repo.CreateSession(ctx, classID, in)
}

// UpdateSession modifies a session (staff).
func (s *Service) UpdateSession(ctx context.Context, id auth.Identity, sessionID string, in SessionRequest) (*Session, error) {
	sess, err := s.repo.GetSessionByID(ctx, sessionID)
	if err != nil {
		return nil, err
	}
	cls, err := s.repo.GetClassByID(ctx, sess.ClassID)
	if err != nil {
		return nil, err
	}
	if !canManageChurch(id, cls.ChurchID) {
		return nil, ErrForbidden
	}
	if err := validateSessionRequest(in); err != nil {
		return nil, err
	}
	return s.repo.UpdateSession(ctx, sessionID, in)
}

// DeleteSession removes a session (staff).
func (s *Service) DeleteSession(ctx context.Context, id auth.Identity, sessionID string) error {
	sess, err := s.repo.GetSessionByID(ctx, sessionID)
	if err != nil {
		return err
	}
	cls, err := s.repo.GetClassByID(ctx, sess.ClassID)
	if err != nil {
		return err
	}
	if !canManageChurch(id, cls.ChurchID) {
		return ErrForbidden
	}
	return s.repo.DeleteSession(ctx, sessionID)
}