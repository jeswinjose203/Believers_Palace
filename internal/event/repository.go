package event

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when an event does not exist.
var ErrNotFound = errors.New("event not found")

// ErrNotRegistered is returned when cancelling a registration that doesn't exist.
var ErrNotRegistered = errors.New("not registered for this event")

// ErrAlreadyRegistered is returned when a user registers twice for an event.
var ErrAlreadyRegistered = errors.New("already registered for this event")

// Repository provides access to the event store.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates an event repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const columns = `id, church_id, title, description, location, start_date, end_date, image, capacity, registration_required, created_at`

func scan(row pgx.Row) (*Event, error) {
	var (
		e                            Event
		description, location, image *string
	)
	if err := row.Scan(
		&e.ID, &e.ChurchID, &e.Title, &description, &location,
		&e.StartDate, &e.EndDate, &image, &e.Capacity, &e.RegistrationRequired, &e.CreatedAt,
	); err != nil {
		return nil, err
	}
	if description != nil {
		e.Description = *description
	}
	if location != nil {
		e.Location = *location
	}
	if image != nil {
		e.Image = *image
	}
	return &e, nil
}

// Create inserts a new event for a church.
func (r *Repository) Create(ctx context.Context, churchID string, in Request) (*Event, error) {
	regRequired := false
	if in.RegistrationRequired != nil {
		regRequired = *in.RegistrationRequired
	}
	const q = `
		INSERT INTO events (church_id, title, description, location, start_date, end_date, image, capacity, registration_required)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING ` + columns
	e, err := scan(r.pool.QueryRow(ctx, q,
		churchID, in.Title, nullify(in.Description), nullify(in.Location),
		in.StartDate, in.EndDate, nullify(in.Image), in.Capacity, regRequired,
	))
	if err != nil {
		return nil, fmt.Errorf("create event: %w", err)
	}
	return e, nil
}

// GetByID returns an event by ID.
func (r *Repository) GetByID(ctx context.Context, id string) (*Event, error) {
	const q = `SELECT ` + columns + ` FROM events WHERE id = $1`
	e, err := scan(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get event: %w", err)
	}
	return e, nil
}

// ListByChurch returns a page of events for a church plus the total count.
// When search is non-empty it matches the title, description, or location.
func (r *Repository) ListByChurch(ctx context.Context, churchID, search string, limit, offset int) ([]Event, int, error) {
	args := []any{churchID}
	where := "WHERE church_id = $1"
	if search != "" {
		args = append(args, "%"+search+"%")
		where += fmt.Sprintf(
			" AND (title ILIKE $%d OR description ILIKE $%d OR location ILIKE $%d)",
			len(args), len(args), len(args),
		)
	}

	var total int
	if err := r.pool.QueryRow(ctx,
		"SELECT count(*) FROM events "+where, args...,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count events: %w", err)
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(
		"SELECT %s FROM events %s ORDER BY start_date DESC LIMIT $%d OFFSET $%d",
		columns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list events: %w", err)
	}
	defer rows.Close()

	items := make([]Event, 0)
	for rows.Next() {
		e, err := scan(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan event: %w", err)
		}
		items = append(items, *e)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate events: %w", err)
	}
	return items, total, nil
}
 
// ListByChurchInRange returns church events overlapping [from, to].
func (r *Repository) ListByChurchInRange(ctx context.Context, churchID string, from, to time.Time) ([]Event, error) {
    const q = `SELECT ` + columns + ` FROM events
        WHERE church_id = $1 AND start_date <= $3
        AND (end_date IS NULL OR end_date >= $2)
        ORDER BY start_date`
    rows, err := r.pool.Query(ctx, q, churchID, from, to)
    if err != nil {
        return nil, fmt.Errorf("list events in range: %w", err)
    }
    defer rows.Close()
    var items []Event
    for rows.Next() {
        e, err := scan(rows)
        if err != nil {
            return nil, err
        }
        items = append(items, *e)
    }
    return items, rows.Err()
}

// Update replaces an event's fields and returns the updated record.
func (r *Repository) Update(ctx context.Context, id string, in Request) (*Event, error) {
	regRequired := false
	if in.RegistrationRequired != nil {
		regRequired = *in.RegistrationRequired
	}
	const q = `
		UPDATE events
		SET title = $1, description = $2, location = $3, start_date = $4, end_date = $5,
		    image = $6, capacity = $7, registration_required = $8, updated_at = now()
		WHERE id = $9
		RETURNING ` + columns
	e, err := scan(r.pool.QueryRow(ctx, q,
		in.Title, nullify(in.Description), nullify(in.Location), in.StartDate, in.EndDate,
		nullify(in.Image), in.Capacity, regRequired, id,
	))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update event: %w", err)
	}
	return e, nil
}

// Delete removes an event by ID.
func (r *Repository) Delete(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM events WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete event: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// CountRegistrations returns the number of registrations for an event.
func (r *Repository) CountRegistrations(ctx context.Context, eventID string) (int, error) {
	var n int
	if err := r.pool.QueryRow(ctx,
		`SELECT count(*) FROM event_registrations WHERE event_id = $1`, eventID,
	).Scan(&n); err != nil {
		return 0, fmt.Errorf("count registrations: %w", err)
	}
	return n, nil
}

// RegisteredEventIDs returns the subset of eventIDs the user is registered for.
func (r *Repository) RegisteredEventIDs(ctx context.Context, userID string, eventIDs []string) (map[string]bool, error) {
	out := make(map[string]bool)
	if userID == "" || len(eventIDs) == 0 {
		return out, nil
	}
	rows, err := r.pool.Query(ctx,
		`SELECT event_id FROM event_registrations WHERE user_id = $1 AND event_id = ANY($2::uuid[])`,
		userID, eventIDs)
	if err != nil {
		return nil, fmt.Errorf("registered events: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("scan registered event: %w", err)
		}
		out[id] = true
	}
	return out, rows.Err()
}

// DeleteRegistration removes the user's registration for an event. It returns
// ErrNotRegistered if there was none.
func (r *Repository) DeleteRegistration(ctx context.Context, eventID, userID string) error {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM event_registrations WHERE event_id = $1 AND user_id = $2`, eventID, userID)
	if err != nil {
		return fmt.Errorf("delete registration: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotRegistered
	}
	return nil
}

// IsRegistered reports whether the user has registered for the event.
func (r *Repository) IsRegistered(ctx context.Context, eventID, userID string) (bool, error) {
	var exists bool
	if err := r.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM event_registrations WHERE event_id = $1 AND user_id = $2)`,
		eventID, userID,
	).Scan(&exists); err != nil {
		return false, fmt.Errorf("check registration: %w", err)
	}
	return exists, nil
}

// ListRegistrations returns a page of registrations for an event plus the
// total count, most recent first.
func (r *Repository) ListRegistrations(ctx context.Context, eventID string, limit, offset int) ([]Registration, int, error) {
	var total int
	if err := r.pool.QueryRow(ctx,
		`SELECT count(*) FROM event_registrations WHERE event_id = $1`, eventID,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count registrations: %w", err)
	}

	const q = `
		SELECT id, event_id, user_id, attendee_name, attendee_email, attendee_phone, notes, created_at
		FROM event_registrations
		WHERE event_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3`
	rows, err := r.pool.Query(ctx, q, eventID, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("list registrations: %w", err)
	}
	defer rows.Close()

	items := make([]Registration, 0)
	for rows.Next() {
		var (
			reg                       Registration
			name, email, phone, notes *string
		)
		if err := rows.Scan(
			&reg.ID, &reg.EventID, &reg.UserID, &name, &email, &phone, &notes, &reg.CreatedAt,
		); err != nil {
			return nil, 0, fmt.Errorf("scan registration: %w", err)
		}
		if name != nil {
			reg.AttendeeName = *name
		}
		if email != nil {
			reg.AttendeeEmail = *email
		}
		if phone != nil {
			reg.AttendeePhone = *phone
		}
		if notes != nil {
			reg.Notes = *notes
		}
		items = append(items, reg)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate registrations: %w", err)
	}
	return items, total, nil
}

// CreateRegistration inserts an attendee registration. userID may be nil for
// anonymous attendees. A duplicate signed-in registration yields
// ErrAlreadyRegistered.
func (r *Repository) CreateRegistration(ctx context.Context, eventID string, userID *string, in RegistrationRequest) (*Registration, error) {
	const q = `
		INSERT INTO event_registrations (event_id, user_id, attendee_name, attendee_email, attendee_phone, notes)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, event_id, user_id, attendee_name, attendee_email, attendee_phone, notes, created_at`

	var (
		reg                       Registration
		name, email, phone, notes *string
	)
	err := r.pool.QueryRow(ctx, q,
		eventID, userID, nullify(in.AttendeeName), nullify(in.AttendeeEmail),
		nullify(in.AttendeePhone), nullify(in.Notes),
	).Scan(&reg.ID, &reg.EventID, &reg.UserID, &name, &email, &phone, &notes, &reg.CreatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return nil, ErrAlreadyRegistered
		}
		return nil, fmt.Errorf("create registration: %w", err)
	}
	if name != nil {
		reg.AttendeeName = *name
	}
	if email != nil {
		reg.AttendeeEmail = *email
	}
	if phone != nil {
		reg.AttendeePhone = *phone
	}
	if notes != nil {
		reg.Notes = *notes
	}
	return &reg, nil
}

func nullify(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
