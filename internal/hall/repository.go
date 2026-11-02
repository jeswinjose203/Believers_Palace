package hall

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a hall does not exist.
var ErrNotFound = errors.New("hall not found")

// Repository provides access to the hall store.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a hall repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const columns = `id, church_id, name, description, capacity, location, images, amenities, price, created_at`

func scan(row pgx.Row) (*Hall, error) {
	var (
		h                     Hall
		description, location *string
		imagesRaw, amenRaw    []byte
	)
	if err := row.Scan(
		&h.ID, &h.ChurchID, &h.Name, &description, &h.Capacity, &location,
		&imagesRaw, &amenRaw, &h.Price, &h.CreatedAt,
	); err != nil {
		return nil, err
	}
	if description != nil {
		h.Description = *description
	}
	if location != nil {
		h.Location = *location
	}
	var err error
	if h.Images, err = decodeStrings(imagesRaw); err != nil {
		return nil, fmt.Errorf("decode images: %w", err)
	}
	if h.Amenities, err = decodeStrings(amenRaw); err != nil {
		return nil, fmt.Errorf("decode amenities: %w", err)
	}
	return &h, nil
}

// decodeStrings decodes a JSONB string array, yielding a non-nil empty slice
// for NULL/empty so the JSON response always contains an array.
func decodeStrings(raw []byte) ([]string, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return []string{}, nil
	}
	var out []string
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	if out == nil {
		out = []string{}
	}
	return out, nil
}

// encodeStrings marshals a string slice to a JSONB-storable value.
func encodeStrings(s []string) (string, error) {
	if s == nil {
		s = []string{}
	}
	b, err := json.Marshal(s)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// Create inserts a new hall for a church.
func (r *Repository) Create(ctx context.Context, churchID string, in CreateRequest) (*Hall, error) {
	images, err := encodeStrings(in.Images)
	if err != nil {
		return nil, fmt.Errorf("encode images: %w", err)
	}
	amenities, err := encodeStrings(in.Amenities)
	if err != nil {
		return nil, fmt.Errorf("encode amenities: %w", err)
	}

	const q = `
		INSERT INTO halls (church_id, name, description, capacity, location, images, amenities, price)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING ` + columns
	h, err := scan(r.pool.QueryRow(ctx, q,
		churchID, in.Name, nullify(in.Description), in.Capacity, nullify(in.Location),
		images, amenities, in.Price,
	))
	if err != nil {
		return nil, fmt.Errorf("create hall: %w", err)
	}
	return h, nil
}

// GetByID returns a hall by ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Hall, error) {
	const q = `SELECT ` + columns + ` FROM halls WHERE id = $1`
	h, err := scan(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get hall: %w", err)
	}
	return h, nil
}

// ListByChurch returns a page of halls for a church plus the total count.
// When search is non-empty it matches the name, description, or location.
func (r *Repository) ListByChurch(ctx context.Context, churchID, search string, limit, offset int) ([]Hall, int, error) {
	args := []any{churchID}
	where := "WHERE church_id = $1"
	if search != "" {
		args = append(args, "%"+search+"%")
		where += fmt.Sprintf(
			" AND (name ILIKE $%d OR description ILIKE $%d OR location ILIKE $%d)",
			len(args), len(args), len(args),
		)
	}

	var total int
	if err := r.pool.QueryRow(ctx,
		"SELECT count(*) FROM halls "+where, args...,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count halls: %w", err)
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(
		"SELECT %s FROM halls %s ORDER BY name ASC LIMIT $%d OFFSET $%d",
		columns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list halls: %w", err)
	}
	defer rows.Close()

	items := make([]Hall, 0)
	for rows.Next() {
		h, err := scan(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan hall: %w", err)
		}
		items = append(items, *h)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate halls: %w", err)
	}
	return items, total, nil
}

// Update applies the provided fields and returns the updated hall.
func (r *Repository) Update(ctx context.Context, id string, in UpdateRequest) (*Hall, error) {
	var (
		sets []string
		args []any
	)
	if in.Name != nil {
		args = append(args, *in.Name)
		sets = append(sets, fmt.Sprintf("name = $%d", len(args)))
	}
	if in.Description != nil {
		args = append(args, nullify(*in.Description))
		sets = append(sets, fmt.Sprintf("description = $%d", len(args)))
	}
	if in.Capacity != nil {
		args = append(args, in.Capacity)
		sets = append(sets, fmt.Sprintf("capacity = $%d", len(args)))
	}
	if in.Location != nil {
		args = append(args, nullify(*in.Location))
		sets = append(sets, fmt.Sprintf("location = $%d", len(args)))
	}
	if in.Images != nil {
		enc, err := encodeStrings(*in.Images)
		if err != nil {
			return nil, fmt.Errorf("encode images: %w", err)
		}
		args = append(args, enc)
		sets = append(sets, fmt.Sprintf("images = $%d", len(args)))
	}
	if in.Amenities != nil {
		enc, err := encodeStrings(*in.Amenities)
		if err != nil {
			return nil, fmt.Errorf("encode amenities: %w", err)
		}
		args = append(args, enc)
		sets = append(sets, fmt.Sprintf("amenities = $%d", len(args)))
	}
	if in.Price != nil {
		args = append(args, in.Price)
		sets = append(sets, fmt.Sprintf("price = $%d", len(args)))
	}

	if len(sets) == 0 {
		return r.GetByID(ctx, id)
	}
	sets = append(sets, "updated_at = now()")

	args = append(args, id)
	q := fmt.Sprintf(
		"UPDATE halls SET %s WHERE id = $%d RETURNING %s",
		strings.Join(sets, ", "), len(args), columns,
	)
	h, err := scan(r.pool.QueryRow(ctx, q, args...))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update hall: %w", err)
	}
	return h, nil
}

// ChurchIDOf returns the church ID that owns the given hall. The boolean is
// false when the hall does not exist.
func (r *Repository) ChurchIDOf(ctx context.Context, hallID string) (string, bool, error) {
	var churchID string
	err := r.pool.QueryRow(ctx, `SELECT church_id FROM halls WHERE id = $1`, hallID).Scan(&churchID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup hall church: %w", err)
	}
	return churchID, true, nil
}

// Delete removes a hall by ID.
func (r *Repository) Delete(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM halls WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete hall: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// nullify converts an empty string to NULL so optional columns stay null.
func nullify(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
