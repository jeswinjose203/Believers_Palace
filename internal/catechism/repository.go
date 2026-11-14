package catechism

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

// ErrNotFound is returned when a resource does not exist.
var ErrNotFound = errors.New("not found")

// ErrClassFull is returned when enrollment would exceed capacity.
var ErrClassFull = errors.New("class is full")

// ErrDuplicateEnrollment is returned when the student already has an active enrollment.
var ErrDuplicateEnrollment = errors.New("duplicate active enrollment")

// Repository provides access to catechism data.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a catechism repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const classColumns = `id, church_id, name, description, level, min_age, max_age,
	teacher_user_id, teacher_name, schedule, location, start_date, end_date,
	capacity, status, image, created_at, updated_at`

func scanClass(row pgx.Row) (*Class, error) {
	var (
		c                                      Class
		desc, teacherName, loc, image          *string
		teacherID                              *string
		scheduleRaw                            []byte
		minAge, maxAge                         *int
	)
	if err := row.Scan(
		&c.ID, &c.ChurchID, &c.Name, &desc, &c.Level, &minAge, &maxAge,
		&teacherID, &teacherName, &scheduleRaw, &loc,
		&c.StartDate, &c.EndDate, &c.Capacity, &c.Status, &image,
		&c.CreatedAt, &c.UpdatedAt,
	); err != nil {
		return nil, err
	}
	if desc != nil {
		c.Description = *desc
	}
	c.MinAge = minAge
	c.MaxAge = maxAge
	c.TeacherUserID = teacherID
	if teacherName != nil {
		c.TeacherName = *teacherName
	}
	slots, err := scheduleFromJSON(scheduleRaw)
	if err != nil {
		return nil, err
	}
	c.Schedule = slots
	if loc != nil {
		c.Location = *loc
	}
	if image != nil {
		c.Image = *image
	}
	return &c, nil
}

func nullify(s string) *string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return &s
}

// CreateClass inserts a new catechism class.
func (r *Repository) CreateClass(ctx context.Context, churchID string, in ClassRequest) (*Class, error) {
	status := in.Status
	if status == "" {
		status = StatusDraft
	}
	schedJSON, err := scheduleToJSON(in.Schedule)
	if err != nil {
		return nil, fmt.Errorf("marshal schedule: %w", err)
	}
	const q = `
		INSERT INTO catechism_classes (
			church_id, name, description, level, min_age, max_age,
			teacher_user_id, teacher_name, schedule, location,
			start_date, end_date, capacity, status, image
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
		RETURNING ` + classColumns
	c, err := scanClass(r.pool.QueryRow(ctx, q,
		churchID, in.Name, nullify(in.Description), in.Level, in.MinAge, in.MaxAge,
		in.TeacherUserID, nullify(in.TeacherName), schedJSON, nullify(in.Location),
		in.StartDate, in.EndDate, *in.Capacity, status, nullify(in.Image),
	))
	if err != nil {
		return nil, fmt.Errorf("create class: %w", err)
	}
	return c, nil
}

// GetClassByID returns a class by ID.
func (r *Repository) GetClassByID(ctx context.Context, id string) (*Class, error) {
	const q = `SELECT ` + classColumns + ` FROM catechism_classes WHERE id = $1`
	c, err := scanClass(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get class: %w", err)
	}
	return c, nil
}

// ListClassesByChurch returns a page of classes for a church.
func (r *Repository) ListClassesByChurch(
	ctx context.Context, churchID, search string, status ClassStatus, level ClassLevel,
	limit, offset int,
) ([]Class, int, error) {
	args := []any{churchID}
	where := "WHERE church_id = $1"
	if search != "" {
		args = append(args, "%"+search+"%")
		where += fmt.Sprintf(" AND (name ILIKE $%d OR description ILIKE $%d)", len(args), len(args))
	}
	if status != "" {
		args = append(args, status)
		where += fmt.Sprintf(" AND status = $%d", len(args))
	}
	if level != "" {
		args = append(args, level)
		where += fmt.Sprintf(" AND level = $%d", len(args))
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM catechism_classes "+where, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count classes: %w", err)
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(
		"SELECT %s FROM catechism_classes %s ORDER BY start_date DESC LIMIT $%d OFFSET $%d",
		classColumns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list classes: %w", err)
	}
	defer rows.Close()

	var items []Class
	for rows.Next() {
		c, err := scanClass(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, *c)
	}
	return items, total, rows.Err()
}

// UpdateClass updates a class.
func (r *Repository) UpdateClass(ctx context.Context, id string, in ClassRequest) (*Class, error) {
	status := in.Status
	if status == "" {
		status = StatusDraft
	}
	schedJSON, err := scheduleToJSON(in.Schedule)
	if err != nil {
		return nil, fmt.Errorf("marshal schedule: %w", err)
	}
	const q = `
		UPDATE catechism_classes SET
			name = $2, description = $3, level = $4, min_age = $5, max_age = $6,
			teacher_user_id = $7, teacher_name = $8, schedule = $9, location = $10,
			start_date = $11, end_date = $12, capacity = $13, status = $14, image = $15,
			updated_at = now()
		WHERE id = $1
		RETURNING ` + classColumns
	c, err := scanClass(r.pool.QueryRow(ctx, q,
		id, in.Name, nullify(in.Description), in.Level, in.MinAge, in.MaxAge,
		in.TeacherUserID, nullify(in.TeacherName), schedJSON, nullify(in.Location),
		in.StartDate, in.EndDate, *in.Capacity, status, nullify(in.Image),
	))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update class: %w", err)
	}
	return c, nil
}

// DeleteClass removes a class.
func (r *Repository) DeleteClass(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM catechism_classes WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete class: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// CountApprovedEnrollments counts active seat-taking enrollments (pending + approved).
func (r *Repository) CountApprovedEnrollments(ctx context.Context, classID string) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx, `
		SELECT count(*) FROM catechism_enrollments
		WHERE class_id = $1 AND status IN ('pending', 'approved')
	`, classID).Scan(&n)
	return n, err
}

// GuardianEnrolledInClass reports whether the guardian has an active enrollment in the class.
func (r *Repository) GuardianEnrolledInClass(ctx context.Context, classID, guardianID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM catechism_enrollments
			WHERE class_id = $1 AND guardian_id = $2 AND status IN ('pending', 'approved')
		)
	`, classID, guardianID).Scan(&exists)
	return exists, err
}

const enrollmentColumns = `id, class_id, guardian_id, student_name, date_of_birth, notes, status, created_at, updated_at`

func scanEnrollment(row pgx.Row) (*Enrollment, error) {
	var e Enrollment
	var notes *string
	if err := row.Scan(
		&e.ID, &e.ClassID, &e.GuardianID, &e.StudentName, &e.DateOfBirth,
		&notes, &e.Status, &e.CreatedAt, &e.UpdatedAt,
	); err != nil {
		return nil, err
	}
	if notes != nil {
		e.Notes = *notes
	}
	return &e, nil
}

// CreateEnrollment inserts an enrollment inside a transaction with capacity and duplicate checks.
func (r *Repository) CreateEnrollment(ctx context.Context, classID, guardianID string, in EnrollmentRequest) (*Enrollment, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var status ClassStatus
	var capacity int
	if err := tx.QueryRow(ctx, `
		SELECT status, capacity FROM catechism_classes WHERE id = $1 FOR UPDATE
	`, classID).Scan(&status, &capacity); errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	} else if err != nil {
		return nil, err
	}

	var count int
	if err := tx.QueryRow(ctx, `
		SELECT count(*) FROM catechism_enrollments
		WHERE class_id = $1 AND status IN ('pending', 'approved')
	`, classID).Scan(&count); err != nil {
		return nil, err
	}
	if count >= capacity {
		return nil, ErrClassFull
	}

	const q = `
		INSERT INTO catechism_enrollments (class_id, guardian_id, student_name, date_of_birth, notes, status)
		VALUES ($1, $2, $3, $4, $5, 'pending')
		RETURNING ` + enrollmentColumns
	e, err := scanEnrollment(tx.QueryRow(ctx, q,
		classID, guardianID, strings.TrimSpace(in.StudentName), in.DateOfBirth, nullify(in.Notes),
	))
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return nil, ErrDuplicateEnrollment
		}
		return nil, fmt.Errorf("create enrollment: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return e, nil
}

// GetEnrollmentByID returns an enrollment by ID.
func (r *Repository) GetEnrollmentByID(ctx context.Context, id string) (*Enrollment, error) {
	const q = `SELECT ` + enrollmentColumns + ` FROM catechism_enrollments WHERE id = $1`
	e, err := scanEnrollment(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get enrollment: %w", err)
	}
	return e, nil
}

// ListEnrollmentsByClass lists enrollments for a class; when guardianID is set, only that guardian's rows.
func (r *Repository) ListEnrollmentsByClass(
	ctx context.Context, classID, search, guardianID string, limit, offset int,
) ([]Enrollment, int, error) {
	args := []any{classID}
	where := "WHERE class_id = $1"
	if guardianID != "" {
		args = append(args, guardianID)
		where += fmt.Sprintf(" AND guardian_id = $%d", len(args))
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		where += fmt.Sprintf(" AND student_name ILIKE $%d", len(args))
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM catechism_enrollments "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(
		"SELECT %s FROM catechism_enrollments %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d",
		enrollmentColumns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var items []Enrollment
	for rows.Next() {
		e, err := scanEnrollment(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, *e)
	}
	return items, total, rows.Err()
}

// ListEnrollmentsByGuardian lists enrollments for a guardian with optional search on student/class name.
func (r *Repository) ListEnrollmentsByGuardian(
	ctx context.Context, guardianID, search string, limit, offset int,
) ([]Enrollment, int, error) {
	args := []any{guardianID}
	where := "WHERE e.guardian_id = $1"
	join := `FROM catechism_enrollments e
		JOIN catechism_classes c ON c.id = e.class_id`
	if search != "" {
		args = append(args, "%"+search+"%")
		where += fmt.Sprintf(" AND (e.student_name ILIKE $%d OR c.name ILIKE $%d)", len(args), len(args))
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) "+join+" "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(`
		SELECT e.id, e.class_id, e.guardian_id, e.student_name, e.date_of_birth, e.notes, e.status,
			e.created_at, e.updated_at, c.name, c.level, c.status
		%s %s ORDER BY e.created_at DESC LIMIT $%d OFFSET $%d`,
		join, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var items []Enrollment
	for rows.Next() {
		var e Enrollment
		var notes *string
		if err := rows.Scan(
			&e.ID, &e.ClassID, &e.GuardianID, &e.StudentName, &e.DateOfBirth, &notes, &e.Status,
			&e.CreatedAt, &e.UpdatedAt, &e.ClassName, &e.ClassLevel, &e.ClassStatus,
		); err != nil {
			return nil, 0, err
		}
		if notes != nil {
			e.Notes = *notes
		}
		items = append(items, e)
	}
	return items, total, rows.Err()
}

// UpdateEnrollmentStatus sets enrollment status.
func (r *Repository) UpdateEnrollmentStatus(ctx context.Context, id string, status EnrollmentStatus) (*Enrollment, error) {
	const q = `
		UPDATE catechism_enrollments SET status = $2, updated_at = now()
		WHERE id = $1
		RETURNING ` + enrollmentColumns
	e, err := scanEnrollment(r.pool.QueryRow(ctx, q, id, status))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update enrollment status: %w", err)
	}
	return e, nil
}

// GuardianHasApprovedEnrollment reports whether the guardian has an approved enrollment for the class.
func (r *Repository) GuardianHasApprovedEnrollment(ctx context.Context, classID, guardianID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM catechism_enrollments
			WHERE class_id = $1 AND guardian_id = $2 AND status = 'approved'
		)
	`, classID, guardianID).Scan(&exists)
	return exists, err
}

const sessionColumns = `id, class_id, title, topic, session_date, start_time, end_time, notes, created_at, updated_at`

func scanSession(row pgx.Row) (*Session, error) {
	var s Session
	var topic, notes *string
	var startTime, endTime time.Time
	if err := row.Scan(
		&s.ID, &s.ClassID, &s.Title, &topic, &s.SessionDate,
		&startTime, &endTime, &notes, &s.CreatedAt, &s.UpdatedAt,
	); err != nil {
		return nil, err
	}
	if topic != nil {
		s.Topic = *topic
	}
	if notes != nil {
		s.Notes = *notes
	}
	s.StartTime = startTime.Format("15:04:05")
	s.EndTime = endTime.Format("15:04:05")
	return &s, nil
}

// CreateSession inserts a lesson session.
func (r *Repository) CreateSession(ctx context.Context, classID string, in SessionRequest) (*Session, error) {
	const q = `
		INSERT INTO catechism_sessions (class_id, title, topic, session_date, start_time, end_time, notes)
		VALUES ($1, $2, $3, $4, $5::time, $6::time, $7)
		RETURNING ` + sessionColumns
	s, err := scanSession(r.pool.QueryRow(ctx, q,
		classID, in.Title, nullify(in.Topic), in.SessionDate, in.StartTime, in.EndTime, nullify(in.Notes),
	))
	if err != nil {
		return nil, fmt.Errorf("create session: %w", err)
	}
	return s, nil
}

// GetSessionByID returns a session by ID.
func (r *Repository) GetSessionByID(ctx context.Context, id string) (*Session, error) {
	const q = `SELECT ` + sessionColumns + ` FROM catechism_sessions WHERE id = $1`
	s, err := scanSession(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get session: %w", err)
	}
	return s, nil
}

// ListSessionsByClass returns sessions for a class.
func (r *Repository) ListSessionsByClass(ctx context.Context, classID, search string, limit, offset int) ([]Session, int, error) {
	args := []any{classID}
	where := "WHERE class_id = $1"
	if search != "" {
		args = append(args, "%"+search+"%")
		where += fmt.Sprintf(" AND (title ILIKE $%d OR topic ILIKE $%d)", len(args), len(args))
	}

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM catechism_sessions "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(
		"SELECT %s FROM catechism_sessions %s ORDER BY session_date DESC LIMIT $%d OFFSET $%d",
		sessionColumns, where, len(args)-1, len(args),
	)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var items []Session
	for rows.Next() {
		s, err := scanSession(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, *s)
	}
	return items, total, rows.Err()
}

// UpdateSession updates a session.
func (r *Repository) UpdateSession(ctx context.Context, id string, in SessionRequest) (*Session, error) {
	const q = `
		UPDATE catechism_sessions SET
			title = $2, topic = $3, session_date = $4,
			start_time = $5::time, end_time = $6::time, notes = $7,
			updated_at = now()
		WHERE id = $1
		RETURNING ` + sessionColumns
	s, err := scanSession(r.pool.QueryRow(ctx, q,
		id, in.Title, nullify(in.Topic), in.SessionDate, in.StartTime, in.EndTime, nullify(in.Notes),
	))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update session: %w", err)
	}
	return s, nil
}

// DeleteSession removes a session.
func (r *Repository) DeleteSession(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM catechism_sessions WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete session: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}