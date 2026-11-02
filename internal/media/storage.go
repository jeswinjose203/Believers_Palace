package media

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// Storage persists uploaded image files on the local filesystem.
type Storage struct {
	dir string
}

// NewStorage creates a Storage rooted at dir, creating the directory if needed.
func NewStorage(dir string) (*Storage, error) {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return nil, fmt.Errorf("create media dir: %w", err)
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, fmt.Errorf("resolve media dir: %w", err)
	}
	return &Storage{dir: abs}, nil
}

// Save streams src to a new file named by the given storage key and returns the
// number of bytes written. The key must be a simple base name (no separators).
func (s *Storage) Save(key string, src io.Reader) (int64, error) {
	path, err := s.resolve(key)
	if err != nil {
		return 0, err
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o640)
	if err != nil {
		return 0, fmt.Errorf("create media file: %w", err)
	}
	defer f.Close()

	n, err := io.Copy(f, src)
	if err != nil {
		// Best-effort cleanup of the partial file.
		_ = os.Remove(path)
		return 0, fmt.Errorf("write media file: %w", err)
	}
	return n, nil
}

// Open opens a stored file for reading by its storage key.
func (s *Storage) Open(key string) (io.ReadCloser, error) {
	path, err := s.resolve(key)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open media file: %w", err)
	}
	return f, nil
}

// Remove deletes a stored file by its storage key. A missing file is not an error.
func (s *Storage) Remove(key string) error {
	path, err := s.resolve(key)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove media file: %w", err)
	}
	return nil
}

// resolve validates the key and returns its absolute path within the storage
// directory, rejecting any path traversal.
func (s *Storage) resolve(key string) (string, error) {
	base := filepath.Base(key)
	if base != key || base == "." || base == ".." || base == "" {
		return "", fmt.Errorf("invalid storage key %q", key)
	}
	path := filepath.Join(s.dir, base)
	// Defense in depth: ensure the resolved path stays within the root.
	if filepath.Dir(path) != s.dir {
		return "", fmt.Errorf("invalid storage key %q", key)
	}
	return path, nil
}
