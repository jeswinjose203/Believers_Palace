package event

import (
	"context"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestDBConcurrentRegistrationsRespectCapacity(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("requires a migrated disposable database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	var churchID, eventID string
	if err := pool.QueryRow(ctx, `INSERT INTO churches (name,address) VALUES ('Capacity test','Test') RETURNING id`).Scan(&churchID); err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM churches WHERE id=$1`, churchID)
	const capacity = 5
	if err := pool.QueryRow(ctx, `INSERT INTO events (church_id,title,start_date,capacity)
		VALUES ($1,'Capacity test',now(),$2) RETURNING id`, churchID, capacity).Scan(&eventID); err != nil {
		t.Fatal(err)
	}
	const attempts = 32
	repo := NewRepository(pool)
	errs := make(chan error, attempts)
	var workers sync.WaitGroup
	for range attempts {
		workers.Add(1)
		go func() {
			defer workers.Done()
			_, err := repo.CreateRegistration(ctx, eventID, nil, RegistrationRequest{})
			errs <- err
		}()
	}
	workers.Wait()
	close(errs)
	registered := 0
	for err := range errs {
		if err == nil {
			registered++
		} else if !errors.Is(err, ErrRegistrationUnavailable) {
			t.Errorf("unexpected registration error: %v", err)
		}
	}
	if registered != capacity {
		t.Fatalf("registered %d attendees for capacity %d", registered, capacity)
	}
}
