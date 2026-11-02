package media

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"strings"
)

// ErrUnsupportedType is returned when an uploaded file is not a supported image.
var ErrUnsupportedType = errors.New("unsupported file type; an image is required")

// ErrTooLarge is returned when an uploaded image exceeds the size limit.
var ErrTooLarge = errors.New("uploaded image exceeds the configured size limit")

// allowedImageTypes maps accepted MIME types to their canonical file extension.
var allowedImageTypes = map[string]string{
	"image/jpeg": ".jpg",
	"image/png":  ".png",
	"image/webp": ".webp",
	"image/gif":  ".gif",
}

// allowedExtensions maps accepted lowercase file extensions to a canonical MIME
// type, used when the declared content type is unreliable.
var allowedExtensions = map[string]string{
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".png":  "image/png",
	".webp": "image/webp",
	".gif":  "image/gif",
}

// UploadResult describes a stored image file.
type UploadResult struct {
	URL      string `json:"url"`
	FileName string `json:"fileName"`
	MimeType string `json:"mimeType"`
	FileSize int64  `json:"fileSize"`
}

// Service holds image upload business logic and file handling.
type Service struct {
	storage  *Storage
	baseURL  string
	maxBytes int64
}

// NewService creates a media service. baseURL is the externally reachable base
// URL of the API (e.g. https://api.example.com) with no trailing slash.
func NewService(storage *Storage, baseURL string, maxBytes int64) *Service {
	return &Service{storage: storage, baseURL: strings.TrimRight(baseURL, "/"), maxBytes: maxBytes}
}

// MaxBytes returns the configured maximum upload size in bytes.
func (s *Service) MaxBytes() int64 { return s.maxBytes }

// Upload validates and stores an image, returning its public URL and metadata.
func (s *Service) Upload(originalName, declaredMime string, size int64, content io.Reader) (*UploadResult, error) {
	mime, ext, ok := resolveImageType(originalName, declaredMime)
	if !ok {
		return nil, ErrUnsupportedType
	}
	if s.maxBytes > 0 && size > s.maxBytes {
		return nil, ErrTooLarge
	}

	key := randomKey() + ext
	written, err := s.storage.Save(key, io.LimitReader(content, s.limitReaderMax()))
	if err != nil {
		return nil, err
	}
	// Enforce the size limit even when the declared size was unreliable.
	if s.maxBytes > 0 && written > s.maxBytes {
		_ = s.storage.Remove(key)
		return nil, ErrTooLarge
	}

	return &UploadResult{
		URL:      s.baseURL + "/api/media/" + key,
		FileName: key,
		MimeType: mime,
		FileSize: written,
	}, nil
}

// StoredFile holds an open reader and content type for a stored image.
type StoredFile struct {
	Reader   io.ReadCloser
	MimeType string
}

// Open returns an open reader for the stored image identified by key, along
// with its content type inferred from the extension.
func (s *Service) Open(key string) (*StoredFile, error) {
	rc, err := s.storage.Open(key)
	if err != nil {
		return nil, err
	}
	mime := "application/octet-stream"
	if ext := lowerExt(key); ext != "" {
		if m, ok := allowedExtensions[ext]; ok {
			mime = m
		}
	}
	return &StoredFile{Reader: rc, MimeType: mime}, nil
}

// limitReaderMax returns the byte ceiling for streaming uploads. When a max is
// configured we read one extra byte so oversize files can be detected.
func (s *Service) limitReaderMax() int64 {
	if s.maxBytes <= 0 {
		return 1 << 62
	}
	return s.maxBytes + 1
}

// resolveImageType determines the canonical MIME type and file extension from
// the declared content type, falling back to the filename extension.
func resolveImageType(name, mime string) (canonicalMime, ext string, ok bool) {
	mime = strings.ToLower(strings.TrimSpace(mime))
	if ext, found := allowedImageTypes[mime]; found {
		return mime, ext, true
	}
	if e := lowerExt(name); e != "" {
		if m, found := allowedExtensions[e]; found {
			return m, allowedImageTypes[m], true
		}
	}
	return "", "", false
}

// lowerExt returns the lowercase file extension (including the dot) of name.
func lowerExt(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	i := strings.LastIndex(name, ".")
	if i < 0 {
		return ""
	}
	return name[i:]
}

// randomKey returns a 32-character hex string for use as an opaque storage key.
func randomKey() string {
	var b [16]byte
	// crypto/rand.Read never returns a short read on success.
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}
