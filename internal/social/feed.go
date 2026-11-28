package social

import (
	"encoding/base64"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"believers_palace/internal/httpx"
	"believers_palace/internal/media"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

type pageCursor struct {
	At time.Time
	ID string
}

func readCursor(w http.ResponseWriter, r *http.Request) (*pageCursor, bool) {
	value := r.URL.Query().Get("cursor")
	if value == "" {
		return &pageCursor{}, true
	}
	if len(value) <= 128 {
		raw, err := base64.RawURLEncoding.DecodeString(value)
		stamp, id, ok := strings.Cut(string(raw), "|")
		at, parseErr := time.Parse(time.RFC3339Nano, stamp)
		if err == nil && ok && parseErr == nil && validUUID(id) {
			return &pageCursor{at, id}, true
		}
	}
	bad(w, "Invalid cursor.")
	return nil, false
}

func (p pageCursor) encode() string {
	return base64.RawURLEncoding.EncodeToString([]byte(p.At.UTC().Format(time.RFC3339Nano) + "|" + p.ID))
}

type post struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Username    string    `json:"username"`
	Body        string    `json:"body"`
	MediaKey    *string   `json:"mediaKey"`
	MediaURL    string    `json:"mediaUrl,omitempty"`
	CreatedAt   time.Time `json:"createdAt"`
	Likes       int64     `json:"likes"`
	Comments    int64     `json:"comments"`
	RecentLiker *string   `json:"recentLiker,omitempty"`
	Liked       bool      `json:"liked"`
}

func verificationRequired(w http.ResponseWriter) {
	httpx.ErrorCode(w, 403, "Verify your phone number to post.", "post_verification_required")
}

func (h *Handler) myPosts(w http.ResponseWriter, r *http.Request) {
	cursor, ok := readCursor(w, r)
	if !ok {
		return
	}
	var at *time.Time
	var id *string
	if cursor.ID != "" {
		at, id = &cursor.At, &cursor.ID
	}
	rows, err := h.db.Query(r.Context(), `SELECT `+postColumns+`
		FROM social_posts p JOIN users u ON u.id=p.author_id
		WHERE p.author_id=$1 AND ($2::timestamptz IS NULL OR (p.created_at,p.id)<($2,$3::uuid))
		ORDER BY p.created_at DESC,p.id DESC LIMIT $4`, viewer(r), at, id, feedPageSize+1)
	if err != nil {
		failure(w, err)
		return
	}
	items, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (post, error) {
		return h.scanPost(row)
	})
	if err != nil {
		failure(w, err)
		return
	}
	result := map[string]any{"data": items}
	if len(items) > feedPageSize {
		last := items[feedPageSize-1]
		result["data"] = items[:feedPageSize]
		result["nextCursor"] = (pageCursor{last.CreatedAt, last.ID}).encode()
	}
	httpx.JSON(w, 200, result)
}

func (h *Handler) editPost(w http.ResponseWriter, r *http.Request) {
	id := postID(w, r)
	if id == "" {
		return
	}
	var in struct{ Body, MediaKey string }
	if !decode(w, r, &in) {
		return
	}
	body := strings.TrimSpace(in.Body)
	if utf8.RuneCountInString(body) > 4000 || (body == "" && in.MediaKey == "") ||
		(in.MediaKey != "" && !mediaPattern.MatchString(in.MediaKey)) {
		bad(w, "Enter up to 4,000 characters or attach an image or video.")
		return
	}
	var updated string
	err := h.db.QueryRow(r.Context(), `UPDATE social_posts SET body=$3,media_key=NULLIF($4,'')
		WHERE id=$1 AND author_id=$2 AND ($4='' OR media_key=$4 OR EXISTS(
			SELECT 1 FROM social_media WHERE key=$4 AND owner_id=$2))
		RETURNING id`, id, viewer(r), body, in.MediaKey).Scan(&updated)
	if err != nil {
		failure(w, err)
		return
	}
	changes := post{Body: body}
	if in.MediaKey != "" {
		changes.MediaKey = &in.MediaKey
		changes.MediaURL = h.media.CDNURL(in.MediaKey)
	}
	httpx.JSON(w, 200, map[string]any{
		"id": updated, "body": changes.Body, "mediaKey": changes.MediaKey, "mediaUrl": changes.MediaURL,
	})
}

func (h *Handler) deletePost(w http.ResponseWriter, r *http.Request) {
	id := postID(w, r)
	if id == "" {
		return
	}
	result, err := h.db.Exec(r.Context(), `DELETE FROM social_posts WHERE id=$1 AND author_id=$2`, id, viewer(r))
	if err != nil {
		failure(w, err)
		return
	}
	if result.RowsAffected() == 0 {
		failure(w, pgx.ErrNoRows)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) createPost(w http.ResponseWriter, r *http.Request) {
	var in struct{ Body, MediaKey, ClientID string }
	if !decode(w, r, &in) {
		return
	}
	body := strings.TrimSpace(in.Body)
	if utf8.RuneCountInString(body) > 4000 || (body == "" && in.MediaKey == "") ||
		(in.MediaKey != "" && !mediaPattern.MatchString(in.MediaKey)) || !clientPattern.MatchString(in.ClientID) {
		bad(w, "Enter up to 4,000 characters or attach an image or video.")
		return
	}
	var verified, owns bool
	var id *string
	err := h.db.QueryRow(r.Context(), `WITH account AS (
        SELECT id,church_id,phone_verified AS verified,
            ($3='' OR EXISTS(SELECT 1 FROM social_media WHERE key=$3 AND owner_id=$1)) AS owns
        FROM users WHERE id=$1
    ), inserted AS (
        INSERT INTO social_posts(author_id,church_id,body,media_key,client_id)
        SELECT id,church_id,$2,NULLIF($3,''),$4 FROM account WHERE verified AND owns
        ON CONFLICT (author_id,client_id) DO UPDATE SET client_id=EXCLUDED.client_id RETURNING id
    )
    SELECT verified,owns,(SELECT id FROM inserted) FROM account`, viewer(r), body, in.MediaKey, in.ClientID).Scan(&verified, &owns, &id)
	switch {
	case err != nil:
		failure(w, err)
	case !verified:
		verificationRequired(w)
	case !owns:
		bad(w, "Upload the attachment before posting.")
	default:
		httpx.JSON(w, 201, map[string]any{"id": id})
	}
}

func (h *Handler) like(w http.ResponseWriter, r *http.Request) {
	h.react(w, r, `INSERT INTO social_likes(post_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, true)
}
func (h *Handler) unlike(w http.ResponseWriter, r *http.Request) {
	h.react(w, r, `DELETE FROM social_likes WHERE post_id=$1 AND user_id=$2`, false)
}

func (h *Handler) react(w http.ResponseWriter, r *http.Request, query string, liked bool) {
	id := chi.URLParam(r, "id")
	if !validUUID(id) {
		bad(w, "Invalid post.")
		return
	}
	if _, err := h.db.Exec(r.Context(), query, id, viewer(r)); err != nil {
		failure(w, err)
		return
	}
	httpx.JSON(w, 200, map[string]bool{"liked": liked})
}

func (h *Handler) upload(w http.ResponseWriter, r *http.Request) {
	select {
	case h.uploadSlots <- struct{}{}:
		defer func() { <-h.uploadSlots }()
	default:
		w.Header().Set("Retry-After", "2")
		httpx.ErrorCode(w, 503, "Upload capacity is busy. Try again shortly.", "upload_busy")
		return
	}
	var verified bool
	if err := h.db.QueryRow(r.Context(), `SELECT phone_verified FROM users WHERE id=$1`, viewer(r)).Scan(&verified); err != nil {
		failure(w, err)
		return
	}
	if !verified {
		verificationRequired(w)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, media.SocialMaxBytes+(64<<10))
	parts, err := r.MultipartReader()
	if err != nil {
		bad(w, "Expected a multipart attachment.")
		return
	}
	part, err := parts.NextPart()
	if err != nil || part.FormName() != "file" || part.FileName() == "" {
		bad(w, "An attachment is required.")
		return
	}
	result, err := h.media.UploadSocial(part)
	switch {
	case errors.Is(err, media.ErrUnsupportedType):
		httpx.ErrorCode(w, 415, "Choose a JPEG, PNG, GIF, WebP, MP4, or WebM file.", "unsupported_media_type")
	case errors.Is(err, media.ErrTooLarge):
		httpx.ErrorCode(w, 413, "Attachments can be up to 25 MB.", "payload_too_large")
	case err != nil:
		failure(w, err)
	default:
		if _, err = h.db.Exec(r.Context(), `INSERT INTO social_media(key,owner_id) VALUES($1,$2)`, result.FileName, viewer(r)); err != nil {
			h.media.Remove(result.FileName)
			failure(w, err)
			return
		}
		httpx.JSON(w, 201, result)
	}
}
