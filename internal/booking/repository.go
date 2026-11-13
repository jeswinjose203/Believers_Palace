package booking

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a booking does not exist.
var ErrNotFound = errors.New("booking not found")

// ErrOverlap is returned when a booking would overlap an existing active
// (pending or approved) booking for the same hall.
var ErrOverlap = errors.New("hall is already booked for an overlapping time range")

// ListFilter holds optional filters for listing bookings.
type ListFilter struct {
	ChurchID string
	UserID   string // when set, restrict to this user's bookings
	Status   Status
	Search   string // when set, matches purpose or notes
	Limit    int
	Offset   int
}

// Repository provides access to the booking store.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a booking repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const columns = `id, church_id, hall_id, user_id, start_date, end_date, purpose, notes, status, admin_notes, cancellation_reason, created_at`

// columnsWithUser selects booking columns plus the requester's public profile
// via a LEFT JOIN on users (aliased b and u). Used by list/get so admins can
// see who made each booking.
const columnsWithUser = `b.id, b.church_id, b.hall_id, b.user_id, b.start_date, b.end_date,
	b.purpose, b.notes, b.status, b.admin_notes, b.cancellation_reason, b.created_at,
	u.id, u.name, u.email, u.phone, u.profile_pic`

func scan(row pgx.Row) (*Booking, error) {
	var (
		b                                  Booking
		purpose, notes, adminNotes, cancel *string
	)
	if err := row.Scan(
		&b.ID, &b.ChurchID, &b.HallID, &b.UserID, &b.StartDate, &b.EndDate,
		&purpose, &notes, &b.Status, &adminNotes, &cancel, &b.CreatedAt,
	); err != nil {
		return nil, err
	}
	if purpose != nil {
		b.Purpose = *purpose
	}
	if notes != nil {
		b.Notes = *notes
	}
	if adminNotes != nil {
		b.AdminNotes = *adminNotes
	}
	if cancel != nil {
		b.CancellationReason = *cancel
	}
	return &b, nil
}

// scanWithUser scans a booking row that also carries the requester's profile
// columns (from columnsWithUser). A NULL user id yields a nil User.
func scanWithUser(row pgx.Row) (*Booking, error) {
	var (
		b                                  Booking
		purpose, notes, adminNotes, cancel *string
		uID, uName, uEmail                 *string
		uPhone, uPic                       *string
	)
	if err := row.Scan(
		&b.ID, &b.ChurchID, &b.HallID, &b.UserID, &b.StartDate, &b.EndDate,
		&purpose, &notes, &b.Status, &adminNotes, &cancel, &b.CreatedAt,
		&uID, &uName, &uEmail, &uPhone, &uPic,
	); err != nil {
		return nil, err
	}
	if purpose != nil {
		b.Purpose = *purpose
	}
	if notes != nil {
		b.Notes = *notes
	}
	if adminNotes != nil {
		b.AdminNotes = *adminNotes
	}
	if cancel != nil {
		b.CancellationReason = *cancel
	}
	if uID != nil {
		r := &Requester{ID: *uID, Phone: uPhone, ProfilePic: uPic}
		if uName != nil {
			r.Name = *uName
		}
		if uEmail != nil {
			r.Email = *uEmail
		}
		b.User = r
	}
	return &b, nil
}

// HasOverlap reports whether an active (pending or approved) booking already
// exists for the hall that overlaps the given time range.
func (r *Repository) HasOverlap(ctx context.Context, hallID string, startDate, endDate time.Time) (bool, error) {
	const q = `
		SELECT EXISTS (
			SELECT 1 FROM bookings
			WHERE hall_id = $1
			  AND status IN ('pending', 'approved')
			  AND tstzrange(start_date, end_date) && tstzrange($2, $3)
		)`
	var exists bool
	if err := r.pool.QueryRow(ctx, q, hallID, startDate, endDate).Scan(&exists); err != nil {
		return false, fmt.Errorf("check booking overlap: %w", err)
	}
	return exists, nil
}

// Create inserts a new booking in the pending state.
func (r *Repository) Create(ctx context.Context, churchID, hallID, userID string, in CreateRequest) (*Booking, error) {
	const q = `
		INSERT INTO bookings (church_id, hall_id, user_id, start_date, end_date, purpose, notes, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING ` + columns
	b, err := scan(r.pool.QueryRow(ctx, q,
		churchID, hallID, userID, in.StartDate, in.EndDate,
		nullify(in.Purpose), nullify(in.Notes), StatusPending,
	))
	if err != nil {
		// The GiST exclusion constraint rejects overlapping bookings even under
		// concurrency (Postgres error code 23P01, exclusion_violation).
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23P01" {
			return nil, ErrOverlap
		}
		return nil, fmt.Errorf("create booking: %w", err)
	}
	return b, nil
}

// GetByID returns a booking by ID, including the requester's profile.
func (r *Repository) GetByID(ctx context.Context, id string) (*Booking, error) {
	const q = `SELECT ` + columnsWithUser + ` FROM bookings b
		LEFT JOIN users u ON u.id = b.user_id WHERE b.id = $1`
	b, err := scanWithUser(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get booking: %w", err)
	}
	return b, nil
}

// List returns bookings matching the filter plus the total count. Each booking
// includes the requester's public profile (via a LEFT JOIN on users).
func (r *Repository) List(ctx context.Context, f ListFilter) ([]Booking, int, error) {
	var (
		conds []string
		args  []any
	)
	if f.ChurchID != "" {
		args = append(args, f.ChurchID)
		conds = append(conds, fmt.Sprintf("b.church_id = $%d", len(args)))
	}
	if f.UserID != "" {
		args = append(args, f.UserID)
		conds = append(conds, fmt.Sprintf("b.user_id = $%d", len(args)))
	}
	if f.Status != "" {
		args = append(args, f.Status)
		conds = append(conds, fmt.Sprintf("b.status = $%d", len(args)))
	}
	if f.Search != "" {
		args = append(args, "%"+f.Search+"%")
		conds = append(conds, fmt.Sprintf("(b.purpose ILIKE $%d OR b.notes ILIKE $%d)", len(args), len(args)))
	}

	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM bookings b "+where, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count bookings: %w", err)
	}

	args = append(args, f.Limit, f.Offset)
	q := fmt.Sprintf(
		`SELECT %s FROM bookings b LEFT JOIN users u ON u.id = b.user_id %s
		 ORDER BY b.start_date DESC LIMIT $%d OFFSET $%d`,
		columnsWithUser, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list bookings: %w", err)
	}
	defer rows.Close()

	items := make([]Booking, 0)
	for rows.Next() {
		b, err := scanWithUser(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan booking: %w", err)
		}
		items = append(items, *b)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate bookings: %w", err)
	}
	return items, total, nil
}
 
// ListOverlappingForUser returns bookings for a user that overlap [from, to].
func (r *Repository) ListOverlappingForUser(ctx context.Context, userID string, from, to time.Time) ([]Booking, error) {
    const q = `SELECT ` + columns + ` FROM bookings
        WHERE user_id = $1 AND start_date <= $3 AND end_date >= $2
        ORDER BY start_date`
    rows, err := r.pool.Query(ctx, q, userID, from, to)
    if err != nil {
        return nil, fmt.Errorf("list overlapping bookings: %w", err)
    }
    defer rows.Close()
    var items []Booking
    for rows.Next() {
        b, err := scan(rows)
        if err != nil {
            return nil, err
        }
        items = append(items, *b)
    }
    return items, rows.Err()
}

// UpdateStatus sets the status and admin notes and returns the updated booking.
func (r *Repository) UpdateStatus(ctx context.Context, id string, status Status, adminNotes string) (*Booking, error) {
	const q = `
		UPDATE bookings
		SET status = $1, admin_notes = COALESCE($2, admin_notes), updated_at = now()
		WHERE id = $3
		RETURNING ` + columns
	b, err := scan(r.pool.QueryRow(ctx, q, status, nullify(adminNotes), id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update booking status: %w", err)
	}
	return b, nil
}

// Cancel marks a booking cancelled with an optional reason.
func (r *Repository) Cancel(ctx context.Context, id, reason string) (*Booking, error) {
	const q = `
		UPDATE bookings
		SET status = $1, cancellation_reason = COALESCE($2, cancellation_reason), updated_at = now()
		WHERE id = $3
		RETURNING ` + columns
	b, err := scan(r.pool.QueryRow(ctx, q, StatusCancelled, nullify(reason), id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("cancel booking: %w", err)
	}
	return b, nil
}

func nullify(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
