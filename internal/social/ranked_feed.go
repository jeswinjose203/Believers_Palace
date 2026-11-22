package social

import (
	"encoding/base64"
	"encoding/binary"
	"math"
	"net/http"
	"sort"
	"time"

	"believers_palace/internal/httpx"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

const (
	feedPageSize     = 24
	feedWindowSize   = 120
	feedCursorHeader = 27
	feedAffinitySize = 24
)

type rankedCursor struct {
	before   time.Time
	tail     pgtype.UUID
	pending  []pgtype.UUID
	featured []pgtype.UUID
	more     bool
}

func (c rankedCursor) encode() string {
	data := make([]byte, feedCursorHeader, feedCursorHeader+16*(len(c.pending)+len(c.featured)))
	data[0] = 2
	data[26] = byte(len(c.featured))
	if c.more {
		data[1] = 1
	}
	binary.BigEndian.PutUint64(data[2:10], uint64(c.before.UnixMicro()))
	copy(data[10:26], c.tail.Bytes[:])
	for _, id := range append(append([]pgtype.UUID(nil), c.featured...), c.pending...) {
		data = append(data, id.Bytes[:]...)
	}
	return base64.RawURLEncoding.EncodeToString(data)
}

func decodeRankedCursor(value string) (rankedCursor, bool) {
	if value == "" {
		return rankedCursor{more: true}, true
	}
	if len(value) > base64.RawURLEncoding.EncodedLen(feedCursorHeader+16*(feedWindowSize+2*feedAffinitySize)) {
		return rankedCursor{}, false
	}
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil || len(data) < feedCursorHeader || (len(data)-feedCursorHeader)%16 != 0 || data[0] != 2 || data[1] > 1 {
		return rankedCursor{}, false
	}
	c := rankedCursor{
		before: time.UnixMicro(int64(binary.BigEndian.Uint64(data[2:10]))).UTC(),
		tail:   pgtype.UUID{Bytes: [16]byte(data[10:26]), Valid: true},
		more:   data[1] == 1,
	}
	featuredCount := int(data[26])
	ids := data[feedCursorHeader:]
	if featuredCount > feedAffinitySize || featuredCount > len(ids)/16 ||
		len(ids)/16-featuredCount > feedWindowSize+feedAffinitySize {
		return rankedCursor{}, false
	}
	for i := 0; len(ids) > 0; i++ {
		id := pgtype.UUID{Bytes: [16]byte(ids[:16]), Valid: true}
		ids = ids[16:]
		if i < featuredCount {
			c.featured = append(c.featured, id)
		} else {
			c.pending = append(c.pending, id)
		}
	}
	return c, true
}

type candidate struct {
	id, author      pgtype.UUID
	at              time.Time
	likes, affinity int
	liked           bool
	featured        bool
}

func rankCandidates(items []candidate, now time.Time) []pgtype.UUID {
	type scored struct {
		candidate
		score float64
	}
	scores := make([]scored, 0, len(items))
	for _, p := range items {
		age := math.Max(0, now.Sub(p.at).Hours())
		// Recency and dampened social proof work for anonymous interests. Author
		// affinity uses the reader's recent likes and fades as the post ages.
		freshness := 2.6*math.Exp(-age/18) + 0.9*math.Exp(-age/96)
		popularity := 0.72 * math.Log1p(float64(p.likes)) * math.Exp(-age/72)
		affinity := 0.85 * math.Log1p(float64(p.affinity)) * math.Exp(-age/96)
		exploration := 0.0
		if p.likes < 3 {
			exploration = 0.5 * math.Exp(-age/10)
		}
		alreadyLiked := 0.0
		if p.liked {
			alreadyLiked = 0.8
		}
		scores = append(scores, scored{p, freshness + popularity + affinity + exploration - alreadyLiked})
	}
	sort.SliceStable(scores, func(i, j int) bool { return scores[i].score > scores[j].score })
	ids := make([]pgtype.UUID, 0, len(scores))
	for len(scores) > 0 {
		perAuthor := make(map[pgtype.UUID]int)
		for i := 0; i < feedPageSize && len(scores) > 0; i++ {
			best := 0
			bestScore := math.Inf(-1)
			for j, s := range scores {
				adjusted := s.score - 1.1*float64(perAuthor[s.author])
				if adjusted > bestScore {
					best, bestScore = j, adjusted
				}
			}
			selected := scores[best]
			perAuthor[selected.author]++
			ids = append(ids, selected.id)
			scores = append(scores[:best], scores[best+1:]...)
		}
	}
	return ids
}

func (h *Handler) feed(w http.ResponseWriter, r *http.Request) {
	cursor, ok := decodeRankedCursor(r.URL.Query().Get("cursor"))
	if !ok {
		// Clients can refresh to clear a cursor issued before this ranker.
		bad(w, "Invalid feed cursor. Refresh the feed.")
		return
	}
	if len(cursor.pending) == 0 && cursor.more {
		var err error
		cursor, err = h.candidateWindow(r, cursor)
		if err != nil {
			failure(w, err)
			return
		}
	}
	count := min(feedPageSize, len(cursor.pending))
	items := []post{}
	if count > 0 {
		rows, err := h.db.Query(r.Context(), `SELECT p.id,u.name,u.username,p.body,p.media_key,p.created_at,
			(SELECT count(*) FROM (SELECT 1 FROM social_likes WHERE post_id=p.id LIMIT 201) sample),
			EXISTS(SELECT 1 FROM social_likes WHERE post_id=p.id AND user_id=$1)
			FROM unnest($2::uuid[]) WITH ORDINALITY AS ordered(id,position)
			JOIN social_posts p ON p.id=ordered.id JOIN users u ON u.id=p.author_id ORDER BY ordered.position`, viewer(r), cursor.pending[:count])
		if err != nil {
			failure(w, err)
			return
		}
		items, err = pgx.CollectRows(rows, func(row pgx.CollectableRow) (post, error) {
			var p post
			err := row.Scan(&p.ID, &p.Name, &p.Username, &p.Body, &p.MediaKey, &p.CreatedAt, &p.Likes, &p.Liked)
			if err == nil && p.MediaKey != nil {
				p.MediaURL = h.media.CDNURL(*p.MediaKey)
			}
			return p, err
		})
		if err != nil {
			failure(w, err)
			return
		}
		cursor.pending = cursor.pending[count:]
	}
	result := map[string]any{"data": items}
	if cursor.more || len(cursor.pending) > 0 {
		result["nextCursor"] = cursor.encode()
	}
	httpx.JSON(w, 200, result)
}

func (h *Handler) candidateWindow(r *http.Request, cursor rankedCursor) (rankedCursor, error) {
	var at *time.Time
	if cursor.tail.Valid {
		at = &cursor.before
	}
	rows, err := h.db.Query(r.Context(), `WITH pool AS MATERIALIZED (
		SELECT id,author_id,created_at FROM social_posts
		WHERE id<>ALL(COALESCE($5::uuid[],'{}')) AND (created_at,id)<(COALESCE($2::timestamptz,'infinity'),COALESCE($3::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'))
		ORDER BY created_at DESC,id DESC LIMIT $4
	), history AS MATERIALIZED (
		SELECT seen.author_id,count(*) AS affinity FROM (
			SELECT post_id FROM social_likes WHERE user_id=$1 AND created_at>now()-interval '30 days'
			ORDER BY created_at DESC,post_id LIMIT 100
		) actions JOIN social_posts seen ON seen.id=actions.post_id GROUP BY seen.author_id
	)
	, selected AS (
		SELECT *,false AS featured FROM pool
		UNION ALL
		SELECT a.*,true FROM (
			SELECT author_id FROM history
			WHERE $2::timestamptz IS NULL
			ORDER BY affinity DESC,author_id LIMIT 8
		) authors CROSS JOIN LATERAL (
			SELECT id,author_id,created_at FROM social_posts
			WHERE author_id=authors.author_id AND created_at>now()-interval '7 days'
			  AND (created_at,id) < (SELECT created_at,id FROM pool ORDER BY created_at,id LIMIT 1)
			ORDER BY created_at DESC,id DESC LIMIT 3
		) a
	)
	SELECT p.id,p.author_id,p.created_at,
		(SELECT count(*) FROM (SELECT 1 FROM social_likes WHERE post_id=p.id LIMIT 64) sample),
		COALESCE(h.affinity,0),
		EXISTS(SELECT 1 FROM social_likes WHERE post_id=p.id AND user_id=$1),p.featured
	FROM selected p LEFT JOIN history h ON h.author_id=p.author_id ORDER BY p.featured,p.created_at DESC,p.id DESC`,
		viewer(r), at, cursor.tail, feedWindowSize+1, cursor.featured)
	if err != nil {
		return rankedCursor{}, err
	}
	items, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (candidate, error) {
		var p candidate
		err := row.Scan(&p.id, &p.author, &p.at, &p.likes, &p.affinity, &p.liked, &p.featured)
		return p, err
	})
	if err != nil {
		return rankedCursor{}, err
	}
	globalCount := 0
	window := make([]candidate, 0, len(items))
	for _, item := range items {
		if item.featured {
			cursor.featured = append(cursor.featured, item.id)
			window = append(window, item)
			continue
		}
		globalCount++
		if globalCount <= feedWindowSize {
			cursor.before, cursor.tail = item.at, item.id
			window = append(window, item)
		}
	}
	cursor.more = globalCount > feedWindowSize
	cursor.pending = rankCandidates(window, time.Now())
	return cursor, nil
}
