package certificate

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// multipartMaxMemory bounds the in-memory portion of multipart parsing; larger
// parts spill to temporary files managed by the standard library.
const multipartMaxMemory = 8 << 20 // 8 MiB

// Handler handles certificate HTTP requests.
type Handler struct {
	svc *Service
}

// NewHandler creates a certificate handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// UserRoutes returns routes under /users/{userId}/certificates.
func (h *Handler) UserRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.list)
	r.Post("/", h.upload)
	return r
}

// Routes returns routes under /certificates/{certificateId}.
func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Get("/{certificateId}/download", h.download)
	return r
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	userID := chi.URLParam(r, "userId")
	pp := httpx.ParsePageParams(r)
	typ := Type(r.URL.Query().Get("type"))

	items, total, err := h.svc.List(r.Context(), id, userID, typ, pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) upload(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	userID := chi.URLParam(r, "userId")

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

	meta, verr := parseMetadata(r)
	if verr != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, verr.Error(), "bad_request")
		return
	}

	declaredMime := header.Header.Get("Content-Type")
	cert, err := h.svc.Upload(r.Context(), id, userID, meta, header.Filename, declaredMime, header.Size, file)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, cert)
}

func (h *Handler) download(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	certID := chi.URLParam(r, "certificateId")

	cert, rc, err := h.svc.Download(r.Context(), id, certID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	defer rc.Close()

	w.Header().Set("Content-Type", cert.MimeType)
	w.Header().Set("Content-Length", fmt.Sprintf("%d", cert.FileSize))
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", cert.FileName))
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, rc)
}

// parseMetadata extracts and lightly validates the non-file form fields.
func parseMetadata(r *http.Request) (UploadMetadata, error) {
	m := UploadMetadata{
		Type:              Type(r.FormValue("type")),
		CertificateNumber: r.FormValue("certificateNumber"),
		FullName:          r.FormValue("fullName"),
		Notes:             r.FormValue("notes"),
	}
	if v := r.FormValue("issueDate"); v != "" {
		t, err := time.Parse("2006-01-02", v)
		if err != nil {
			return m, errors.New("issueDate must be in YYYY-MM-DD format")
		}
		m.IssueDate = &t
	}
	return m, nil
}

func (h *Handler) writeError(w http.ResponseWriter, err error) {
	var ve *ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.ErrorCode(w, http.StatusBadRequest, ve.Message, "bad_request")
	case errors.Is(err, ErrForbidden):
		httpx.ErrorCode(w, http.StatusForbidden, "insufficient permissions", "forbidden")
	case errors.Is(err, ErrUnsupportedType):
		httpx.ErrorCode(w, http.StatusUnsupportedMediaType, "unsupported file type; PDF is required", "unsupported_media_type")
	case errors.Is(err, ErrTooLarge):
		httpx.ErrorCode(w, http.StatusRequestEntityTooLarge, "uploaded file exceeds the configured size limit", "payload_too_large")
	case errors.Is(err, ErrNumberExists):
		httpx.ErrorCode(w, http.StatusConflict, "certificate number already exists", "conflict")
	case errors.Is(err, ErrUserNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "user not found", "not_found")
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "certificate not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
