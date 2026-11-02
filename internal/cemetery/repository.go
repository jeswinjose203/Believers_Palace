package cemetery

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrPlotNotFound is returned when a cemetery plot does not exist.
var ErrPlotNotFound = errors.New("cemetery plot not found")

// ErrRequestNotFound is returned when a service request does not exist.
var ErrRequestNotFound = errors.New("cemetery service request not found")

// ErrPlotNumberExists is returned when a plot number already exists for a church.
var ErrPlotNumberExists = errors.New("plot number already exists")

// Repository provides access to cemetery plots and service requests.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a cemetery repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// ----- Plots -----

const plotColumns = `id, church_id, plot_number, section, location_description, status, notes, created_at`

func scanPlot(row pgx.Row) (*Plot, error) {
	var (
		p                            Plot
		section, locationDesc, notes *string
	)
	if err := row.Scan(
		&p.ID, &p.ChurchID, &p.PlotNumber, &section, &locationDesc, &p.Status, &notes, &p.CreatedAt,
	); err != nil {
		return nil, err
	}
	if section != nil {
		p.Section = *section
	}
	if locationDesc != nil {
		p.LocationDescription = *locationDesc
	}
	if notes != nil {
		p.Notes = *notes
	}
	return &p, nil
}

// CreatePlot inserts a new cemetery plot.
func (r *Repository) CreatePlot(ctx context.Context, churchID string, in PlotCreateRequest, status PlotStatus) (*Plot, error) {
	const q = `
		INSERT INTO cemetery_plots (church_id, plot_number, section, location_description, status, notes)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING ` + plotColumns
	p, err := scanPlot(r.pool.QueryRow(ctx, q,
		churchID, in.PlotNumber, nullify(in.Section), nullify(in.LocationDescription), status, nullify(in.Notes),
	))
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return nil, ErrPlotNumberExists
		}
		return nil, fmt.Errorf("create plot: %w", err)
	}
	return p, nil
}

// GetPlot returns a plot by ID.
func (r *Repository) GetPlot(ctx context.Context, id string) (*Plot, error) {
	const q = `SELECT ` + plotColumns + ` FROM cemetery_plots WHERE id = $1`
	p, err := scanPlot(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrPlotNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get plot: %w", err)
	}
	return p, nil
}

// PlotFilter holds optional filters for listing cemetery plots.
type PlotFilter struct {
	ChurchID string
	Status   PlotStatus
	Search   string // when set, matches plot number, section, or location
	Limit    int
	Offset   int
}

// ListPlots returns a filtered page of plots for a church plus the total count.
func (r *Repository) ListPlots(ctx context.Context, f PlotFilter) ([]Plot, int, error) {
	args := []any{f.ChurchID}
	where := "WHERE church_id = $1"
	if f.Status != "" {
		args = append(args, f.Status)
		where += fmt.Sprintf(" AND status = $%d", len(args))
	}
	if f.Search != "" {
		args = append(args, "%"+f.Search+"%")
		where += fmt.Sprintf(
			" AND (plot_number ILIKE $%d OR section ILIKE $%d OR location_description ILIKE $%d)",
			len(args), len(args), len(args),
		)
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM cemetery_plots "+where, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count plots: %w", err)
	}

	args = append(args, f.Limit, f.Offset)
	q := fmt.Sprintf(
		"SELECT %s FROM cemetery_plots %s ORDER BY plot_number ASC LIMIT $%d OFFSET $%d",
		plotColumns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list plots: %w", err)
	}
	defer rows.Close()

	items := make([]Plot, 0)
	for rows.Next() {
		p, err := scanPlot(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan plot: %w", err)
		}
		items = append(items, *p)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate plots: %w", err)
	}
	return items, total, nil
}

// PlotAvailable reports whether a plot exists, belongs to the church, and is
// in the available state.
func (r *Repository) PlotAvailable(ctx context.Context, churchID, plotID string) (bool, error) {
	var status PlotStatus
	err := r.pool.QueryRow(ctx,
		`SELECT status FROM cemetery_plots WHERE id = $1 AND church_id = $2`, plotID, churchID,
	).Scan(&status)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("check plot availability: %w", err)
	}
	return status == PlotAvailable, nil
}

// UpdatePlot applies the provided (non-nil) fields and returns the updated plot.
func (r *Repository) UpdatePlot(ctx context.Context, id string, in PlotUpdateRequest) (*Plot, error) {
	var (
		sets []string
		args []any
	)
	if in.PlotNumber != nil {
		args = append(args, *in.PlotNumber)
		sets = append(sets, fmt.Sprintf("plot_number = $%d", len(args)))
	}
	if in.Section != nil {
		args = append(args, nullify(*in.Section))
		sets = append(sets, fmt.Sprintf("section = $%d", len(args)))
	}
	if in.LocationDescription != nil {
		args = append(args, nullify(*in.LocationDescription))
		sets = append(sets, fmt.Sprintf("location_description = $%d", len(args)))
	}
	if in.Status != nil {
		args = append(args, *in.Status)
		sets = append(sets, fmt.Sprintf("status = $%d", len(args)))
	}
	if in.Notes != nil {
		args = append(args, nullify(*in.Notes))
		sets = append(sets, fmt.Sprintf("notes = $%d", len(args)))
	}

	if len(sets) == 0 {
		return r.GetPlot(ctx, id)
	}
	sets = append(sets, "updated_at = now()")

	args = append(args, id)
	q := fmt.Sprintf(
		"UPDATE cemetery_plots SET %s WHERE id = $%d RETURNING %s",
		strings.Join(sets, ", "), len(args), plotColumns,
	)
	p, err := scanPlot(r.pool.QueryRow(ctx, q, args...))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrPlotNotFound
	}
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return nil, ErrPlotNumberExists
		}
		return nil, fmt.Errorf("update plot: %w", err)
	}
	return p, nil
}

// DeletePlot removes a cemetery plot by ID.
func (r *Repository) DeletePlot(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM cemetery_plots WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete plot: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrPlotNotFound
	}
	return nil
}

// ----- Service requests -----

const requestColumns = `id, church_id, user_id, type, status, full_name, contact_phone, contact_email, deceased_name, requested_date, plot_id, description, notes, admin_notes, scheduled_date, created_at, updated_at`

func scanRequest(row pgx.Row) (*ServiceRequest, error) {
	var (
		sr                                              ServiceRequest
		phone, email, deceased, description, notes, adm *string
	)
	if err := row.Scan(
		&sr.ID, &sr.ChurchID, &sr.UserID, &sr.Type, &sr.Status, &sr.FullName,
		&phone, &email, &deceased, &sr.RequestedDate, &sr.PlotID,
		&description, &notes, &adm, &sr.ScheduledDate, &sr.CreatedAt, &sr.UpdatedAt,
	); err != nil {
		return nil, err
	}
	if phone != nil {
		sr.ContactPhone = *phone
	}
	if email != nil {
		sr.ContactEmail = *email
	}
	if deceased != nil {
		sr.DeceasedName = *deceased
	}
	if description != nil {
		sr.Description = *description
	}
	if notes != nil {
		sr.Notes = *notes
	}
	if adm != nil {
		sr.AdminNotes = *adm
	}
	return &sr, nil
}

// CreateRequest inserts a new service request in the pending state.
func (r *Repository) CreateRequest(ctx context.Context, churchID, userID string, in ServiceRequestCreate) (*ServiceRequest, error) {
	const q = `
		INSERT INTO cemetery_service_requests
			(church_id, user_id, type, status, full_name, contact_phone, contact_email,
			 deceased_name, requested_date, plot_id, description, notes)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		RETURNING ` + requestColumns
	sr, err := scanRequest(r.pool.QueryRow(ctx, q,
		churchID, userID, in.Type, RequestPending, in.FullName,
		nullify(in.ContactPhone), nullify(in.ContactEmail), nullify(in.DeceasedName),
		in.RequestedDate, in.PlotID, nullify(in.Description), nullify(in.Notes),
	))
	if err != nil {
		return nil, fmt.Errorf("create service request: %w", err)
	}
	return sr, nil
}

// GetRequest returns a service request by ID.
func (r *Repository) GetRequest(ctx context.Context, id string) (*ServiceRequest, error) {
	const q = `SELECT ` + requestColumns + ` FROM cemetery_service_requests WHERE id = $1`
	sr, err := scanRequest(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrRequestNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get service request: %w", err)
	}
	return sr, nil
}

// RequestFilter holds optional filters for listing service requests.
type RequestFilter struct {
	ChurchID string
	UserID   string // when set, restrict to this user's requests
	Status   RequestStatus
	Type     ServiceType
	Search   string // when set, matches full name, deceased name, or description
	Limit    int
	Offset   int
}

// ListRequests returns a filtered page of service requests plus the total count.
func (r *Repository) ListRequests(ctx context.Context, f RequestFilter) ([]ServiceRequest, int, error) {
	var (
		conds []string
		args  []any
	)
	if f.ChurchID != "" {
		args = append(args, f.ChurchID)
		conds = append(conds, fmt.Sprintf("church_id = $%d", len(args)))
	}
	if f.UserID != "" {
		args = append(args, f.UserID)
		conds = append(conds, fmt.Sprintf("user_id = $%d", len(args)))
	}
	if f.Status != "" {
		args = append(args, f.Status)
		conds = append(conds, fmt.Sprintf("status = $%d", len(args)))
	}
	if f.Type != "" {
		args = append(args, f.Type)
		conds = append(conds, fmt.Sprintf("type = $%d", len(args)))
	}
	if f.Search != "" {
		args = append(args, "%"+f.Search+"%")
		conds = append(conds, fmt.Sprintf(
			"(full_name ILIKE $%d OR deceased_name ILIKE $%d OR description ILIKE $%d)",
			len(args), len(args), len(args),
		))
	}

	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM cemetery_service_requests "+where, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count service requests: %w", err)
	}

	args = append(args, f.Limit, f.Offset)
	q := fmt.Sprintf(
		"SELECT %s FROM cemetery_service_requests %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d",
		requestColumns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list service requests: %w", err)
	}
	defer rows.Close()

	items := make([]ServiceRequest, 0)
	for rows.Next() {
		sr, err := scanRequest(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan service request: %w", err)
		}
		items = append(items, *sr)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate service requests: %w", err)
	}
	return items, total, nil
}

// UpdateRequestStatus updates status, admin notes, and scheduled date.
func (r *Repository) UpdateRequestStatus(ctx context.Context, id string, in RequestStatusUpdate) (*ServiceRequest, error) {
	const q = `
		UPDATE cemetery_service_requests
		SET status = $1,
		    admin_notes = COALESCE($2, admin_notes),
		    scheduled_date = $3,
		    updated_at = now()
		WHERE id = $4
		RETURNING ` + requestColumns
	sr, err := scanRequest(r.pool.QueryRow(ctx, q, in.Status, nullify(in.AdminNotes), in.ScheduledDate, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrRequestNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update service request status: %w", err)
	}
	return sr, nil
}

func nullify(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
