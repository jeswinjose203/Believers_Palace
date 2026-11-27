package chatlive

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
	"github.com/gorilla/websocket"
)

type Room struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

type Signal struct {
	Room
	Deleted string `json:"deleted,omitempty"`
}

type TicketStore interface {
	Issue(context.Context, string, auth.Identity) error
	Consume(context.Context, string) (auth.Identity, bool, error)
}

type Hub struct {
	mu          sync.Mutex
	tickets     TicketStore
	available   bool
	connections map[*websocket.Conn]struct{}
	rooms       map[Room]map[*websocket.Conn]chan Signal
	authorize   func(context.Context, auth.Identity, Room) bool
}

func New(tickets TicketStore, authorize func(context.Context, auth.Identity, Room) bool) *Hub {
	return &Hub{
		tickets:     tickets,
		connections: make(map[*websocket.Conn]struct{}),
		rooms:       make(map[Room]map[*websocket.Conn]chan Signal),
		authorize:   authorize,
	}
}

func (h *Hub) setAvailable(available bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.available = available
	if !available {
		for conn := range h.connections {
			_ = conn.Close()
		}
	}
}

func (h *Hub) Ticket(w http.ResponseWriter, r *http.Request) {
	h.mu.Lock()
	available := h.available
	h.mu.Unlock()
	if !available {
		httpx.Error(w, http.StatusServiceUnavailable, "live chat is reconnecting")
		return
	}
	code, hash, err := auth.GenerateOpaqueToken()
	if err != nil || h.tickets.Issue(r.Context(), hash, auth.MustFromContext(r.Context())) != nil {
		httpx.Error(w, http.StatusInternalServerError, "could not open chat connection")
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	httpx.JSON(w, http.StatusOK, map[string]string{"ticket": code})
}

// Publish sends a small change signal. History and message bodies remain
// behind the existing authorized HTTP endpoints.
func (h *Hub) Publish(kind, id, deleted string) {
	room := Room{kind, id}
	h.mu.Lock()
	defer h.mu.Unlock()
	for connection, queue := range h.rooms[room] {
		select {
		case queue <- Signal{Room: room, Deleted: deleted}:
		default:
			// A slow client reconnects and catches up using its cursor.
			_ = connection.Close()
		}
	}
}

func (h *Hub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	protocols := websocket.Subprotocols(r)
	if len(protocols) != 2 || protocols[0] != "chat.v1" || len(protocols[1]) != 64 {
		httpx.Error(w, http.StatusUnauthorized, "invalid chat connection ticket")
		return
	}
	ticketCtx, cancelTicket := context.WithTimeout(r.Context(), 5*time.Second)
	id, ok, err := h.tickets.Consume(ticketCtx, auth.HashToken(protocols[1]))
	cancelTicket()
	if err != nil {
		httpx.Error(w, http.StatusServiceUnavailable, "live chat is reconnecting")
		return
	}
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "invalid chat connection ticket")
		return
	}
	// The one-time ticket is issued to an authenticated API caller. This
	// endpoint does not authenticate using cookies or other ambient credentials.
	upgrader := websocket.Upgrader{
		Subprotocols: []string{"chat.v1"},
		CheckOrigin:  func(*http.Request) bool { return true },
	}
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	h.mu.Lock()
	if !h.available {
		h.mu.Unlock()
		return
	}
	h.connections[conn] = struct{}{}
	h.mu.Unlock()
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), 15*time.Minute)
	defer cancel()

	incoming := make(chan command, 16)
	outgoing := make(chan Signal, 128)
	subscribed := make(map[Room]bool)
	defer func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		for room := range subscribed {
			h.remove(room, conn)
		}
		delete(h.connections, conn)
	}()
	go readCommands(ctx, cancel, conn, incoming)
	heartbeat := time.NewTicker(25 * time.Second)
	defer heartbeat.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-heartbeat.C:
			_ = conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if conn.WriteMessage(websocket.PingMessage, nil) != nil {
				return
			}
		case cmd := <-incoming:
			room := cmd.Room
			switch cmd.Op {
			case "unsubscribe":
				h.mu.Lock()
				h.remove(room, conn)
				h.mu.Unlock()
				delete(subscribed, room)
			case "subscribe":
				if subscribed[room] || len(subscribed) >= 256 ||
					!h.authorize(ctx, id, room) {
					continue
				}
				h.mu.Lock()
				if h.rooms[room] == nil {
					h.rooms[room] = make(map[*websocket.Conn]chan Signal)
				}
				h.rooms[room][conn] = outgoing
				h.mu.Unlock()
				subscribed[room] = true
				if writeSignal(conn, Signal{Room: room}) != nil {
					return
				}
			}
		case change := <-outgoing:
			if subscribed[change.Room] && writeSignal(conn, change) != nil {
				return
			}
		}
	}
}

type command struct {
	Room
	Op string `json:"op"`
}

func readCommands(ctx context.Context, cancel context.CancelFunc, conn *websocket.Conn, commands chan<- command) {
	defer cancel()
	conn.SetReadLimit(1024)
	_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	})
	window := time.Now()
	commandsInWindow := 0
	for {
		_, body, err := conn.ReadMessage()
		if err != nil {
			return
		}
		now := time.Now()
		if now.Sub(window) >= time.Minute {
			window, commandsInWindow = now, 0
		}
		commandsInWindow++
		if commandsInWindow > 512 {
			return
		}
		var cmd command
		if json.Unmarshal(body, &cmd) != nil {
			return
		}
		select {
		case commands <- cmd:
		case <-ctx.Done():
			return
		}
	}
}

func writeSignal(conn *websocket.Conn, change Signal) error {
	_ = conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	return conn.WriteJSON(change)
}

func (h *Hub) remove(room Room, conn *websocket.Conn) {
	delete(h.rooms[room], conn)
	if len(h.rooms[room]) == 0 {
		delete(h.rooms, room)
	}
}
