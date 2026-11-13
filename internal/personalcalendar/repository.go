package personalcalendar
 
import (
    "context"
    "encoding/json"
    "errors"
    "fmt"
    "time"
 
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgconn"
    "github.com/jackc/pgx/v5/pgxpool"
)
 
// ErrNotFound is returned when a resource does not exist or is not owned by the user.
var ErrNotFound = errors.New("not found")
 
// Repository provides SQL access for personal calendar data.
type Repository struct {
    pool *pgxpool.Pool
}
 
// NewRepository creates a personal calendar repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
    return &Repository{pool: pool}
}
 
const eventCols = `id, user_id, title, description, category, color, start_at, end_at, all_day,
    recurrence, recurrence_interval, recurrence_until, reminder_minutes, created_at, updated_at`
 
func scanEvent(row pgx.Row) (*Event, error) {
    var (
        e           Event
        desc, color *string
        recUntil    *time.Time
    )
    if err := row.Scan(
        &e.ID, new(string), &e.Title, &desc, &e.Category, &color,
        &e.StartAt, &e.EndAt, &e.AllDay, &e.Recurrence, &e.RecurrenceInterval,
        &recUntil, &e.ReminderMinutes, &e.CreatedAt, &e.UpdatedAt,
    ); err != nil {
        return nil, err
    }
    if desc != nil {
        e.Description = *desc
    }
    if color != nil {
        e.Color = *color
    }
    e.RecurrenceUntil = recUntil
    return &e, nil
}
 
func (r *Repository) GetPreferences(ctx context.Context, userID string) (*Preferences, error) {
    const q = `SELECT theme, date_format, week_starts_on, holiday_country, category_colors
        FROM user_calendar_preferences WHERE user_id = $1`
    var (
        p           Preferences
        colorsBytes []byte
    )
    err := r.pool.QueryRow(ctx, q, userID).Scan(
        &p.Theme, &p.DateFormat, &p.WeekStartsOn, &p.HolidayCountry, &colorsBytes,
    )
    if errors.Is(err, pgx.ErrNoRows) {
        return nil, ErrNotFound
    }
    if err != nil {
        return nil, fmt.Errorf("get preferences: %w", err)
    }
    _ = json.Unmarshal(colorsBytes, &p.CategoryColors)
    if p.CategoryColors == nil {
        p.CategoryColors = DefaultCategoryColors()
    }
    return &p, nil
}
 
func (r *Repository) UpsertPreferences(ctx context.Context, userID string, p Preferences) (*Preferences, error) {
    colors, err := json.Marshal(p.CategoryColors)
    if err != nil {
        return nil, err
    }
    const q = `
        INSERT INTO user_calendar_preferences (user_id, theme, date_format, week_starts_on, holiday_country, category_colors)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (user_id) DO UPDATE SET
            theme = EXCLUDED.theme,
            date_format = EXCLUDED.date_format,
            week_starts_on = EXCLUDED.week_starts_on,
            holiday_country = EXCLUDED.holiday_country,
            category_colors = EXCLUDED.category_colors,
            updated_at = now()
        RETURNING theme, date_format, week_starts_on, holiday_country, category_colors`
    var colorsOut []byte
    out := &Preferences{}
    err = r.pool.QueryRow(ctx, q, userID, p.Theme, p.DateFormat, p.WeekStartsOn, p.HolidayCountry, colors).Scan(
        &out.Theme, &out.DateFormat, &out.WeekStartsOn, &out.HolidayCountry, &colorsOut,
    )
    if err != nil {
        return nil, fmt.Errorf("upsert preferences: %w", err)
    }
    _ = json.Unmarshal(colorsOut, &out.CategoryColors)
    return out, nil
}
 
func (r *Repository) CreateEvent(ctx context.Context, userID string, in EventRequest) (*Event, error) {
    rec := RecurrenceNone
    if in.Recurrence != nil {
        rec = *in.Recurrence
    }
    interval := 1
    if in.RecurrenceInterval != nil && *in.RecurrenceInterval > 0 {
        interval = *in.RecurrenceInterval
    }
    allDay := false
    if in.AllDay != nil {
        allDay = *in.AllDay
    }
    reminders := in.ReminderMinutes
    if reminders == nil {
        reminders = []int{}
    }
    const q = `
        INSERT INTO calendar_events (user_id, title, description, category, color, start_at, end_at, all_day,
            recurrence, recurrence_interval, recurrence_until, reminder_minutes)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
        RETURNING ` + eventCols
    row := r.pool.QueryRow(ctx, q,
        userID, in.Title, nullStr(in.Description), in.Category, nullStr(in.Color),
        in.StartAt, in.EndAt, allDay, rec, interval, in.RecurrenceUntil, reminders,
    )
    e, err := scanEvent(row)
    if err != nil {
        return nil, fmt.Errorf("create event: %w", err)
    }
    return e, nil
}
 
func (r *Repository) GetEvent(ctx context.Context, userID, eventID string) (*Event, error) {
    q := `SELECT ` + eventCols + ` FROM calendar_events WHERE id = $1 AND user_id = $2`
    e, err := scanEvent(r.pool.QueryRow(ctx, q, eventID, userID))
    if errors.Is(err, pgx.ErrNoRows) {
        return nil, ErrNotFound
    }
    if err != nil {
        return nil, fmt.Errorf("get event: %w", err)
    }
    return e, nil
}
 
func (r *Repository) ListEvents(ctx context.Context, userID, search, category string, limit, offset int) ([]Event, int, error) {
    args := []any{userID}
    where := "WHERE user_id = $1"
    if search != "" {
        args = append(args, "%"+search+"%")
        where += fmt.Sprintf(" AND (title ILIKE $%d OR description ILIKE $%d)", len(args), len(args))
    }
    if category != "" {
        args = append(args, category)
        where += fmt.Sprintf(" AND category = $%d", len(args))
    }
    var total int
    if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM calendar_events "+where, args...).Scan(&total); err != nil {
        return nil, 0, err
    }
    args = append(args, limit, offset)
    q := fmt.Sprintf(`SELECT %s FROM calendar_events %s ORDER BY start_at DESC LIMIT $%d OFFSET $%d`,
        eventCols, where, len(args)-1, len(args))
    rows, err := r.pool.Query(ctx, q, args...)
    if err != nil {
        return nil, 0, err
    }
    defer rows.Close()
    var items []Event
    for rows.Next() {
        e, err := scanEvent(rows)
        if err != nil {
            return nil, 0, err
        }
        items = append(items, *e)
    }
    return items, total, rows.Err()
}
 
func (r *Repository) ListEventsForUser(ctx context.Context, userID string) ([]Event, error) {
    q := `SELECT ` + eventCols + ` FROM calendar_events WHERE user_id = $1 ORDER BY start_at`
    rows, err := r.pool.Query(ctx, q, userID)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    var items []Event
    for rows.Next() {
        e, err := scanEvent(rows)
        if err != nil {
            return nil, err
        }
        items = append(items, *e)
    }
    return items, rows.Err()
}
 
func (r *Repository) UpdateEvent(ctx context.Context, userID, eventID string, in EventRequest) (*Event, error) {
    rec := RecurrenceNone
    if in.Recurrence != nil {
        rec = *in.Recurrence
    }
    interval := 1
    if in.RecurrenceInterval != nil && *in.RecurrenceInterval > 0 {
        interval = *in.RecurrenceInterval
    }
    allDay := false
    if in.AllDay != nil {
        allDay = *in.AllDay
    }
    reminders := in.ReminderMinutes
    if reminders == nil {
        reminders = []int{}
    }
    const q = `
        UPDATE calendar_events SET
            title = COALESCE($3, title),
            description = $4,
            category = COALESCE($5, category),
            color = $6,
            start_at = COALESCE($7, start_at),
            end_at = COALESCE($8, end_at),
            all_day = $9,
            recurrence = $10,
            recurrence_interval = $11,
            recurrence_until = $12,
            reminder_minutes = $13,
            updated_at = now()
        WHERE id = $1 AND user_id = $2
        RETURNING ` + eventCols
    e, err := scanEvent(r.pool.QueryRow(ctx, q,
        eventID, userID, in.Title, nullStr(in.Description), in.Category, nullStr(in.Color),
        in.StartAt, in.EndAt, allDay, rec, interval, in.RecurrenceUntil, reminders,
    ))
    if errors.Is(err, pgx.ErrNoRows) {
        return nil, ErrNotFound
    }
    if err != nil {
        return nil, fmt.Errorf("update event: %w", err)
    }
    return e, nil
}
 
func (r *Repository) DeleteEvent(ctx context.Context, userID, eventID string) error {
    tag, err := r.pool.Exec(ctx, `DELETE FROM calendar_events WHERE id = $1 AND user_id = $2`, eventID, userID)
    if err != nil {
        return err
    }
    if tag.RowsAffected() == 0 {
        return ErrNotFound
    }
    return nil
}
 
func scanTask(row pgx.Row) (*Task, error) {
    var t Task
    var desc *string
    var due time.Time
    if err := row.Scan(&t.ID, new(string), &t.Title, &desc, &due, &t.Completed, &t.CreatedAt, &t.UpdatedAt); err != nil {
        return nil, err
    }
    if desc != nil {
        t.Description = *desc
    }
    t.DueDate = due
    return &t, nil
}
 
const taskCols = `id, user_id, title, description, due_date, completed, created_at, updated_at`
 
func (r *Repository) CreateTask(ctx context.Context, userID string, in TaskRequest) (*Task, error) {
    const q = `INSERT INTO calendar_tasks (user_id, title, description, due_date)
        VALUES ($1,$2,$3,$4) RETURNING ` + taskCols
    t, err := scanTask(r.pool.QueryRow(ctx, q, userID, in.Title, nullStr(in.Description), in.DueDate))
    if err != nil {
        return nil, fmt.Errorf("create task: %w", err)
    }
    return t, nil
}
 
func (r *Repository) ListTasks(ctx context.Context, userID string, limit, offset int) ([]Task, int, error) {
    var total int
    if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM calendar_tasks WHERE user_id = $1`, userID).Scan(&total); err != nil {
        return nil, 0, err
    }
    q := `SELECT ` + taskCols + ` FROM calendar_tasks WHERE user_id = $1 ORDER BY due_date LIMIT $2 OFFSET $3`
    rows, err := r.pool.Query(ctx, q, userID, limit, offset)
    if err != nil {
        return nil, 0, err
    }
    defer rows.Close()
    var items []Task
    for rows.Next() {
        t, err := scanTask(rows)
        if err != nil {
            return nil, 0, err
        }
        items = append(items, *t)
    }
    return items, total, rows.Err()
}
 
func (r *Repository) ListTasksDueInRange(ctx context.Context, userID string, from, to time.Time) ([]Task, error) {
    q := `SELECT ` + taskCols + ` FROM calendar_tasks WHERE user_id = $1 AND due_date >= $2::date AND due_date <= $3::date ORDER BY due_date`
    rows, err := r.pool.Query(ctx, q, userID, from, to)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    var items []Task
    for rows.Next() {
        t, err := scanTask(rows)
        if err != nil {
            return nil, err
        }
        items = append(items, *t)
    }
    return items, rows.Err()
}
 
func (r *Repository) PatchTask(ctx context.Context, userID, taskID string, in TaskPatch) (*Task, error) {
    const q = `
        UPDATE calendar_tasks SET
            title = COALESCE($3, title),
            description = COALESCE($4, description),
            due_date = COALESCE($5, due_date),
            completed = COALESCE($6, completed),
            updated_at = now()
        WHERE id = $1 AND user_id = $2
        RETURNING ` + taskCols
    t, err := scanTask(r.pool.QueryRow(ctx, q, taskID, userID, in.Title, in.Description, in.DueDate, in.Completed))
    if errors.Is(err, pgx.ErrNoRows) {
        return nil, ErrNotFound
    }
    if err != nil {
        return nil, err
    }
    return t, nil
}
 
func (r *Repository) DeleteTask(ctx context.Context, userID, taskID string) error {
    tag, err := r.pool.Exec(ctx, `DELETE FROM calendar_tasks WHERE id = $1 AND user_id = $2`, taskID, userID)
    if err != nil {
        return err
    }
    if tag.RowsAffected() == 0 {
        return ErrNotFound
    }
    return nil
}
 
const goalCols = `id, user_id, title, description, target_days, tracking_mode, start_date, end_date,
    status, completed_at, created_at, updated_at`
 
func scanGoal(row pgx.Row) (*Goal, error) {
    var g Goal
    var desc *string
    var start, end, completed *time.Time
    if err := row.Scan(
        &g.ID, new(string), &g.Title, &desc, &g.TargetDays, &g.TrackingMode,
        &start, &end, &g.Status, &completed, &g.CreatedAt, &g.UpdatedAt,
    ); err != nil {
        return nil, err
    }
    if desc != nil {
        g.Description = *desc
    }
    g.StartDate = start
    g.EndDate = end
    g.CompletedAt = completed
    return &g, nil
}
 
func (r *Repository) CreateGoal(ctx context.Context, userID string, in GoalRequest) (*Goal, error) {
    mode := TrackingTotal
    if in.TrackingMode != nil {
        mode = *in.TrackingMode
    }
    target := 1
    if in.TargetDays != nil {
        target = *in.TargetDays
    }
    const q = `INSERT INTO calendar_goals (user_id, title, description, target_days, tracking_mode, start_date, end_date)
        VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING ` + goalCols
    g, err := scanGoal(r.pool.QueryRow(ctx, q, userID, in.Title, nullStr(in.Description), target, mode, in.StartDate, in.EndDate))
    if err != nil {
        return nil, err
    }
    return g, nil
}
 
func (r *Repository) ListGoals(ctx context.Context, userID, status string, limit, offset int) ([]Goal, int, error) {
    args := []any{userID}
    where := "WHERE user_id = $1"
    if status != "" {
        args = append(args, status)
        where += fmt.Sprintf(" AND status = $%d", len(args))
    }
    var total int
    if err := r.pool.QueryRow(ctx, "SELECT count(*) FROM calendar_goals "+where, args...).Scan(&total); err != nil {
        return nil, 0, err
    }
    args = append(args, limit, offset)
    q := fmt.Sprintf(`SELECT %s FROM calendar_goals %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d`,
        goalCols, where, len(args)-1, len(args))
    rows, err := r.pool.Query(ctx, q, args...)
    if err != nil {
        return nil, 0, err
    }
    defer rows.Close()
    var items []Goal
    for rows.Next() {
        g, err := scanGoal(rows)
        if err != nil {
            return nil, 0, err
        }
        items = append(items, *g)
    }
    return items, total, rows.Err()
}
 
func (r *Repository) ListActiveGoals(ctx context.Context, userID string) ([]Goal, error) {
    q := `SELECT ` + goalCols + ` FROM calendar_goals WHERE user_id = $1 AND status = 'active' ORDER BY created_at`
    rows, err := r.pool.Query(ctx, q, userID)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    var items []Goal
    for rows.Next() {
        g, err := scanGoal(rows)
        if err != nil {
            return nil, err
        }
        items = append(items, *g)
    }
    return items, rows.Err()
}
 
func (r *Repository) GetGoal(ctx context.Context, userID, goalID string) (*Goal, error) {
    g, err := scanGoal(r.pool.QueryRow(ctx, `SELECT `+goalCols+` FROM calendar_goals WHERE id = $1 AND user_id = $2`, goalID, userID))
    if errors.Is(err, pgx.ErrNoRows) {
        return nil, ErrNotFound
    }
    return g, err
}
 
func (r *Repository) UpdateGoal(ctx context.Context, userID, goalID string, in GoalRequest) (*Goal, error) {
    status := GoalActive
    if in.Status != nil {
        status = *in.Status
    }
    mode := TrackingTotal
    if in.TrackingMode != nil {
        mode = *in.TrackingMode
    }
    target := 1
    if in.TargetDays != nil {
        target = *in.TargetDays
    }
    const q = `
        UPDATE calendar_goals SET
            title = COALESCE($3, title),
            description = $4,
            target_days = $5,
            tracking_mode = $6,
            start_date = $7,
            end_date = $8,
            status = $9,
            updated_at = now()
        WHERE id = $1 AND user_id = $2
        RETURNING ` + goalCols
    g, err := scanGoal(r.pool.QueryRow(ctx, q, goalID, userID, in.Title, nullStr(in.Description), target, mode, in.StartDate, in.EndDate, status))
    if errors.Is(err, pgx.ErrNoRows) {
        return nil, ErrNotFound
    }
    return g, err
}
 
func (r *Repository) MarkGoalCompleted(ctx context.Context, goalID string, at time.Time) error {
    _, err := r.pool.Exec(ctx, `UPDATE calendar_goals SET status = 'completed', completed_at = $2, updated_at = now() WHERE id = $1`, goalID, at)
    return err
}
 
func (r *Repository) DeleteGoal(ctx context.Context, userID, goalID string) error {
    tag, err := r.pool.Exec(ctx, `DELETE FROM calendar_goals WHERE id = $1 AND user_id = $2`, goalID, userID)
    if err != nil {
        return err
    }
    if tag.RowsAffected() == 0 {
        return ErrNotFound
    }
    return nil
}
 
func (r *Repository) ListCheckInDates(ctx context.Context, goalID string) ([]time.Time, error) {
    rows, err := r.pool.Query(ctx, `SELECT checkin_date FROM calendar_goal_checkins WHERE goal_id = $1 ORDER BY checkin_date`, goalID)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    var dates []time.Time
    for rows.Next() {
        var d time.Time
        if err := rows.Scan(&d); err != nil {
            return nil, err
        }
        dates = append(dates, d)
    }
    return dates, rows.Err()
}
 
func (r *Repository) HasCheckIn(ctx context.Context, goalID string, day time.Time) (bool, error) {
    var n int
    err := r.pool.QueryRow(ctx,
        `SELECT count(*) FROM calendar_goal_checkins WHERE goal_id = $1 AND checkin_date = $2::date`,
        goalID, day,
    ).Scan(&n)
    return n > 0, err
}
 
func (r *Repository) UpsertCheckIn(ctx context.Context, goalID string, day time.Time, note string) error {
    _, err := r.pool.Exec(ctx, `
        INSERT INTO calendar_goal_checkins (goal_id, checkin_date, note)
        VALUES ($1, $2::date, $3)
        ON CONFLICT (goal_id, checkin_date) DO UPDATE SET note = EXCLUDED.note`,
        goalID, day, nullStr(note),
    )
    return err
}
 
func (r *Repository) DeleteCheckIn(ctx context.Context, goalID string, day time.Time) error {
    tag, err := r.pool.Exec(ctx, `DELETE FROM calendar_goal_checkins WHERE goal_id = $1 AND checkin_date = $2::date`, goalID, day)
    if err != nil {
        return err
    }
    if tag.RowsAffected() == 0 {
        return ErrNotFound
    }
    return nil
}
 
func (r *Repository) CountCheckIns(ctx context.Context, goalID string) (int, error) {
    var n int
    err := r.pool.QueryRow(ctx, `SELECT count(*) FROM calendar_goal_checkins WHERE goal_id = $1`, goalID).Scan(&n)
    return n, err
}
 
func (r *Repository) TryUnlockAchievement(ctx context.Context, userID, code string, goalID *string) (bool, error) {
    const q = `INSERT INTO user_achievements (user_id, achievement_code, goal_id)
        VALUES ($1, $2, $3)
        ON CONFLICT DO NOTHING`
    tag, err := r.pool.Exec(ctx, q, userID, code, goalID)
    if err != nil {
        var pgErr *pgconn.PgError
        if errors.As(err, &pgErr) {
            return false, err
        }
        return false, err
    }
    return tag.RowsAffected() > 0, nil
}
 
func (r *Repository) CountCompletedGoals(ctx context.Context, userID string) (int, error) {
    var n int
    err := r.pool.QueryRow(ctx, `SELECT count(*) FROM calendar_goals WHERE user_id = $1 AND status = 'completed'`, userID).Scan(&n)
    return n, err
}
 
func (r *Repository) ListAchievements(ctx context.Context, userID string) ([]Achievement, error) {
    const q = `
        SELECT d.code, d.title, d.description, d.icon,
            u.unlocked_at IS NOT NULL,
            u.unlocked_at,
            u.goal_id
        FROM achievement_definitions d
        LEFT JOIN user_achievements u ON u.achievement_code = d.code AND u.user_id = $1
            AND (d.code != 'goal_complete' OR u.goal_id IS NOT NULL)
        ORDER BY d.code`
    rows, err := r.pool.Query(ctx, q, userID)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    var items []Achievement
    for rows.Next() {
        var a Achievement
        var unlockedAt *time.Time
        var goalID *string
        if err := rows.Scan(&a.Code, &a.Title, &a.Description, &a.Icon, &a.Unlocked, &unlockedAt, &goalID); err != nil {
            return nil, err
        }
        a.UnlockedAt = unlockedAt
        a.GoalID = goalID
        items = append(items, a)
    }
    return items, rows.Err()
}
 
func nullStr(s string) *string {
    if s == "" {
        return nil
    }
    return &s
}