package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"believers_palace/internal/auth"
	"believers_palace/internal/config"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestMixedAPILoad(t *testing.T) {
	dsn := os.Getenv("API_LOAD_DATABASE_URL")
	if dsn == "" {
		t.Skip("requires a migrated disposable PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	poolConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	poolConfig.MaxConns = 10
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	const userID = "e2222222-0000-0000-0000-000000000001"
	const churchID = "e2222222-0000-0000-0000-000000000002"
	const roomID = "e2222222-0000-0000-0000-000000000003"
	const eventID = "e2222222-0000-0000-0000-000000000004"
	for _, statement := range []struct {
		sql  string
		args []any
	}{
		{`INSERT INTO churches (id,name,address) VALUES ($1,'Load test church','Test')`, []any{churchID}},
		{`INSERT INTO users (id,name,email,password_hash,email_verified,church_id)
			VALUES ($1,'Load test','mixed-load@example.test','unused',true,$2)`, []any{userID, churchID}},
		{`INSERT INTO communities (id,creator_id,name) VALUES ($1,$2,'Load test group')`, []any{roomID, userID}},
		{`INSERT INTO community_memberships (community_id,user_id,status,is_admin) VALUES ($1,$2,'active',true)`, []any{roomID, userID}},
		{`INSERT INTO events (id,church_id,title,start_date) VALUES ($1,$2,'Load test event',now())`, []any{eventID, churchID}},
	} {
		if _, err := pool.Exec(ctx, statement.sql, statement.args...); err != nil {
			t.Fatal(err)
		}
	}
	defer pool.Exec(context.Background(), `DELETE FROM churches WHERE id=$1`, churchID)
	defer pool.Exec(context.Background(), `DELETE FROM users WHERE id=$1`, userID)
	if _, err := pool.Exec(ctx, `INSERT INTO communities (creator_id,name)
		SELECT $1, 'Load test group ' || i FROM generate_series(1,10000) AS i`, userID); err != nil {
		t.Fatal(err)
	}

	const secret = "local-mixed-load-test-only"
	cfg := &config.Config{
		AppEnv:             "test",
		HTTPMaxInFlight:    128,
		ChatMaxConnections: 4096,
		JWT:                config.JWTConfig{Secret: secret, Issuer: "load-test", TTL: time.Hour},
		Storage:            config.StorageConfig{Dir: t.TempDir(), MediaDir: t.TempDir()},
	}
	appCtx, stopApp := context.WithCancel(ctx)
	defer stopApp()
	handler, err := New(appCtx, cfg, pool)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(handler)
	defer server.Close()
	token, err := auth.NewTokenManager(secret, time.Hour, "load-test").Generate(userID, auth.RoleUser, churchID)
	if err != nil {
		t.Fatal(err)
	}
	community := "/api/communities/" + roomID + "/messages"
	event := "/api/events/" + eventID + "/messages"
	routes := []struct{ method, path string }{
		{"GET", "/api/churches?limit=20"},
		{"GET", "/api/churches/" + churchID + "/announcements?limit=20"},
		{"GET", "/api/churches/" + churchID + "/halls?limit=20"},
		{"GET", "/api/churches/" + churchID + "/events?limit=20"},
		{"GET", "/api/churches/" + churchID + "/catechism-classes?limit=20"},
		{"GET", "/api/churches/" + churchID + "/cemetery-plots?limit=20"},
		{"GET", "/api/bookings?limit=20"},
		{"GET", "/api/users/" + userID + "/certificates?limit=20"},
		{"GET", "/api/users/me"},
		{"GET", "/api/users/me/calendar/events?limit=20"},
		{"GET", "/api/marketplace/community-ads?limit=20"},
		{"GET", "/api/marketplace/shop/products?limit=20"},
		{"GET", "/api/communities?limit=30"},
		{"GET", "/api/chat/joined-communities"},
		{"GET", community + "?limit=20"},
		{"GET", event + "?limit=20"},
		{"POST", community},
		{"POST", event},
	}
	workers := 32
	if n, err := strconv.Atoi(os.Getenv("API_LOAD_CONCURRENCY")); err == nil && n >= 1 && n <= 128 {
		workers = n
	}
	requests := 2200
	if n, err := strconv.Atoi(os.Getenv("API_LOAD_REQUESTS")); err == nil && n >= len(routes) {
		requests = n
	}
	client := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{
		MaxIdleConns: workers, MaxIdleConnsPerHost: workers, MaxConnsPerHost: workers,
	}}
	defer client.CloseIdleConnections()
	loadCommunityPage := func(path string) (ids []string, cursor string) {
		t.Helper()
		req, err := http.NewRequestWithContext(ctx, "GET", server.URL+path, nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
		response, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		var page struct {
			Data       []struct{ ID string }
			NextCursor string
		}
		if err := json.NewDecoder(response.Body).Decode(&page); err != nil || response.StatusCode != 200 {
			t.Fatalf("load page: HTTP %d: %v", response.StatusCode, err)
		}
		for _, item := range page.Data {
			ids = append(ids, item.ID)
		}
		return ids, page.NextCursor
	}
	first, cursor := loadCommunityPage("/api/communities?limit=30")
	if len(first) != 30 || cursor == "" {
		t.Fatalf("unexpected first page size=%d cursor=%q", len(first), cursor)
	}
	second, _ := loadCommunityPage("/api/communities?limit=30&cursor=" + cursor)
	if len(second) != 30 {
		t.Fatalf("unexpected second page size=%d", len(second))
	}
	seen := make(map[string]bool)
	for _, id := range append(first, second...) {
		if seen[id] {
			t.Fatalf("duplicate community across pages: %s", id)
		}
		seen[id] = true
	}
	joined, _ := loadCommunityPage("/api/communities?limit=30&joined=true")
	if len(joined) != 1 || joined[0] != roomID {
		t.Fatalf("unexpected joined page: %v", joined)
	}
	results := make([]time.Duration, requests)
	var group sync.WaitGroup
	start := time.Now()
	for worker := range workers {
		group.Add(1)
		go func() {
			defer group.Done()
			for i := worker; i < requests; i += workers {
				route := routes[i%len(routes)]
				body := ""
				if route.method == "POST" {
					body = fmt.Sprintf(`{"content":"local load test","clientId":"load-%d"}`, i)
				}
				req, err := http.NewRequestWithContext(ctx, route.method, server.URL+route.path, strings.NewReader(body))
				if err != nil {
					t.Error(err)
					continue
				}
				req.Header.Set("Authorization", "Bearer "+token)
				req.Header.Set("Content-Type", "application/json")
				requestStart := time.Now()
				resp, err := client.Do(req)
				if err != nil {
					t.Errorf("%s %s: %v", route.method, route.path, err)
					continue
				}
				expected := http.StatusOK
				if route.method == http.MethodPost {
					expected = http.StatusCreated
				}
				if resp.StatusCode != expected {
					message, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
					t.Errorf("%s %s: HTTP %d %s", route.method, route.path, resp.StatusCode, message)
				}
				if _, err := io.Copy(io.Discard, resp.Body); err != nil {
					t.Errorf("%s %s: read response: %v", route.method, route.path, err)
				}
				resp.Body.Close()
				results[i] = time.Since(requestStart)
			}
		}()
	}
	group.Wait()
	elapsed := time.Since(start)
	sort.Slice(results, func(i, j int) bool { return results[i] < results[j] })
	t.Logf("%d requests, %d workers, %.0f req/s, p50=%s p95=%s p99=%s", requests, workers,
		float64(requests)/elapsed.Seconds(), results[requests/2], results[requests*95/100], results[requests*99/100])
}
