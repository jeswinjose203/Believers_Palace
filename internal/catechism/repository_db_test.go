package catechism

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestDBEnrollmentRejectsStaleWrites(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("requires a migrated disposable database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	var church, guardian, class string
	if err := pool.QueryRow(ctx, `INSERT INTO churches (name,address)
		VALUES ('Enrollment state test','Test') RETURNING id`).Scan(&church); err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM churches WHERE id=$1`, church)
	if err := pool.QueryRow(ctx, `INSERT INTO users (name,email,password_hash)
		VALUES ('Guardian',gen_random_uuid()::text || '@example.test','unused') RETURNING id`).Scan(&guardian); err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM users WHERE id=$1`, guardian)
	if err := pool.QueryRow(ctx, `INSERT INTO catechism_classes
		(church_id,name,level,status,start_date,end_date,capacity)
		VALUES ($1,'State test','adult','open',CURRENT_DATE,CURRENT_DATE,2) RETURNING id`, church).Scan(&class); err != nil {
		t.Fatal(err)
	}
	birthday := time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)
	repo := NewRepository(pool)
	enrollment, err := repo.CreateEnrollment(ctx, class, guardian, EnrollmentRequest{StudentName: "Student", DateOfBirth: &birthday})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE catechism_classes SET status='closed' WHERE id=$1`, class); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.CreateEnrollment(ctx, class, guardian, EnrollmentRequest{
		StudentName: "Late student", DateOfBirth: &birthday,
	}); !errors.Is(err, ErrClassNotOpen) {
		t.Fatalf("enrolling in a closed class returned %v", err)
	}

	results := make(chan error, 2)
	for _, status := range []EnrollmentStatus{EnrollApproved, EnrollRejected} {
		go func() {
			_, err := repo.UpdateEnrollmentStatus(ctx, enrollment.ID, EnrollPending, status)
			results <- err
		}()
	}
	changed, conflicted := 0, 0
	for range 2 {
		switch err := <-results; {
		case err == nil:
			changed++
		case errors.Is(err, ErrEnrollmentChanged):
			conflicted++
		default:
			t.Errorf("unexpected update result: %v", err)
		}
	}
	if changed != 1 || conflicted != 1 {
		t.Fatalf("successful updates=%d, conflicts=%d", changed, conflicted)
	}
}
