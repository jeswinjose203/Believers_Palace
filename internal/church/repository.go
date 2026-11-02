package church

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a church does not exist.
var ErrNotFound = errors.New("church not found")

// Repository provides access to the church store.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a church repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const churchColumns = `id, name, address, phone, email, logo, priest, associate_priest, created_at, updated_at`

func scanChurch(row pgx.Row) (*Church, error) {
	var (
		c                     Church
		address, phone, email *string
		logo                  *string
		priestRaw, assocRaw   []byte
	)
	err := row.Scan(
		&c.ID, &c.Name, &address, &phone, &email, &logo,
		&priestRaw, &assocRaw, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	if address != nil {
		c.Address = *address
	}
	if phone != nil {
		c.Phone = *phone
	}
	if email != nil {
		c.Email = *email
	}
	if logo != nil {
		c.Logo = *logo
	}
	if c.Priest, err = decodePriest(priestRaw); err != nil {
		return nil, fmt.Errorf("decode priest: %w", err)
	}
	if c.AssociatePriest, err = decodePriest(assocRaw); err != nil {
		return nil, fmt.Errorf("decode associate priest: %w", err)
	}
	return &c, nil
}

// decodePriest decodes a JSONB column into PriestDetails. NULL/empty yields nil.
func decodePriest(raw []byte) (*PriestDetails, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return nil, nil
	}
	var p PriestDetails
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

// encodePriest encodes PriestDetails to a JSONB-storable value. nil yields SQL NULL.
func encodePriest(p *PriestDetails) (any, error) {
	if p == nil {
		return nil, nil
	}
	b, err := json.Marshal(p)
	if err != nil {
		return nil, err
	}
	return string(b), nil
}

// Create inserts a new church.
func (r *Repository) Create(ctx context.Context, in Request) (*Church, error) {
	const q = `
		INSERT INTO churches (name, address, phone, email, logo, priest, associate_priest)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING ` + churchColumns

	priest, err := encodePriest(in.Priest)
	if err != nil {
		return nil, fmt.Errorf("encode priest: %w", err)
	}
	assoc, err := encodePriest(in.AssociatePriest)
	if err != nil {
		return nil, fmt.Errorf("encode associate priest: %w", err)
	}

	row := r.pool.QueryRow(ctx, q,
		in.Name, nullify(in.Address), nullify(in.Phone), nullify(in.Email),
		nullify(in.Logo), priest, assoc,
	)
	c, err := scanChurch(row)
	if err != nil {
		return nil, fmt.Errorf("create church: %w", err)
	}
	return c, nil
}

// Exists reports whether a church with the given ID exists.
func (r *Repository) Exists(ctx context.Context, id string) (bool, error) {
	var exists bool
	if err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM churches WHERE id = $1)`, id,
	).Scan(&exists); err != nil {
		return false, fmt.Errorf("check church exists: %w", err)
	}
	return exists, nil
}

// GetByID returns a church by ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Church, error) {
	const q = `SELECT ` + churchColumns + ` FROM churches WHERE id = $1`
	c, err := scanChurch(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get church: %w", err)
	}
	return c, nil
}

// List returns a page of churches (condensed) plus the total count. When
// search is non-empty it matches the church name or address.
func (r *Repository) List(ctx context.Context, search string, limit, offset int) ([]ListItem, int, error) {
	var (
		args  []any
		where string
	)
	if search != "" {
		args = append(args, "%"+search+"%")
		where = fmt.Sprintf("WHERE (name ILIKE $%d OR address ILIKE $%d)", len(args), len(args))
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM churches "+where, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count churches: %w", err)
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(
		"SELECT id, name, address, logo FROM churches %s ORDER BY name ASC LIMIT $%d OFFSET $%d",
		where, len(args)-1, len(args),
	)

	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list churches: %w", err)
	}
	defer rows.Close()

	items := make([]ListItem, 0)
	for rows.Next() {
		var (
			it            ListItem
			address, logo *string
		)
		if err := rows.Scan(&it.ID, &it.Name, &address, &logo); err != nil {
			return nil, 0, fmt.Errorf("scan church: %w", err)
		}
		if address != nil {
			it.Address = *address
		}
		if logo != nil {
			it.Logo = *logo
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate churches: %w", err)
	}
	return items, total, nil
}

// Update replaces a church's fields and returns the updated record.
func (r *Repository) Update(ctx context.Context, id string, in Request) (*Church, error) {
	const q = `
		UPDATE churches
		SET name = $1, address = $2, phone = $3, email = $4, logo = $5,
		    priest = $6, associate_priest = $7, updated_at = now()
		WHERE id = $8
		RETURNING ` + churchColumns

	priest, err := encodePriest(in.Priest)
	if err != nil {
		return nil, fmt.Errorf("encode priest: %w", err)
	}
	assoc, err := encodePriest(in.AssociatePriest)
	if err != nil {
		return nil, fmt.Errorf("encode associate priest: %w", err)
	}

	row := r.pool.QueryRow(ctx, q,
		in.Name, nullify(in.Address), nullify(in.Phone), nullify(in.Email),
		nullify(in.Logo), priest, assoc, id,
	)
	c, err := scanChurch(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update church: %w", err)
	}
	return c, nil
}

// Delete removes a church by ID.
func (r *Repository) Delete(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM churches WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete church: %w", err)
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
