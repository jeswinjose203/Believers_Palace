package certificate

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a certificate does not exist.
var ErrNotFound = errors.New("certificate not found")

// ErrNumberExists is returned when a certificate number already exists for the user.
var ErrNumberExists = errors.New("certificate number already exists")

// Repository provides access to the certificate store.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a certificate repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const columns = `id, user_id, uploaded_by_user_id, type, certificate_number, full_name, issue_date, file_name, stored_path, mime_type, file_size, notes, created_at`

func scan(row pgx.Row) (*Certificate, error) {
	var c Certificate
	if err := row.Scan(
		&c.ID, &c.UserID, &c.UploadedByUserID, &c.Type, &c.CertificateNumber, &c.FullName,
		&c.IssueDate, &c.FileName, &c.StoredPath, &c.MimeType, &c.FileSize, &c.Notes, &c.CreatedAt,
	); err != nil {
		return nil, err
	}
	return &c, nil
}

// Create inserts certificate metadata. A duplicate (user, number) yields
// ErrNumberExists.
func (r *Repository) Create(ctx context.Context, c *Certificate) (*Certificate, error) {
	const q = `
		INSERT INTO certificates
			(user_id, uploaded_by_user_id, type, certificate_number, full_name, issue_date,
			 file_name, stored_path, mime_type, file_size, notes)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING ` + columns
	out, err := scan(r.pool.QueryRow(ctx, q,
		c.UserID, c.UploadedByUserID, c.Type, c.CertificateNumber, c.FullName, c.IssueDate,
		c.FileName, c.StoredPath, c.MimeType, c.FileSize, c.Notes,
	))
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return nil, ErrNumberExists
		}
		return nil, fmt.Errorf("create certificate: %w", err)
	}
	return out, nil
}

// GetByID returns certificate metadata by ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Certificate, error) {
	const q = `SELECT ` + columns + ` FROM certificates WHERE id = $1`
	c, err := scan(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get certificate: %w", err)
	}
	return c, nil
}

// ListByUser returns a filtered page of certificates for a user plus the total count.
func (r *Repository) ListByUser(ctx context.Context, userID string, typ Type, limit, offset int) ([]Certificate, int, error) {
	args := []any{userID}
	where := "WHERE user_id = $1"
	if typ != "" {
		args = append(args, typ)
		where += fmt.Sprintf(" AND type = $%d", len(args))
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM certificates "+where, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count certificates: %w", err)
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(
		"SELECT %s FROM certificates %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d",
		columns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list certificates: %w", err)
	}
	defer rows.Close()

	items := make([]Certificate, 0)
	for rows.Next() {
		c, err := scan(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan certificate: %w", err)
		}
		items = append(items, *c)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate certificates: %w", err)
	}
	return items, total, nil
}

// Delete removes certificate metadata by ID.
func (r *Repository) Delete(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM certificates WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete certificate: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
