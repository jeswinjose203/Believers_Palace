package social

import (
	"context"
	"errors"
	"hash/maphash"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"believers_palace/internal/httpx"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

const inboxSize = 30
const messagePageSize = 50

type thread struct {
	ID        string    `json:"id"`
	PeerID    string    `json:"peerId"`
	Name      string    `json:"name"`
	Username  string    `json:"username"`
	Preview   string    `json:"preview"`
	UpdatedAt time.Time `json:"updatedAt"`
}

func (h *Handler) inbox(w http.ResponseWriter, r *http.Request) {
	cursor, ok := readCursor(w, r)
	if !ok {
		return
	}
	var at *time.Time
	var id *string
	if cursor.ID != "" {
		at, id = &cursor.At, &cursor.ID
	}
	rows, err := h.db.Query(r.Context(), `WITH page AS (
        (SELECT id,user_b AS peer,last_seq,updated_at FROM direct_threads WHERE user_a=$1 AND last_seq>hidden_a
         AND (updated_at,id)<(COALESCE($2::timestamptz,'infinity'),COALESCE($3::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'))
         ORDER BY updated_at DESC,id DESC LIMIT $4)
        UNION ALL
        (SELECT id,user_a,last_seq,updated_at FROM direct_threads WHERE user_b=$1 AND last_seq>hidden_b
         AND (updated_at,id)<(COALESCE($2::timestamptz,'infinity'),COALESCE($3::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'))
         ORDER BY updated_at DESC,id DESC LIMIT $4)
        ORDER BY updated_at DESC,id DESC LIMIT $4
    )
    SELECT p.id,u.id,u.name,u.username,left(m.body,160),p.updated_at FROM page p
    JOIN users u ON u.id=p.peer JOIN direct_messages m ON m.thread_id=p.id AND m.seq=p.last_seq
    ORDER BY p.updated_at DESC,p.id DESC`, viewer(r), at, id, inboxSize+1)
	if err != nil {
		failure(w, err)
		return
	}
	items, err := pgx.CollectRows(rows, pgx.RowToStructByPos[thread])
	if err != nil {
		failure(w, err)
		return
	}
	result := map[string]any{"data": items}
	if len(items) > inboxSize {
		last := items[inboxSize-1]
		result["data"] = items[:inboxSize]
		result["nextCursor"] = (pageCursor{last.UpdatedAt, last.ID}).encode()
	}
	httpx.JSON(w, 200, result)
}

func (h *Handler) findThread(w http.ResponseWriter, r *http.Request) {
	peer := chi.URLParam(r, "id")
	if !validUUID(peer) {
		bad(w, "Invalid recipient.")
		return
	}
	var id string
	err := h.db.QueryRow(r.Context(), `SELECT id FROM direct_threads
        WHERE user_a=least($1::uuid,$2::uuid) AND user_b=greatest($1::uuid,$2::uuid)`, viewer(r), peer).Scan(&id)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		failure(w, err)
		return
	}
	httpx.JSON(w, 200, map[string]string{"id": id})
}

type message struct {
	Seq       int64     `json:"seq"`
	SenderID  string    `json:"senderId"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"createdAt"`
}

func (h *Handler) messages(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	before := r.URL.Query().Get("before")
	var limitBefore *int64
	if before != "" {
		n, err := strconv.ParseInt(before, 10, 64)
		if err != nil || n < 1 {
			bad(w, "Invalid message cursor.")
			return
		}
		limitBefore = &n
	}
	if !validUUID(id) {
		bad(w, "Invalid conversation.")
		return
	}
	// A single statement gives deletion and message visibility the same snapshot.
	rows, err := h.db.Query(r.Context(), `SELECT m.seq,m.sender_id,m.body,m.created_at
        FROM direct_threads t CROSS JOIN LATERAL (
            SELECT seq,sender_id,body,created_at FROM direct_messages
            WHERE thread_id=t.id AND seq>CASE WHEN t.user_a=$2 THEN t.hidden_a ELSE t.hidden_b END
              AND seq<COALESCE($3::bigint,9223372036854775807)
            ORDER BY seq DESC LIMIT $4
        ) m WHERE t.id=$1 AND $2 IN(t.user_a,t.user_b) ORDER BY m.seq DESC`, id, viewer(r), limitBefore, messagePageSize+1)
	if err != nil {
		failure(w, err)
		return
	}
	items, err := pgx.CollectRows(rows, pgx.RowToStructByPos[message])
	if err != nil {
		failure(w, err)
		return
	}
	result := map[string]any{"data": items}
	if len(items) > messagePageSize {
		result["data"] = items[:messagePageSize]
		result["before"] = items[messagePageSize-1].Seq
	}
	httpx.JSON(w, 200, result)
}

func (h *Handler) send(w http.ResponseWriter, r *http.Request) {
	var in struct{ PeerID, Body, ClientID string }
	if !decode(w, r, &in) {
		return
	}
	sender := viewer(r)
	body := strings.TrimSpace(in.Body)
	if !validUUID(in.PeerID) || strings.EqualFold(sender, in.PeerID) || !clientPattern.MatchString(in.ClientID) ||
		body == "" || utf8.RuneCountInString(body) > 4000 {
		bad(w, "Choose a recipient and enter up to 4,000 characters.")
		return
	}
	peer := strings.ToLower(in.PeerID)
	// Serialize same-thread writers per instance before acquiring a database
	// connection. The row lock still orders writes across instances.
	key := min(sender, peer) + max(sender, peer)
	slot := h.directWrites[maphash.String(h.writeSeed, key)%uint64(len(h.directWrites))]
	select {
	case slot <- struct{}{}:
		defer func() { <-slot }()
	case <-r.Context().Done():
		return
	}
	id, err := h.saveMessage(r.Context(), sender, peer, body, in.ClientID)
	if err != nil {
		failure(w, err)
		return
	}
	httpx.JSON(w, 201, map[string]string{"id": id})
}

func (h *Handler) saveMessage(ctx context.Context, sender, peer, body, clientID string) (string, error) {
	id, err := appendMessage(ctx, h.db, sender, peer, body, clientID)
	if !errors.Is(err, pgx.ErrNoRows) {
		return id, err
	}

	// Thread bootstrap is uncommon. A transaction keeps a failed first send
	// from leaving an empty conversation and is safe if replicas race.
	tx, err := h.db.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `INSERT INTO direct_threads(user_a,user_b)
		SELECT least($1::uuid,u.id),greatest($1::uuid,u.id) FROM users u WHERE u.id=$2
		ON CONFLICT (user_a,user_b) DO NOTHING`, sender, peer); err != nil {
		return "", err
	}
	id, err = appendMessage(ctx, tx, sender, peer, body, clientID)
	if err != nil {
		return "", err
	}
	return id, tx.Commit(ctx)
}

type messageQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func appendMessage(ctx context.Context, db messageQuerier, sender, peer, body, clientID string) (string, error) {
	var id string
	var signals int
	err := db.QueryRow(ctx, `WITH thread AS MATERIALIZED (
		SELECT id,last_seq FROM direct_threads
		WHERE user_a=least($1::uuid,$2::uuid) AND user_b=greatest($1::uuid,$2::uuid)
		FOR NO KEY UPDATE
	), written AS (
		INSERT INTO direct_messages(thread_id,seq,sender_id,body,client_id)
		SELECT id,last_seq+1,$1,$3,$4 FROM thread
		ON CONFLICT(thread_id,sender_id,client_id) DO NOTHING RETURNING thread_id,seq
	), updated AS (
		UPDATE direct_threads t SET last_seq=w.seq,updated_at=clock_timestamp()
		FROM written w WHERE t.id=w.thread_id RETURNING t.user_a,t.user_b
	), signals AS MATERIALIZED (
		SELECT pg_notify('chat_changes',jsonb_build_object('kind','direct','id',participant.id)::text)
		FROM updated CROSS JOIN LATERAL (VALUES(user_a),(user_b)) AS participant(id)
	)
	SELECT id,(SELECT count(*) FROM signals) FROM thread`, sender, peer, body, clientID).Scan(&id, &signals)
	return id, err
}

func (h *Handler) hide(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if !validUUID(id) {
		bad(w, "Invalid conversation.")
		return
	}
	if _, err := h.db.Exec(r.Context(), `WITH hidden AS (
        UPDATE direct_threads
        SET hidden_a=CASE WHEN user_a=$2 THEN last_seq ELSE hidden_a END,
            hidden_b=CASE WHEN user_b=$2 THEN last_seq ELSE hidden_b END
        WHERE id=$1 AND $2 IN(user_a,user_b) RETURNING id
    ) SELECT pg_notify('chat_changes',jsonb_build_object('kind','direct','id',$2::uuid,'deleted',$1::uuid)::text) FROM hidden`, id, viewer(r)); err != nil {
		failure(w, err)
		return
	}
	w.WriteHeader(204)
}
