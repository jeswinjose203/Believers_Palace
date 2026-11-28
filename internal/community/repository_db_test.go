package community

import (
	"context"
	"errors"
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

func seedCommunityChurch(t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()
	var id string
	if err := pool.QueryRow(context.Background(), `INSERT INTO churches (name) VALUES ('Community test church') RETURNING id`).Scan(&id); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM churches WHERE id=$1`, id) })
	return id
}

func seedCommunity(t *testing.T, pool *pgxpool.Pool) (string, string) {
	t.Helper()
	ctx := context.Background()
	churchID := seedCommunityChurch(t, pool)
	var userID string
	if err := pool.QueryRow(ctx, `INSERT INTO users (name,email,password_hash,church_id)
		VALUES ('community seq user',$1,'test',$2) RETURNING id`,
		fmt.Sprintf("community-seq-%d@example.test", time.Now().UnixNano()), churchID).
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
	t.Cleanup(pool.Close)

	ctx := context.Background()
	churchID := seedCommunityChurch(t, pool)
	var userID string
	if err := pool.QueryRow(ctx, `INSERT INTO users (name,email,password_hash,church_id)
		VALUES ('community image user',$1,'test',$2) RETURNING id`,
		fmt.Sprintf("community-image-%d@example.test", time.Now().UnixNano()), churchID).
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
	for _, item := range communities {
		if item.ID == created.ID {
			if item.Image == nil || *item.Image != image {
				t.Fatalf("listed community image = %v, want %q", item.Image, image)
			}
			return
		}
	}
	t.Fatal("created community is missing from the list")
}

func TestDBCommunityDetailsRequireActiveAdmin(t *testing.T) {
	pool := newCommunityTestPool(t)
	t.Cleanup(pool.Close)
	cid, uid := seedCommunity(t, pool)
	ctx := context.Background()
	repo := NewRepository(pool)
	image := "https://example.test/updated-community.jpg"
	details := CreateRequest{Name: "Updated choir", Description: "Practice on Sundays", Image: &image}

	if _, err := pool.Exec(ctx, `UPDATE community_memberships SET is_admin=false
		WHERE community_id=$1 AND user_id=$2`, cid, uid); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.Update(ctx, cid, uid, details); !errors.Is(err, ErrForbidden) {
		t.Fatalf("regular member edited community: %v", err)
	}
	if _, err := pool.Exec(ctx, `UPDATE community_memberships SET is_admin=true
		WHERE community_id=$1 AND user_id=$2`, cid, uid); err != nil {
		t.Fatal(err)
	}
	updated, err := repo.Update(ctx, cid, uid, details)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Name != details.Name || updated.Description != details.Description ||
		updated.Image == nil || *updated.Image != image || !updated.IsAdmin || updated.Status != "active" {
		t.Fatalf("unexpected update: %+v", updated)
	}
	details.Image = nil
	if _, err := repo.Update(ctx, cid, uid, details); err != nil {
		t.Fatal(err)
	}
	persisted, err := repo.Get(ctx, cid)
	if err != nil {
		t.Fatal(err)
	}
	if persisted.Name != details.Name || persisted.Description != details.Description || persisted.Image != nil {
		t.Fatalf("unexpected persisted details: %+v", persisted)
	}
}

func TestDBConcurrentCommunityMessagesHaveGaplessCursor(t *testing.T) {
	pool := newCommunityTestPool(t)
	t.Cleanup(pool.Close)
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

func TestDBConcurrentAdminDeparturesKeepAnAdmin(t *testing.T) {
	pool := newCommunityTestPool(t)
	t.Cleanup(pool.Close)
	communityID, first := seedCommunity(t, pool)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	var second string
	if err := pool.QueryRow(ctx, `INSERT INTO users (name,email,password_hash)
		VALUES ('Second admin',gen_random_uuid()::text || '@example.test','test') RETURNING id`).
		Scan(&second); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id=$1`, second)
	})
	if _, err := pool.Exec(ctx, `INSERT INTO community_memberships (community_id,user_id,status,is_admin)
		VALUES ($1,$2,'active',true)`, communityID, second); err != nil {
		t.Fatal(err)
	}
	repo := NewRepository(pool)
	outcomes := make(chan error, 2)
	go func() { outcomes <- repo.Leave(ctx, communityID, first) }()
	go func() { outcomes <- repo.Leave(ctx, communityID, second) }()
	left, stayed := 0, 0
	for range 2 {
		switch err := <-outcomes; {
		case err == nil:
			left++
		case errors.Is(err, ErrLastAdmin):
			stayed++
		default:
			t.Errorf("unexpected departure error: %v", err)
		}
	}
	if left != 1 || stayed != 1 {
		t.Fatalf("departures = %d, retained admins = %d", left, stayed)
	}
}

func TestDBCommunityDiscoveryFollowsSelectedChurch(t *testing.T) {
	pool := newCommunityTestPool(t)
	t.Cleanup(pool.Close)
	ctx := context.Background()
	first, member := seedCommunity(t, pool)
	second, other := seedCommunity(t, pool)
	repo := NewRepository(pool)
	check := func(joined bool, want string) {
		t.Helper()
		items, err := repo.List(ctx, member, ListOptions{Joined: joined, Limit: 20})
		if err != nil {
			t.Fatal(err)
		}
		if len(items) != 1 || items[0].ID != want {
			t.Fatalf("joined=%t got %v, want only %s", joined, items, want)
		}
	}
	check(false, first)
	if _, err := repo.RequestMembership(ctx, second, member); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected cross-church request to fail, got %v", err)
	}
	if _, err := pool.Exec(ctx, `UPDATE users SET church_id=(SELECT church_id FROM users WHERE id=$2) WHERE id=$1`, member, other); err != nil {
		t.Fatal(err)
	}
	check(false, second)
	check(true, first)
	if _, err := repo.RequestMembership(ctx, second, member); err != nil {
		t.Fatal(err)
	}
}
