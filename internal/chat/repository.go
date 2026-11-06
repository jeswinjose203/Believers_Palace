package chat

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a message does not exist.
var ErrNotFound = errors.New("message not found")

// Repository provides access to the event chat message store.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a chat repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const columns = `id, event_id, seq, user_id, author_name, author_pic, content, created_at`

func scan(row pgx.Row) (*Message, error) {
	var m Message
	if err := row.Scan(
		&m.ID, &m.EventID, &m.Seq, &m.UserID, &m.AuthorName, &m.AuthorPic, &m.Content, &m.CreatedAt,
	); err != nil {
		return nil, err
	}
	return &m, nil
}

// Create inserts a new message and returns it.
func (r *Repository) Create(ctx context.Context, eventID string, userID *string, authorName string, authorPic *string, content string) (*Message, error) {
	const q = `
		INSERT INTO event_messages (event_id, user_id, author_name, author_pic, content)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING ` + columns
	m, err := scan(r.pool.QueryRow(ctx, q, eventID, userID, authorName, authorPic, content))
	if err != nil {
		return nil, fmt.Errorf("create message: %w", err)
	}
	return m, nil
}

// GetByID returns a message by ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Message, error) {
	const q = `SELECT ` + columns + ` FROM event_messages WHERE id = $1`
	m, err := scan(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get message: %w", err)
	}
	return m, nil
}

// ListByEvent returns a page of messages for an event plus the total count,
// ordered oldest-first so a chat view reads top to bottom.
func (r *Repository) ListByEvent(ctx context.Context, eventID string, limit, offset int) ([]Message, int, error) {
	var total int
	if err := r.pool.QueryRow(ctx,
		`SELECT count(*) FROM event_messages WHERE event_id = $1`, eventID,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count messages: %w", err)
	}

	const q = `
		SELECT ` + columns + `
		FROM event_messages
		WHERE event_id = $1
		ORDER BY seq ASC
		LIMIT $2 OFFSET $3`
	rows, err := r.pool.Query(ctx, q, eventID, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("list messages: %w", err)
	}
	defer rows.Close()

	items := make([]Message, 0)
	for rows.Next() {
		m, err := scan(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan message: %w", err)
		}
		items = append(items, *m)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate messages: %w", err)
	}
	return items, total, nil
}

// ListCursor returns a window of messages ordered oldest-first plus whether
// more messages exist beyond the window:
//   - After > 0:  messages newer than After (oldest first); hasMore = more newer.
//   - Before > 0: the newest messages older than Before; hasMore = more older.
//   - neither:    the latest messages; hasMore = more older.
func (r *Repository) ListCursor(ctx context.Context, eventID string, q CursorQuery) ([]Message, bool, error) {
	var (
		query      string
		args       []any
		descending bool
	)
	switch {
	case q.After > 0:
		query = `SELECT ` + columns + ` FROM event_messages
			WHERE event_id = $1 AND seq > $2 ORDER BY seq ASC LIMIT $3`
		args = []any{eventID, q.After, q.Limit + 1}
	case q.Before > 0:
		query = `SELECT ` + columns + ` FROM event_messages
			WHERE event_id = $1 AND seq < $2 ORDER BY seq DESC LIMIT $3`
		args = []any{eventID, q.Before, q.Limit + 1}
		descending = true
	default:
		query = `SELECT ` + columns + ` FROM event_messages
			WHERE event_id = $1 ORDER BY seq DESC LIMIT $2`
		args = []any{eventID, q.Limit + 1}
		descending = true
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, false, fmt.Errorf("list messages: %w", err)
	}
	defer rows.Close()

	items := make([]Message, 0, q.Limit+1)
	for rows.Next() {
		m, err := scan(rows)
		if err != nil {
			return nil, false, fmt.Errorf("scan message: %w", err)
		}
		items = append(items, *m)
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("iterate messages: %w", err)
	}

	hasMore := len(items) > q.Limit
	if hasMore {
		items = items[:q.Limit]
	}
	if descending {
		for i, j := 0, len(items)-1; i < j; i, j = i+1, j-1 {
			items[i], items[j] = items[j], items[i]
		}
	}
	return items, hasMore, nil
}

// Delete removes a message by ID.
func (r *Repository) Delete(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM event_messages WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete message: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
