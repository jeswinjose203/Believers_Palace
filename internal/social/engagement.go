package social

import (
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"believers_palace/internal/httpx"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

const postColumns = `p.id,u.name,u.username,p.body,p.media_key,p.created_at,
 COALESCE((SELECT sum(total)::bigint FROM social_engagement_counts WHERE post_id=p.id AND kind='like'),0),
 EXISTS(SELECT 1 FROM social_likes WHERE post_id=p.id AND user_id=$1),
 COALESCE((SELECT sum(total)::bigint FROM social_engagement_counts WHERE post_id=p.id AND kind='comment'),0),
 (SELECT recent.username FROM social_likes l JOIN users recent ON recent.id=l.user_id
  WHERE l.post_id=p.id ORDER BY l.created_at DESC,l.user_id DESC LIMIT 1)`

func (h *Handler) scanPost(row pgx.Row) (post, error) {
	var p post
	err := row.Scan(&p.ID, &p.Name, &p.Username, &p.Body, &p.MediaKey, &p.CreatedAt, &p.Likes, &p.Liked, &p.Comments, &p.RecentLiker)
	if err == nil && p.MediaKey != nil {
		p.MediaURL = h.media.CDNURL(*p.MediaKey)
	}
	return p, err
}

func postID(w http.ResponseWriter, r *http.Request) string {
	id := chi.URLParam(r, "id")
	if !validUUID(id) {
		bad(w, "Invalid post.")
		return ""
	}
	return id
}

func (h *Handler) onePost(w http.ResponseWriter, r *http.Request) {
	id := postID(w, r)
	if id == "" {
		return
	}
	p, err := h.scanPost(h.db.QueryRow(r.Context(), `SELECT `+postColumns+`
   FROM social_posts p JOIN users u ON u.id=p.author_id WHERE p.id=$2`, viewer(r), id))
	if err != nil {
		failure(w, err)
		return
	}
	httpx.JSON(w, 200, p)
}

type engagementEntry struct {
	ID        string    `json:"id"`
	Username  string    `json:"username"`
	Body      string    `json:"body,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
}

func (h *Handler) comments(w http.ResponseWriter, r *http.Request) {
	h.engagementPage(w, r, `SELECT c.id,u.username,c.body,c.created_at
 FROM social_comments c JOIN users u ON u.id=c.author_id
 WHERE c.post_id=$1 AND (c.created_at,c.id)<(COALESCE($2::timestamptz,'infinity'),COALESCE($3::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'))
 ORDER BY c.created_at DESC,c.id DESC LIMIT $4`)
}

func (h *Handler) likers(w http.ResponseWriter, r *http.Request) {
	h.engagementPage(w, r, `SELECT l.user_id,u.username,''::text,l.created_at
 FROM social_likes l JOIN users u ON u.id=l.user_id
 WHERE l.post_id=$1 AND (l.created_at,l.user_id)<(COALESCE($2::timestamptz,'infinity'),COALESCE($3::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'))
 ORDER BY l.created_at DESC,l.user_id DESC LIMIT $4`)
}

func (h *Handler) engagementPage(w http.ResponseWriter, r *http.Request, query string) {
	id := postID(w, r)
	if id == "" {
		return
	}
	cursor, ok := readCursor(w, r)
	if !ok {
		return
	}
	var at *time.Time
	var tail *string
	if cursor.ID != "" {
		at, tail = &cursor.At, &cursor.ID
	}
	const limit = 30
	rows, err := h.db.Query(r.Context(), query, id, at, tail, limit+1)
	if err != nil {
		failure(w, err)
		return
	}
	items, err := pgx.CollectRows(rows, pgx.RowToStructByPos[engagementEntry])
	if err != nil {
		failure(w, err)
		return
	}
	result := map[string]any{"data": items}
	if len(items) > limit {
		last := items[limit-1]
		result["data"] = items[:limit]
		result["nextCursor"] = (pageCursor{last.CreatedAt, last.ID}).encode()
	}
	httpx.JSON(w, 200, result)
}

func (h *Handler) comment(w http.ResponseWriter, r *http.Request) {
	id := postID(w, r)
	if id == "" {
		return
	}
	var in struct{ Body, ClientID string }
	if !decode(w, r, &in) {
		return
	}
	body := strings.TrimSpace(in.Body)
	if body == "" || utf8.RuneCountInString(body) > 1000 || strings.ContainsRune(body, 0) || !clientPattern.MatchString(in.ClientID) {
		bad(w, "Enter a comment of up to 1,000 characters.")
		return
	}
	var entry engagementEntry
	err := h.db.QueryRow(r.Context(), `WITH saved AS (
 INSERT INTO social_comments(post_id,author_id,body,client_id) VALUES($1,$2,$3,$4)
 ON CONFLICT(post_id,author_id,client_id) DO UPDATE SET client_id=EXCLUDED.client_id
 RETURNING id,body,created_at,author_id
 ) SELECT s.id,u.username,s.body,s.created_at FROM saved s JOIN users u ON u.id=s.author_id`,
		id, viewer(r), body, in.ClientID).Scan(&entry.ID, &entry.Username, &entry.Body, &entry.CreatedAt)
	if err != nil {
		failure(w, err)
		return
	}
	httpx.JSON(w, 201, entry)
}
