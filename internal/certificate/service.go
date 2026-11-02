package certificate

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"strings"

	"believers_palace/internal/auth"
)

// ErrForbidden is returned when the caller lacks permission for the operation.
var ErrForbidden = errors.New("insufficient permissions")

// ErrUserNotFound is returned when the target user does not exist.
var ErrUserNotFound = errors.New("user not found")

// ErrUnsupportedType is returned when an uploaded file is not a PDF.
var ErrUnsupportedType = errors.New("unsupported file type; PDF is required")

// ErrTooLarge is returned when an uploaded file exceeds the size limit.
var ErrTooLarge = errors.New("uploaded file exceeds the configured size limit")

// ValidationError describes a request validation failure.
type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

// userResolver resolves a target user's existence and church.
type userResolver interface {
	ChurchIDOf(ctx context.Context, userID string) (churchID string, ok bool, err error)
}

// Service holds certificate business logic, authorization, and file handling.
type Service struct {
	repo     *Repository
	storage  *Storage
	users    userResolver
	maxBytes int64
}

// NewService creates a certificate service.
func NewService(repo *Repository, storage *Storage, users userResolver, maxBytes int64) *Service {
	return &Service{repo: repo, storage: storage, users: users, maxBytes: maxBytes}
}

// MaxBytes returns the configured maximum upload size in bytes.
func (s *Service) MaxBytes() int64 { return s.maxBytes }

// List returns a page of certificates for a user, after an access check.
func (s *Service) List(ctx context.Context, id auth.Identity, targetUserID string, typ Type, limit, offset int) ([]Certificate, int, error) {
	if typ != "" && !ValidType(typ) {
		return nil, 0, invalid("invalid type filter")
	}
	if err := s.authorizeUserAccess(ctx, id, targetUserID); err != nil {
		return nil, 0, err
	}
	return s.repo.ListByUser(ctx, targetUserID, typ, limit, offset)
}

// Upload validates and stores a certificate file plus its metadata for the
// target user. On a metadata-write failure the stored file is removed.
func (s *Service) Upload(ctx context.Context, id auth.Identity, targetUserID string, meta UploadMetadata, originalName, declaredMime string, size int64, content io.Reader) (*Certificate, error) {
	if err := s.authorizeUserAccess(ctx, id, targetUserID); err != nil {
		return nil, err
	}

	if !ValidType(meta.Type) {
		return nil, invalid("a valid type is required")
	}
	if strings.TrimSpace(meta.CertificateNumber) == "" {
		return nil, invalid("certificateNumber is required")
	}
	if strings.TrimSpace(meta.FullName) == "" {
		return nil, invalid("fullName is required")
	}
	if !isPDF(originalName, declaredMime) {
		return nil, ErrUnsupportedType
	}
	if s.maxBytes > 0 && size > s.maxBytes {
		return nil, ErrTooLarge
	}

	key := randomKey() + ".pdf"
	written, err := s.storage.Save(key, io.LimitReader(content, s.limitReaderMax()))
	if err != nil {
		return nil, err
	}
	// Enforce the size limit even when the declared size was unreliable.
	if s.maxBytes > 0 && written > s.maxBytes {
		_ = s.storage.Remove(key)
		return nil, ErrTooLarge
	}

	notes := nullify(meta.Notes)
	c := &Certificate{
		UserID:            targetUserID,
		UploadedByUserID:  id.UserID,
		Type:              meta.Type,
		CertificateNumber: meta.CertificateNumber,
		FullName:          meta.FullName,
		IssueDate:         meta.IssueDate,
		FileName:          sanitizeName(originalName),
		StoredPath:        key,
		MimeType:          "application/pdf",
		FileSize:          written,
		Notes:             notes,
	}

	out, err := s.repo.Create(ctx, c)
	if err != nil {
		// Roll back the stored file if metadata persistence fails.
		_ = s.storage.Remove(key)
		return nil, err
	}
	return out, nil
}

// Download returns the certificate metadata and an open reader for its file,
// after an access check. The caller must close the reader.
func (s *Service) Download(ctx context.Context, id auth.Identity, certificateID string) (*Certificate, io.ReadCloser, error) {
	c, err := s.repo.GetByID(ctx, certificateID)
	if err != nil {
		return nil, nil, err
	}
	if err := s.authorizeUserAccess(ctx, id, c.UserID); err != nil {
		return nil, nil, err
	}
	rc, err := s.storage.Open(c.StoredPath)
	if err != nil {
		return nil, nil, err
	}
	return c, rc, nil
}

// authorizeUserAccess permits the target user themselves, a super_admin, or a
// church_admin whose church matches the target user's church.
func (s *Service) authorizeUserAccess(ctx context.Context, id auth.Identity, targetUserID string) error {
	// A user may always access their own certificates (confirm they exist).
	if id.UserID == targetUserID {
		return nil
	}
	if id.Role.IsSuperAdmin() {
		if err := s.ensureUser(ctx, targetUserID); err != nil {
			return err
		}
		return nil
	}
	if id.Role == auth.RoleChurchAdmin {
		targetChurch, ok, err := s.users.ChurchIDOf(ctx, targetUserID)
		if err != nil {
			return err
		}
		if !ok {
			return ErrUserNotFound
		}
		if id.ChurchID != "" && id.ChurchID == targetChurch {
			return nil
		}
	}
	return ErrForbidden
}

func (s *Service) ensureUser(ctx context.Context, userID string) error {
	_, ok, err := s.users.ChurchIDOf(ctx, userID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrUserNotFound
	}
	return nil
}

// limitReaderMax returns the byte ceiling for streaming uploads. When a max is
// configured we read one extra byte so oversize files can be detected.
func (s *Service) limitReaderMax() int64 {
	if s.maxBytes <= 0 {
		return 1 << 62
	}
	return s.maxBytes + 1
}

// isPDF reports whether the declared mime type or filename indicates a PDF.
func isPDF(name, mime string) bool {
	if strings.EqualFold(strings.TrimSpace(mime), "application/pdf") {
		return true
	}
	return strings.HasSuffix(strings.ToLower(strings.TrimSpace(name)), ".pdf")
}

// sanitizeName returns a safe display filename, defaulting when empty.
func sanitizeName(name string) string {
	name = strings.TrimSpace(name)
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, "\\", "_")
	if name == "" {
		return "certificate.pdf"
	}
	return name
}

func nullify(s string) *string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return &s
}

// randomKey returns a 32-character hex string for use as an opaque storage key.
func randomKey() string {
	var b [16]byte
	// crypto/rand.Read never returns a short read on success.
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}
