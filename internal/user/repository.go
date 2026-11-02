package user

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"believers_palace/internal/auth"
)

// ErrNotFound is returned when a user does not exist.
var ErrNotFound = errors.New("user not found")

// ErrEmailExists is returned when an email is already registered.
var ErrEmailExists = errors.New("email already registered")

// ListFilter holds optional filters for listing users.
type ListFilter struct {
	ChurchID string
	Role     auth.Role
	Limit    int
	Offset   int
}

// Repository provides access to the user store.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a user repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const userColumns = `id, name, email, password_hash, phone, unit, profile_pic, role, church_id, email_verified, created_at`

func scanUser(row pgx.Row) (*User, error) {
	var u User
	err := row.Scan(
		&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Phone, &u.Unit,
		&u.ProfilePic, &u.Role, &u.ChurchID, &u.EmailVerified, &u.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// Create inserts a new user with a pre-hashed password.
func (r *Repository) Create(ctx context.Context, in RegisterInput, passwordHash string, role auth.Role) (*User, error) {
	const q = `
		INSERT INTO users (name, email, password_hash, phone, unit, church_id, role)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING ` + userColumns

	row := r.pool.QueryRow(ctx, q,
		in.Name, strings.ToLower(in.Email), passwordHash, in.Phone, in.Unit, in.ChurchID, role,
	)
	u, err := scanUser(row)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return nil, ErrEmailExists
		}
		return nil, fmt.Errorf("create user: %w", err)
	}
	return u, nil
}

// ChurchIDOf returns the church ID associated with a user (empty string if the
// user has no church). The boolean is false when the user does not exist.
func (r *Repository) ChurchIDOf(ctx context.Context, userID string) (string, bool, error) {
	var churchID *string
	err := r.pool.QueryRow(ctx, `SELECT church_id FROM users WHERE id = $1`, userID).Scan(&churchID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup user church: %w", err)
	}
	if churchID == nil {
		return "", true, nil
	}
	return *churchID, true, nil
}

// GetByID returns a user by ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*User, error) {
	const q = `SELECT ` + userColumns + ` FROM users WHERE id = $1`
	u, err := scanUser(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	return u, nil
}

// GetByEmail returns a user by email.
func (r *Repository) GetByEmail(ctx context.Context, email string) (*User, error) {
	const q = `SELECT ` + userColumns + ` FROM users WHERE email = $1`
	u, err := scanUser(r.pool.QueryRow(ctx, q, strings.ToLower(email)))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get user by email: %w", err)
	}
	return u, nil
}

// List returns users matching the filter plus the total count.
func (r *Repository) List(ctx context.Context, f ListFilter) ([]User, int, error) {
	var (
		conds []string
		args  []any
	)
	if f.ChurchID != "" {
		args = append(args, f.ChurchID)
		conds = append(conds, fmt.Sprintf("church_id = $%d", len(args)))
	}
	if f.Role != "" {
		args = append(args, f.Role)
		conds = append(conds, fmt.Sprintf("role = $%d", len(args)))
	}

	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	countQ := "SELECT count(*) FROM users " + where
	if err := r.pool.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count users: %w", err)
	}

	args = append(args, f.Limit, f.Offset)
	listQ := fmt.Sprintf(
		"SELECT %s FROM users %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d",
		userColumns, where, len(args)-1, len(args),
	)

	rows, err := r.pool.Query(ctx, listQ, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list users: %w", err)
	}
	defer rows.Close()

	users := make([]User, 0)
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan user: %w", err)
		}
		users = append(users, *u)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate users: %w", err)
	}
	return users, total, nil
}

// UpdateProfile applies the non-nil profile fields and returns the updated user.
func (r *Repository) UpdateProfile(ctx context.Context, id string, in ProfileUpdateInput) (*User, error) {
	var (
		sets []string
		args []any
	)
	if in.Name != nil {
		args = append(args, *in.Name)
		sets = append(sets, fmt.Sprintf("name = $%d", len(args)))
	}
	if in.Phone != nil {
		args = append(args, in.Phone)
		sets = append(sets, fmt.Sprintf("phone = $%d", len(args)))
	}
	if in.Unit != nil {
		args = append(args, in.Unit)
		sets = append(sets, fmt.Sprintf("unit = $%d", len(args)))
	}
	if in.ProfilePic != nil {
		args = append(args, in.ProfilePic)
		sets = append(sets, fmt.Sprintf("profile_pic = $%d", len(args)))
	}

	if len(sets) == 0 {
		return r.GetByID(ctx, id)
	}
	sets = append(sets, "updated_at = now()")

	args = append(args, id)
	q := fmt.Sprintf(
		"UPDATE users SET %s WHERE id = $%d RETURNING %s",
		strings.Join(sets, ", "), len(args), userColumns,
	)

	u, err := scanUser(r.pool.QueryRow(ctx, q, args...))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update profile: %w", err)
	}
	return u, nil
}

// UpdateRole sets a user's role and returns the updated user.
func (r *Repository) UpdateRole(ctx context.Context, id string, role auth.Role) (*User, error) {
	const q = `
		UPDATE users SET role = $1, updated_at = now()
		WHERE id = $2
		RETURNING ` + userColumns
	u, err := scanUser(r.pool.QueryRow(ctx, q, role, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update role: %w", err)
	}
	return u, nil
}
