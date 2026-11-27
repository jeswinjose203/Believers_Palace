package catechism

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
	"believers_palace/internal/media"
)

const materialMultipartMemory = 8 << 20

type classMaterial struct {
	ID          string    `json:"id"`
	ClassID     string    `json:"classId"`
	Kind        string    `json:"kind"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	FileName    *string   `json:"fileName,omitempty"`
	DownloadURL string    `json:"downloadUrl,omitempty"`
	ExternalURL *string   `json:"externalUrl,omitempty"`
	CreatedAt   time.Time `json:"createdAt"`
	StorageKey  *string   `json:"-"`
	MimeType    *string   `json:"-"`
}

func (h *Handler) SetMaterialStorage(storage *media.Storage, maxBytes int64) {
	h.materialStorage = storage
	h.materialMaxBytes = maxBytes
}

func (h *Handler) classMaterialAccess(r *http.Request) (*Class, bool, bool, error) {
	cls, admin, teacher, err := h.workspaceAccess(r)
	if err != nil {
		return nil, false, false, err
	}
	if admin || teacher {
		return cls, admin, teacher, nil
	}
	id := auth.MustFromContext(r.Context())
	var enrolled bool
	err = h.svc.repo.pool.QueryRow(r.Context(), `SELECT EXISTS(
		SELECT 1 FROM catechism_enrollments WHERE class_id=$1 AND guardian_id=$2
		AND status IN ('approved','completed'))`, cls.ID, id.UserID).Scan(&enrolled)
	if err != nil {
		return nil, false, false, err
	}
	if !enrolled {
		return nil, false, false, ErrForbidden
	}
	return cls, false, false, nil
}

func (h *Handler) listMaterials(w http.ResponseWriter, r *http.Request) {
	cls, _, _, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	rows, err := h.svc.repo.pool.Query(r.Context(), `SELECT m.id,m.class_id,m.kind,m.title,m.description,
		m.file_name,m.external_url,m.created_at,m.storage_key,m.mime_type
		FROM catechism_materials m WHERE m.class_id=$1
		ORDER BY m.created_at DESC,m.id DESC`, cls.ID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	defer rows.Close()
	items := []classMaterial{}
	for rows.Next() {
		var item classMaterial
		if err := rows.Scan(&item.ID, &item.ClassID, &item.Kind, &item.Title, &item.Description,
			&item.FileName, &item.ExternalURL, &item.CreatedAt, &item.StorageKey, &item.MimeType); err != nil {
			h.writeError(w, err)
			return
		}
		if item.Kind == "note" {
			item.DownloadURL = fmt.Sprintf("/catechism-classes/%s/materials/%s/download", cls.ID, item.ID)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"materials": items})
}

func (h *Handler) uploadNote(w http.ResponseWriter, r *http.Request) {
	cls, admin, teacher, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if !admin && !teacher {
		h.writeError(w, ErrForbidden)
		return
	}
	if h.materialStorage == nil {
		httpx.ErrorCode(w, http.StatusServiceUnavailable, "class materials are unavailable", "materials_unavailable")
		return
	}
	maxBytes := h.materialMaxBytes
	if maxBytes < 1 {
		maxBytes = 10 << 20
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes+materialMultipartMemory)
	if err := r.ParseMultipartForm(materialMultipartMemory); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid multipart form", "bad_request")
		return
	}
	defer func() {
		if r.MultipartForm != nil {
			_ = r.MultipartForm.RemoveAll()
		}
	}()
	title := strings.TrimSpace(r.FormValue("title"))
	description := strings.TrimSpace(r.FormValue("description"))
	if title == "" || len(title) > 200 || len(description) > 20000 {
		httpx.ErrorCode(w, http.StatusBadRequest, "enter a title and description within the length limits", "bad_request")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "a PDF note file is required", "bad_request")
		return
	}
	defer file.Close()
	if header.Size > maxBytes || strings.ToLower(filepath.Ext(header.Filename)) != ".pdf" {
		httpx.ErrorCode(w, http.StatusUnsupportedMediaType, "upload a PDF smaller than the configured limit", "unsupported_media_type")
		return
	}
	data, err := io.ReadAll(io.LimitReader(file, maxBytes+1))
	if err != nil {
		h.writeError(w, err)
		return
	}
	if int64(len(data)) > maxBytes || !strings.HasPrefix(http.DetectContentType(data), "application/pdf") && !(len(data) >= 5 && string(data[:5]) == "%PDF-") {
		httpx.ErrorCode(w, http.StatusUnsupportedMediaType, "the note file is not a valid PDF", "unsupported_media_type")
		return
	}
	var keyBytes [16]byte
	if _, err := rand.Read(keyBytes[:]); err != nil {
		h.writeError(w, err)
		return
	}
	key := hex.EncodeToString(keyBytes[:]) + ".pdf"
	if _, err := h.materialStorage.Save(key, bytes.NewReader(data)); err != nil {
		h.writeError(w, err)
		return
	}
	id := auth.MustFromContext(r.Context())
	var item classMaterial
	err = h.svc.repo.pool.QueryRow(r.Context(), `INSERT INTO catechism_materials
		(class_id,author_id,kind,title,description,storage_key,file_name,mime_type)
		VALUES ($1,$2,'note',$3,$4,$5,$6,'application/pdf')
		RETURNING id,class_id,kind,title,description,file_name,external_url,created_at,storage_key,mime_type`,
		cls.ID, id.UserID, title, description, key, filepath.Base(header.Filename)).Scan(
		&item.ID, &item.ClassID, &item.Kind, &item.Title, &item.Description,
		&item.FileName, &item.ExternalURL, &item.CreatedAt, &item.StorageKey, &item.MimeType)
	if err != nil {
		_ = h.materialStorage.Remove(key)
		h.writeError(w, err)
		return
	}
	item.DownloadURL = fmt.Sprintf("/catechism-classes/%s/materials/%s/download", cls.ID, item.ID)
	httpx.JSON(w, http.StatusCreated, item)
}

func (h *Handler) publishVideo(w http.ResponseWriter, r *http.Request) {
	cls, admin, teacher, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if !admin && !teacher {
		h.writeError(w, ErrForbidden)
		return
	}
	var in struct {
		Title       string `json:"title"`
		Description string `json:"description"`
		URL         string `json:"url"`
	}
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	title := strings.TrimSpace(in.Title)
	link, err := url.Parse(strings.TrimSpace(in.URL))
	if title == "" || len(title) > 200 || len(in.Description) > 20000 || err != nil || link.Scheme != "https" || link.Host == "" || link.User != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "enter a title and a valid HTTPS video link", "bad_request")
		return
	}
	id := auth.MustFromContext(r.Context())
	var item classMaterial
	err = h.svc.repo.pool.QueryRow(r.Context(), `INSERT INTO catechism_materials
		(class_id,author_id,kind,title,description,external_url)
		VALUES ($1,$2,'video',$3,$4,$5)
		RETURNING id,class_id,kind,title,description,file_name,external_url,created_at,storage_key,mime_type`,
		cls.ID, id.UserID, title, strings.TrimSpace(in.Description), link.String()).Scan(
		&item.ID, &item.ClassID, &item.Kind, &item.Title, &item.Description,
		&item.FileName, &item.ExternalURL, &item.CreatedAt, &item.StorageKey, &item.MimeType)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, item)
}

func (h *Handler) deleteMaterial(w http.ResponseWriter, r *http.Request) {
	cls, admin, teacher, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if !admin && !teacher {
		h.writeError(w, ErrForbidden)
		return
	}
	var key *string
	err = h.svc.repo.pool.QueryRow(r.Context(), `DELETE FROM catechism_materials WHERE id=$1 AND class_id=$2 RETURNING storage_key`, chi.URLParam(r, "materialId"), cls.ID).Scan(&key)
	if errors.Is(err, pgx.ErrNoRows) {
		h.writeError(w, ErrNotFound)
		return
	}
	if err != nil {
		h.writeError(w, err)
		return
	}
	if key != nil && h.materialStorage != nil {
		_ = h.materialStorage.Remove(*key)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) downloadMaterial(w http.ResponseWriter, r *http.Request) {
	cls, _, _, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if h.materialStorage == nil {
		h.writeError(w, ErrNotFound)
		return
	}
	var item classMaterial
	err = h.svc.repo.pool.QueryRow(r.Context(), `SELECT id,class_id,kind,title,description,file_name,external_url,created_at,storage_key,mime_type
		FROM catechism_materials WHERE id=$1 AND class_id=$2 AND kind='note'`, chi.URLParam(r, "materialId"), cls.ID).Scan(
		&item.ID, &item.ClassID, &item.Kind, &item.Title, &item.Description,
		&item.FileName, &item.ExternalURL, &item.CreatedAt, &item.StorageKey, &item.MimeType)
	if errors.Is(err, pgx.ErrNoRows) {
		h.writeError(w, ErrNotFound)
		return
	}
	if err != nil || item.StorageKey == nil {
		if err == nil {
			err = ErrNotFound
		}
		h.writeError(w, err)
		return
	}
	file, err := h.materialStorage.Open(*item.StorageKey)
	if err != nil {
		h.writeError(w, ErrNotFound)
		return
	}
	defer file.Close()
	mimeType := "application/pdf"
	if item.MimeType != nil {
		mimeType = *item.MimeType
	}
	w.Header().Set("Content-Type", mimeType)
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": filepath.Base(*item.FileName)}))
	w.Header().Set("Cache-Control", "private, no-store")
	http.ServeContent(w, r, filepath.Base(*item.FileName), item.CreatedAt, file)
}
