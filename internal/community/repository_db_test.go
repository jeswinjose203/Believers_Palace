package community

import (
	"context"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func newCommunityTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping database-backed community chat test")
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

func seedCommunity(t *testing.T, pool *pgxpool.Pool) (string, string) {
	t.Helper()
	ctx := context.Background()
	var userID string
	if err := pool.QueryRow(ctx, `INSERT INTO users (name,email,password_hash)
		VALUES ('community seq user',$1,'test') RETURNING id`,
		fmt.Sprintf("community-seq-%d@example.test", time.Now().UnixNano())).
		Scan(&userID); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	community, err := NewRepository(pool).Create(ctx, userID, "seq-test community", "", nil)
	if err != nil {
		t.Fatalf("create community: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM communities WHERE id=$1`, community.ID)
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id=$1`, userID)
	})
	return community.ID, userID
}

func TestDBCommunityImagePersists(t *testing.T) {
	pool := newCommunityTestPool(t)
	defer pool.Close()

	ctx := context.Background()
	var userID string
	if err := pool.QueryRow(ctx, `INSERT INTO users (name,email,password_hash)
		VALUES ('community image user',$1,'test') RETURNING id`,
		fmt.Sprintf("community-image-%d@example.test", time.Now().UnixNano())).
		Scan(&userID); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id=$1`, userID)
	})

	image := "https://example.test/community.jpg"
	repo := NewRepository(pool)
	created, err := repo.Create(ctx, userID, "image-test community", "", &image)
	if err != nil {
		t.Fatalf("create community: %v", err)
	}

	got, err := repo.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("get community: %v", err)
	}
	if got.Image == nil || *got.Image != image {
		t.Fatalf("stored image = %v, want %q", got.Image, image)
	}

	communities, err := repo.List(ctx, userID)
	if err != nil {
		t.Fatalf("list communities: %v", err)
	}
	if len(communities) != 1 || communities[0].Image == nil || *communities[0].Image != image {
		t.Fatalf("listed communities = %+v, want community image %q", communities, image)
	}
}

func TestDBConcurrentCommunityMessagesHaveGaplessCursor(t *testing.T) {
	pool := newCommunityTestPool(t)
	defer pool.Close()
	repo := NewRepository(pool)
	communityID, userID := seedCommunity(t, pool)

	const count = 200
	var wait sync.WaitGroup
	seqs := make([]int64, count)
	errs := make([]error, count)
	for i := 0; i < count; i++ {
		wait.Add(1)
		go func(i int) {
			defer wait.Done()
			message, err := repo.CreateMessage(
				context.Background(), communityID, userID, "Member", nil, "hello",
			)
			if err != nil {
				errs[i] = err
				return
			}
			seqs[i] = message.Seq
		}(i)
	}
	wait.Wait()

	seenSeqs := make(map[int64]bool, count)
	for i, err := range errs {
		if err != nil {
			t.Fatalf("create message %d: %v", i, err)
		}
		if seqs[i] < 1 || seqs[i] > count || seenSeqs[seqs[i]] {
			t.Fatalf("invalid or duplicate seq %d", seqs[i])
		}
		seenSeqs[seqs[i]] = true
	}

	var after int64
	seenMessages := 0
	for {
		page, hasMore, err := repo.ListMessages(context.Background(), communityID, CursorQuery{
			After: after, AfterSet: true, Limit: 20,
		})
		if err != nil {
			t.Fatalf("list after %d: %v", after, err)
		}
		for i, message := range page {
			if message.Seq != after+int64(i)+1 {
				t.Fatalf("out-of-order message seq %d after %d", message.Seq, after)
			}
		}
		if len(page) == 0 {
			break
		}
		after = page[len(page)-1].Seq
		seenMessages += len(page)
		if !hasMore {
			break
		}
	}
	if seenMessages != count {
		t.Fatalf("cursor returned %d messages; want %d", seenMessages, count)
	}
}
