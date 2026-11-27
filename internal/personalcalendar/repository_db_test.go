package personalcalendar

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func newPersonalCalTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping database-backed personal calendar test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("ping: %v", err)
	}
	return pool
}

func seedCalendarUsers(t *testing.T, pool *pgxpool.Pool) (userA, userB string) {
	t.Helper()
	ctx := context.Background()
	ts := time.Now().UnixNano()
	for i, dest := range []*string{&userA, &userB} {
		email := fmt.Sprintf("cal-isolation-%d-%d@example.test", ts, i)
		if err := pool.QueryRow(ctx, `INSERT INTO users (name, email, password_hash)
			VALUES ($1, $2, 'test') RETURNING id`,
			fmt.Sprintf("cal user %d", i), email,
		).Scan(dest); err != nil {
			t.Fatalf("insert user: %v", err)
		}
	}
	t.Cleanup(func() {
		c := context.Background()
		for _, id := range []string{userA, userB} {
			_, _ = pool.Exec(c, `DELETE FROM users WHERE id = $1`, id)
		}
	})
	return userA, userB
}

// TestDBCrossUserIsolation ensures calendar rows are only readable by their owner.
func TestDBCrossUserIsolation(t *testing.T) {
	pool := newPersonalCalTestPool(t)
	defer pool.Close()
	repo := NewRepository(pool)
	userA, userB := seedCalendarUsers(t, pool)
	ctx := context.Background()

	start := time.Date(2026, 6, 1, 10, 0, 0, 0, time.UTC)
	end := start.Add(time.Hour)
	ev, err := repo.CreateEvent(ctx, userA, EventRequest{
		Title:    "A event",
		Category: CategoryPersonal,
		StartAt:  &start,
		EndAt:    &end,
	})
	if err != nil {
		t.Fatalf("create event: %v", err)
	}

	due := time.Date(2026, 6, 2, 0, 0, 0, 0, time.UTC)
	task, err := repo.CreateTask(ctx, userA, TaskRequest{
		Title:   "A task",
		DueDate: &due,
	})
	if err != nil {
		t.Fatalf("create task: %v", err)
	}

	target := 7
	goal, err := repo.CreateGoal(ctx, userA, GoalRequest{
		Title:      "A goal",
		TargetDays: &target,
	})
	if err != nil {
		t.Fatalf("create goal: %v", err)
	}

	for _, tc := range []struct {
		name string
		run  func() error
	}{
		{"event", func() error {
			_, e := repo.GetEvent(ctx, userB, ev.ID)
			return e
		}},
		{"task", func() error {
			_, e := repo.PatchTask(ctx, userB, task.ID, TaskPatch{})
			return e
		}},
		{"goal", func() error {
			_, e := repo.GetGoal(ctx, userB, goal.ID)
			return e
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if !errors.Is(tc.run(), ErrNotFound) {
				t.Fatalf("user B should not access user A %s", tc.name)
			}
		})
	}

	listEv, total, err := repo.ListEvents(ctx, userB, EventListQuery{}, 50, 0)
	if err != nil {
		t.Fatalf("list events: %v", err)
	}
	if total != 0 || len(listEv) != 0 {
		t.Fatalf("user B list events = %d, want 0", len(listEv))
	}
}