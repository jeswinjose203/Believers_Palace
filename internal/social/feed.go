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
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Username  string    `json:"username"`
	Body      string    `json:"body"`
	MediaKey  *string   `json:"mediaKey"`
	CreatedAt time.Time `json:"createdAt"`
	Likes     int       `json:"likes"`
	Liked     bool      `json:"liked"`
}

const feedPageSize = 24

func (h *Handler) feed(w http.ResponseWriter, r *http.Request) {
	cursor, ok := readCursor(w, r)
	if !ok {
		return
	}
	var at *time.Time
	var id *string
	if cursor.ID != "" {
		at, id = &cursor.At, &cursor.ID
	}
	// Rank each bounded chronological batch. The next cursor is based on the
	// candidate order, so reactions and church changes cannot skip posts.
	rows, err := h.db.Query(r.Context(), `WITH candidates AS MATERIALIZED (
        SELECT * FROM social_posts
        WHERE (created_at,id) < (COALESCE($2::timestamptz,'infinity'),COALESCE($3::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'))
        ORDER BY created_at DESC,id DESC LIMIT $4
    ), numbered AS (
        SELECT *, row_number() OVER (ORDER BY created_at DESC,id DESC) AS position FROM candidates
    )
    SELECT p.id,u.name,u.username,p.body,p.media_key,p.created_at,
           n.likes, EXISTS(SELECT 1 FROM social_likes WHERE post_id=p.id AND user_id=$1),
           p.position
    FROM numbered p
    JOIN users u ON u.id=p.author_id
    JOIN users reader ON reader.id=$1
    CROSS JOIN LATERAL (SELECT count(*) AS likes FROM
        (SELECT 1 FROM social_likes WHERE post_id=p.id LIMIT 201) sample) n
    ORDER BY (p.position=$4), (
        ln(1+n.likes)*0.65
        + CASE WHEN p.church_id=reader.church_id THEN 1.5 ELSE 0 END
        - ln(1+GREATEST(0,EXTRACT(epoch FROM (now()-p.created_at))/3600))*0.9
    ) DESC, p.created_at DESC,p.id DESC`, viewer(r), at, id, feedPageSize+1)
	if err != nil {
		failure(w, err)
		return
	}
	defer rows.Close()
	items := make([]post, 0, feedPageSize)
	var tail pageCursor
	more := false
	for rows.Next() {
		var p post
		var position int
		if err := rows.Scan(&p.ID, &p.Name, &p.Username, &p.Body, &p.MediaKey, &p.CreatedAt, &p.Likes, &p.Liked, &position); err != nil {
			failure(w, err)
			return
		}
		if position > feedPageSize {
			more = true
			continue
		}
		if position == feedPageSize {
			tail = pageCursor{p.CreatedAt, p.ID}
		}
		items = append(items, p)
	}
	if err := rows.Err(); err != nil {
		failure(w, err)
		return
	}
	result := map[string]any{"data": items}
	if more {
		result["nextCursor"] = tail.encode()
	}
	httpx.JSON(w, 200, result)
}

func verificationRequired(w http.ResponseWriter) {
	httpx.ErrorCode(w, 403, "Verify your email and phone number to post.", "post_verification_required")
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
        SELECT id,church_id,(email_verified AND phone_verified) AS verified,
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
	var verified bool
	if err := h.db.QueryRow(r.Context(), `SELECT email_verified AND phone_verified FROM users WHERE id=$1`, viewer(r)).Scan(&verified); err != nil {
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
