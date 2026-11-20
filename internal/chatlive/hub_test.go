package chatlive

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"believers_palace/internal/auth"
	"github.com/gorilla/websocket"
)

type testTickets struct {
	mu    sync.Mutex
	items map[string]auth.Identity
}

func (s *testTickets) Issue(_ context.Context, hash string, id auth.Identity) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items[hash] = id
	return nil
}

func (s *testTickets) Consume(_ context.Context, hash string) (auth.Identity, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	id, ok := s.items[hash]
	delete(s.items, hash)
	return id, ok, nil
}

func TestLiveChatTicketAndRoomUpdates(t *testing.T) {
	room := Room{Kind: "community", ID: "joined"}
	hub := New(&testTickets{items: make(map[string]auth.Identity)}, func(_ context.Context, id auth.Identity, candidate Room) bool {
		return id.UserID == auth.DebugUserID && candidate == room
	})
	hub.setAvailable(true)
	mux := http.NewServeMux()
	mux.Handle("POST /ticket", auth.DebugMiddleware()(http.HandlerFunc(hub.Ticket)))
	mux.Handle("GET /live", hub)
	server := httptest.NewServer(mux)
	defer server.Close()

	response, err := server.Client().Post(server.URL+"/ticket", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	var result struct{ Ticket string }
	if err := json.NewDecoder(response.Body).Decode(&result); err != nil {
		t.Fatal(err)
	}
	dialer := websocket.Dialer{
		Subprotocols:     []string{"chat.v1", result.Ticket},
		HandshakeTimeout: time.Second,
	}
	address := "ws" + strings.TrimPrefix(server.URL, "http") + "/live"
	conn, _, err := dialer.Dial(address, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))

	for _, candidate := range []Room{{Kind: "community", ID: "private"}, room} {
		if err := conn.WriteJSON(command{Room: candidate, Op: "subscribe"}); err != nil {
			t.Fatal(err)
		}
	}
	var signal Signal
	if err := conn.ReadJSON(&signal); err != nil || signal.Room != room {
		t.Fatalf("expected only the authorized subscription, got %+v, %v", signal, err)
	}
	hub.Publish(room.Kind, room.ID, "deleted-message")
	if err := conn.ReadJSON(&signal); err != nil || signal.Deleted != "deleted-message" {
		t.Fatalf("expected delete event, got %+v, %v", signal, err)
	}

	reused, rejection, err := dialer.Dial(address, nil)
	if reused != nil {
		reused.Close()
	}
	if rejection != nil {
		defer rejection.Body.Close()
	}
	if err == nil || rejection == nil || rejection.StatusCode != http.StatusUnauthorized {
		t.Fatal("the single-use ticket was accepted again")
	}
}
