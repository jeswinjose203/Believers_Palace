package chat

import (
	"context"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// These tests run only when TEST_DATABASE_URL points at a Postgres database
// with the project's migrations applied. They verify the commit-ordered,
// per-event `seq` assignment that guarantees the polling `after` cursor never
// skips a message under concurrent posts. Run with, e.g.:
//
//	TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/believers_palace?sslmode=disable \
//	  go test ./internal/chat -run DB -v
//
// They are skipped (not failed) when the variable is unset so `make test`
// stays green without a database.

func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping database-backed chat test")
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

// seedEvent creates a church and event and returns the event ID. It registers
// a cleanup that removes the rows (messages cascade on event delete).
func seedEvent(t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()
	ctx := context.Background()
	var churchID, eventID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO churches (name) VALUES ('seq-test church') RETURNING id`,
	).Scan(&churchID); err != nil {
		t.Fatalf("insert church: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO events (church_id, title, start_date)
		 VALUES ($1, 'seq-test event', now()) RETURNING id`, churchID,
	).Scan(&eventID); err != nil {
		t.Fatalf("insert event: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM events WHERE id = $1`, eventID)
		_, _ = pool.Exec(context.Background(), `DELETE FROM churches WHERE id = $1`, churchID)
	})
	return eventID
}

// TestDBConcurrentSeqNoGaps posts many messages to the same event from many
// goroutines and asserts the assigned seqs are exactly 1..N with no gaps or
// duplicates. This is the core guarantee behind the gap-free `after` cursor.
func TestDBConcurrentSeqNoGaps(t *testing.T) {
	pool := newTestPool(t)
	defer pool.Close()
	repo := NewRepository(pool)
	eventID := seedEvent(t, pool)

	const n = 200
	var wg sync.WaitGroup
	seqs := make([]int64, n)
	errs := make([]error, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			m, err := repo.Create(context.Background(), eventID, nil, "U", nil, "hi")
			if err != nil {
				errs[i] = err
				return
			}
			seqs[i] = m.Seq
		}(i)
	}
	wg.Wait()

	seen := make(map[int64]bool, n)
	for i, err := range errs {
		if err != nil {
			t.Fatalf("create %d: %v", i, err)
		}
		if seqs[i] < 1 || seqs[i] > n {
			t.Fatalf("seq out of range: %d", seqs[i])
		}
		if seen[seqs[i]] {
			t.Fatalf("duplicate seq: %d", seqs[i])
		}
		seen[seqs[i]] = true
	}
	for s := int64(1); s <= n; s++ {
		if !seen[s] {
			t.Fatalf("missing seq: %d", s)
		}
	}
}

// TestDBAfterCursorSeesAll walks the chat using only the `after` cursor (as the
// client poll does) and asserts it observes every message exactly once.
func TestDBAfterCursorSeesAll(t *testing.T) {
	pool := newTestPool(t)
	defer pool.Close()
	repo := NewRepository(pool)
	eventID := seedEvent(t, pool)

	const n = 150
	for i := 0; i < n; i++ {
		if _, err := repo.Create(context.Background(), eventID, nil, "U", nil, "m"); err != nil {
			t.Fatalf("create: %v", err)
		}
	}

	var after int64
	seen := 0
	for {
		page, hasMore, err := repo.ListCursor(context.Background(), eventID, CursorQuery{After: after, Limit: 20})
		if err != nil {
			t.Fatalf("list cursor: %v", err)
		}
		if len(page) == 0 {
			break
		}
		for i, m := range page {
			if m.Seq != after+int64(i)+1 {
				t.Fatalf("out-of-order seq: got %d after %d", m.Seq, after)
			}
		}
		after = page[len(page)-1].Seq
		seen += len(page)
		if !hasMore {
			break
		}
	}
	if seen != n {
		t.Fatalf("cursor saw %d messages, want %d", seen, n)
	}
}
