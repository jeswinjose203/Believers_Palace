package media

import (
	"errors"
	"io"
	"net/http"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/httpx"
)

// multipartMaxMemory bounds the in-memory portion of multipart parsing; larger
// parts spill to temporary files managed by the standard library.
const multipartMaxMemory = 8 << 20 // 8 MiB

// Handler handles image upload and download HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates a media handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// UploadRoutes returns the authenticated upload route, mounted under
// /media/upload.
func (h *Handler) UploadRoutes() chi.Router {
	r := chi.NewRouter()
	r.Post("/", h.upload)
	return r
}

// PublicRoutes returns the unauthenticated download route, mounted under
// /media. Images are served publicly so clients can load them directly via a
// URL (e.g. an <img> src or Flutter NetworkImage).
func (h *Handler) PublicRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/{key}", h.download)
	return r
}

func (h *Handler) upload(w http.ResponseWriter, r *http.Request) {
	// Cap the request body to the configured max (plus headroom for the
	// multipart envelope) before parsing.
	if max := h.svc.MaxBytes(); max > 0 {
		r.Body = http.MaxBytesReader(w, r.Body, max+multipartMaxMemory)
	}

	if err := r.ParseMultipartForm(multipartMaxMemory); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid multipart form", "bad_request")
		return
	}
	defer func() {
		if r.MultipartForm != nil {
			_ = r.MultipartForm.RemoveAll()
		}
	}()

	file, header, err := r.FormFile("file")
	if err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "file is required", "bad_request")
		return
	}
	defer file.Close()

	declaredMime := header.Header.Get("Content-Type")
	res, err := h.svc.Upload(header.Filename, declaredMime, header.Size, file)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, res)
}

func (h *Handler) download(w http.ResponseWriter, r *http.Request) {
	key := chi.URLParam(r, "key")

	f, err := h.svc.Open(key)
	if err != nil {
		httpx.ErrorCode(w, http.StatusNotFound, "image not found", "not_found")
		return
	}
	defer f.Reader.Close()

	w.Header().Set("Content-Type", f.MimeType)
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, f.Reader)
}

func (h *Handler) writeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrUnsupportedType):
		httpx.ErrorCode(w, http.StatusUnsupportedMediaType, "unsupported file type; an image (jpeg, png, webp, gif) is required", "unsupported_media_type")
	case errors.Is(err, ErrTooLarge):
		httpx.ErrorCode(w, http.StatusRequestEntityTooLarge, "uploaded image exceeds the configured size limit", "payload_too_large")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
