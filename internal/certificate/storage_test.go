package certificate

import (
	"io"
	"strings"
	"testing"
)

func TestValidType(t *testing.T) {
	if !ValidType(TypeBaptism) || ValidType("bogus") {
		t.Error("ValidType failed")
	}
}

func TestIsPDF(t *testing.T) {
	cases := []struct {
		name, mime string
		want       bool
	}{
		{"x.pdf", "application/pdf", true},
		{"x.pdf", "", true},
		{"x", "application/pdf", true},
		{"x.txt", "text/plain", false},
		{"x", "", false},
	}
	for _, c := range cases {
		if got := isPDF(c.name, c.mime); got != c.want {
			t.Errorf("isPDF(%q,%q) = %v, want %v", c.name, c.mime, got, c.want)
		}
	}
}

func TestStorageRoundtripAndTraversal(t *testing.T) {
	s, err := NewStorage(t.TempDir())
	if err != nil {
		t.Fatalf("NewStorage: %v", err)
	}

	// Path traversal keys must be rejected.
	for _, bad := range []string{"../escape", "a/b", "..", ".", ""} {
		if _, err := s.Save(bad, strings.NewReader("x")); err == nil {
			t.Errorf("Save(%q) expected error", bad)
		}
	}

	// Valid roundtrip.
	const key = "abc123.pdf"
	n, err := s.Save(key, strings.NewReader("%PDF-1.7 data"))
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	if n != int64(len("%PDF-1.7 data")) {
		t.Errorf("Save wrote %d bytes", n)
	}

	rc, err := s.Open(key)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer rc.Close()
	got, _ := io.ReadAll(rc)
	if string(got) != "%PDF-1.7 data" {
		t.Errorf("Open returned %q", got)
	}

	if err := s.Remove(key); err != nil {
		t.Errorf("Remove: %v", err)
	}
	// Removing a missing file is not an error.
	if err := s.Remove(key); err != nil {
		t.Errorf("Remove(missing): %v", err)
	}
}

func TestSanitizeName(t *testing.T) {
	cases := map[string]string{
		"":           "certificate.pdf",
		"a/b/c.pdf":  "a_b_c.pdf",
		"normal.pdf": "normal.pdf",
		`a\b.pdf`:    "a_b.pdf",
	}
	for in, want := range cases {
		if got := sanitizeName(in); got != want {
			t.Errorf("sanitizeName(%q) = %q, want %q", in, got, want)
		}
	}
}
