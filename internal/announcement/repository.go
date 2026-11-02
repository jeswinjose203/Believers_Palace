package announcement

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when an announcement does not exist.
var ErrNotFound = errors.New("announcement not found")

// Repository provides access to the announcement store.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates an announcement repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const columns = `id, church_id, title, content, image, published_at, created_at, updated_at`

func scan(row pgx.Row) (*Announcement, error) {
	var a Announcement
	if err := row.Scan(
		&a.ID, &a.ChurchID, &a.Title, &a.Content, &a.Image,
		&a.PublishedAt, &a.CreatedAt, &a.UpdatedAt,
	); err != nil {
		return nil, err
	}
	return &a, nil
}

// Create inserts a new announcement for a church.
func (r *Repository) Create(ctx context.Context, churchID string, in CreateRequest) (*Announcement, error) {
	const q = `
		INSERT INTO announcements (church_id, title, content, image, published_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING ` + columns
	a, err := scan(r.pool.QueryRow(ctx, q, churchID, in.Title, in.Content, in.Image, in.PublishedAt))
	if err != nil {
		return nil, fmt.Errorf("create announcement: %w", err)
	}
	return a, nil
}

// GetByID returns an announcement by ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Announcement, error) {
	const q = `SELECT ` + columns + ` FROM announcements WHERE id = $1`
	a, err := scan(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get announcement: %w", err)
	}
	return a, nil
}

// ListByChurch returns a page of announcements for a church plus the total count.
// When search is non-empty it matches the title or content.
func (r *Repository) ListByChurch(ctx context.Context, churchID, search string, limit, offset int) ([]Announcement, int, error) {
	args := []any{churchID}
	where := "WHERE church_id = $1"
	if search != "" {
		args = append(args, "%"+search+"%")
		where += fmt.Sprintf(" AND (title ILIKE $%d OR content ILIKE $%d)", len(args), len(args))
	}

	var total int
	if err := r.pool.QueryRow(ctx,
		"SELECT count(*) FROM announcements "+where, args...,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count announcements: %w", err)
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(
		"SELECT %s FROM announcements %s ORDER BY COALESCE(published_at, created_at) DESC LIMIT $%d OFFSET $%d",
		columns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list announcements: %w", err)
	}
	defer rows.Close()

	items := make([]Announcement, 0)
	for rows.Next() {
		a, err := scan(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan announcement: %w", err)
		}
		items = append(items, *a)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate announcements: %w", err)
	}
	return items, total, nil
}

// Update applies the non-nil fields and returns the updated announcement.
func (r *Repository) Update(ctx context.Context, id string, in UpdateRequest) (*Announcement, error) {
	var (
		sets []string
		args []any
	)
	if in.Title != nil {
		args = append(args, *in.Title)
		sets = append(sets, fmt.Sprintf("title = $%d", len(args)))
	}
	if in.Content != nil {
		args = append(args, *in.Content)
		sets = append(sets, fmt.Sprintf("content = $%d", len(args)))
	}
	if in.Image != nil {
		args = append(args, in.Image)
		sets = append(sets, fmt.Sprintf("image = $%d", len(args)))
	}
	if in.PublishedAt != nil {
		args = append(args, in.PublishedAt)
		sets = append(sets, fmt.Sprintf("published_at = $%d", len(args)))
	}

	if len(sets) == 0 {
		return r.GetByID(ctx, id)
	}
	sets = append(sets, "updated_at = now()")

	args = append(args, id)
	q := fmt.Sprintf(
		"UPDATE announcements SET %s WHERE id = $%d RETURNING %s",
		strings.Join(sets, ", "), len(args), columns,
	)
	a, err := scan(r.pool.QueryRow(ctx, q, args...))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update announcement: %w", err)
	}
	return a, nil
}

// Delete removes an announcement by ID.
func (r *Repository) Delete(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM announcements WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete announcement: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
