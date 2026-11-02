package media

import (
	"strings"
	"testing"
)

func TestResolveImageType(t *testing.T) {
	cases := []struct {
		name       string
		fileName   string
		mime       string
		wantOK     bool
		wantMime   string
		wantExtDot string
	}{
		{"jpeg by mime", "x", "image/jpeg", true, "image/jpeg", ".jpg"},
		{"png by mime", "x", "image/png", true, "image/png", ".png"},
		{"webp by mime", "x", "image/webp", true, "image/webp", ".webp"},
		{"gif by mime", "x", "image/gif", true, "image/gif", ".gif"},
		{"jpg by extension", "photo.JPG", "application/octet-stream", true, "image/jpeg", ".jpg"},
		{"jpeg ext maps to jpg", "photo.jpeg", "", true, "image/jpeg", ".jpg"},
		{"unsupported pdf", "doc.pdf", "application/pdf", false, "", ""},
		{"unsupported no ext", "noext", "", false, "", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			mime, ext, ok := resolveImageType(c.fileName, c.mime)
			if ok != c.wantOK {
				t.Fatalf("ok = %v, want %v", ok, c.wantOK)
			}
			if !ok {
				return
			}
			if mime != c.wantMime {
				t.Errorf("mime = %q, want %q", mime, c.wantMime)
			}
			if ext != c.wantExtDot {
				t.Errorf("ext = %q, want %q", ext, c.wantExtDot)
			}
		})
	}
}

func TestServiceUploadAndOpen(t *testing.T) {
	st, err := NewStorage(t.TempDir())
	if err != nil {
		t.Fatalf("NewStorage: %v", err)
	}
	svc := NewService(st, "http://localhost:8080/", 1024) // trailing slash trimmed

	data := "fake-png-bytes"
	res, err := svc.Upload("logo.png", "image/png", int64(len(data)), strings.NewReader(data))
	if err != nil {
		t.Fatalf("Upload: %v", err)
	}
	if res.MimeType != "image/png" {
		t.Errorf("MimeType = %q, want image/png", res.MimeType)
	}
	if res.FileSize != int64(len(data)) {
		t.Errorf("FileSize = %d, want %d", res.FileSize, len(data))
	}
	if !strings.HasPrefix(res.URL, "http://localhost:8080/api/media/") {
		t.Errorf("URL = %q, missing expected prefix", res.URL)
	}
	if !strings.HasSuffix(res.URL, ".png") {
		t.Errorf("URL = %q, want .png suffix", res.URL)
	}

	// Round-trip: open the stored file by its key.
	f, err := svc.Open(res.FileName)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer f.Reader.Close()
	if f.MimeType != "image/png" {
		t.Errorf("Open MimeType = %q, want image/png", f.MimeType)
	}
}

func TestServiceUploadRejectsUnsupported(t *testing.T) {
	st, _ := NewStorage(t.TempDir())
	svc := NewService(st, "http://localhost:8080", 1024)

	_, err := svc.Upload("doc.pdf", "application/pdf", 10, strings.NewReader("pdf"))
	if err != ErrUnsupportedType {
		t.Fatalf("err = %v, want ErrUnsupportedType", err)
	}
}

func TestServiceUploadRejectsTooLarge(t *testing.T) {
	st, _ := NewStorage(t.TempDir())
	svc := NewService(st, "http://localhost:8080", 4)

	_, err := svc.Upload("big.png", "image/png", 100, strings.NewReader("too-big"))
	if err != ErrTooLarge {
		t.Fatalf("err = %v, want ErrTooLarge (declared size)", err)
	}

	// Even if the declared size lies, the written-bytes check must catch it.
	_, err = svc.Upload("big.png", "image/png", 1, strings.NewReader("way-too-big"))
	if err != ErrTooLarge {
		t.Fatalf("err = %v, want ErrTooLarge (written size)", err)
	}
}

func TestStorageRejectsPathTraversal(t *testing.T) {
	st, _ := NewStorage(t.TempDir())
	for _, key := range []string{"../escape.png", "sub/dir.png", "..", ".", ""} {
		if _, err := st.Open(key); err == nil {
			t.Errorf("Open(%q) succeeded, want error", key)
		}
	}
}
