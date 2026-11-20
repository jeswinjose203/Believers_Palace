package chatlive

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"believers_palace/internal/auth"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
)

// TestDistributedChat uses a migrated disposable database and two HTTP
// servers. Increase CHAT_TEST_CONNECTIONS to exercise a larger local load.
func TestDistributedChat(t *testing.T) {
	dsn := os.Getenv("CHAT_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("requires a migrated disposable database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	db := Postgres{Pool: pool}
	const roomID = "b313457c-3f91-4eb6-9228-1346984f803b"
	const memberID = "78a88190-48b1-42b1-b7fc-8a9496863c45"
	room := Room{Kind: "community", ID: roomID}
	authorize := func(_ context.Context, _ auth.Identity, requested Room) bool {
		return requested == room
	}
	start := func() (*Hub, *httptest.Server) {
		hub := New(db, authorize)
		r := http.NewServeMux()
		r.Handle("POST /ticket", auth.DebugMiddleware()(http.HandlerFunc(hub.Ticket)))
		r.Handle("GET /live", hub)
		server := httptest.NewServer(r)
		go db.Run(ctx, hub)
		for range 200 {
			hub.mu.Lock()
			available := hub.available
			hub.mu.Unlock()
			if available {
				return hub, server
			}
			time.Sleep(10 * time.Millisecond)
		}
		server.Close()
		t.Fatal("PostgreSQL listener failed to start")
		return nil, nil
	}
	_, first := start()
	defer first.Close()
	_, second := start()
	defer second.Close()

	connectionCount := 128
	if value, err := strconv.Atoi(os.Getenv("CHAT_TEST_CONNECTIONS")); err == nil && value > 0 {
		connectionCount = value
	}
	clients := make([]*websocket.Conn, 0, connectionCount)
	for i := range connectionCount {
		response, err := first.Client().Post(first.URL+"/ticket", "application/json", nil)
		if err != nil {
			t.Fatal(err)
		}
		var issued struct{ Ticket string }
		err = json.NewDecoder(response.Body).Decode(&issued)
		response.Body.Close()
		if err != nil || issued.Ticket == "" {
			t.Fatalf("could not issue ticket: %v (HTTP %d)", err, response.StatusCode)
		}
		target := first.URL
		if i%2 == 0 {
			target = second.URL
		}
		address := "ws" + strings.TrimPrefix(target, "http") + "/live"
		dialer := websocket.Dialer{Subprotocols: []string{"chat.v1", issued.Ticket}, HandshakeTimeout: 2 * time.Second}
		conn, _, err := dialer.Dial(address, nil)
		if err != nil {
			t.Fatal(err)
		}
		defer conn.Close()
		clients = append(clients, conn)
		if err := conn.WriteJSON(command{Room: room, Op: "subscribe"}); err != nil {
			t.Fatal(err)
		}
		_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
		var ack Signal
		if err := conn.ReadJSON(&ack); err != nil || ack.Room != room {
			t.Fatalf("subscribe: %+v %v", ack, err)
		}
	}
	for _, stmt := range []string{
		"INSERT INTO users (id,name,email,password_hash,email_verified) VALUES ('" + memberID + "','Chat Test','chat-load@example.test','unused',true)",
		"INSERT INTO communities (id,creator_id,name) VALUES ('" + roomID + "','" + memberID + "','Chat load test')",
		"INSERT INTO community_memberships (community_id,user_id,status) VALUES ('" + roomID + "','" + memberID + "','active')",
	} {
		if _, err := pool.Exec(ctx, stmt); err != nil {
			t.Fatal(err)
		}
	}
	defer pool.Exec(context.Background(), "DELETE FROM users WHERE id=$1", memberID)

	const messages = 20
	latencies := make([]time.Duration, 0, messages*connectionCount)
	for i := range messages {
		start := time.Now()
		if _, err := pool.Exec(ctx, `INSERT INTO community_messages
			(community_id,seq,user_id,author_name,content) VALUES ($1,$2,$3,'Test','Load test')`,
			roomID, i+1, memberID); err != nil {
			t.Fatal(err)
		}
		for _, conn := range clients {
			_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
			var signal Signal
			if err := conn.ReadJSON(&signal); err != nil || signal.Room != room {
				t.Fatalf("message %d: %+v %v", i, signal, err)
			}
			latencies = append(latencies, time.Since(start))
		}
	}
	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	t.Logf("%d sockets across 2 replicas, %d/%d signals, p50=%s p95=%s p99=%s",
		connectionCount, len(latencies), messages*connectionCount,
		latencies[len(latencies)/2], latencies[len(latencies)*95/100], latencies[len(latencies)*99/100])
	const recipient = "ae350cd5-e378-4a51-8119-da87b7405d20"
	if _, err := pool.Exec(ctx, `INSERT INTO users (id,name,email,password_hash,email_verified)
		VALUES ($1,'Recipient','chat-recipient@example.test','unused',true)`, recipient); err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), "DELETE FROM users WHERE id=$1", recipient)
	if _, err := pool.Exec(ctx, `INSERT INTO community_memberships (community_id,user_id,status)
		VALUES ($1,$2,'active')`, roomID, recipient); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO chat_push_devices (token,user_id)
		VALUES ('sender-device',$1), ('recipient-device',$2)`, memberID, recipient); err != nil {
		t.Fatal(err)
	}
	var sent atomic.Int32
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var payload struct{ Message struct{ FID string } }
		if json.NewDecoder(r.Body).Decode(&payload) != nil || payload.Message.FID != "recipient-device" {
			t.Error("push went to an unexpected device")
		}
		sent.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer provider.Close()
	worker := PushWorker{Postgres: db, client: provider.Client(), endpoint: provider.URL}
	for i := range 2 {
		if _, err := pool.Exec(ctx, `INSERT INTO community_messages
			(community_id,seq,user_id,author_name,content) VALUES ($1,$2,$3,'Test','Push test')`,
			roomID, messages+i+1, memberID); err != nil {
			t.Fatal(err)
		}
		if _, err := worker.expand(ctx); err != nil {
			t.Fatal(err)
		}
		if i == 1 {
			// Changing the preference after jobs were queued still suppresses delivery.
			if _, err := pool.Exec(ctx, `INSERT INTO chat_notification_preferences
				(user_id,kind,room_id,muted) VALUES ($1,'community',$2,true)`, recipient, roomID); err != nil {
				t.Fatal(err)
			}
		}
		if _, err := worker.deliverBatch(ctx); err != nil {
			t.Fatal(err)
		}
	}
	if sent.Load() != 1 {
		t.Fatalf("expected one push to an unmuted recipient, got %d", sent.Load())
	}
}
