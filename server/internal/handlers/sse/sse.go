package sse

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/ja-son-wu/c-paper-server/internal/middleware"
)

type Event struct {
	Type string `json:"type"`
	Data string `json:"data"`
}

type Hub struct {
	mu      sync.RWMutex
	clients map[int64]map[chan Event]bool
}

func NewHub() *Hub {
	return &Hub{clients: make(map[int64]map[chan Event]bool)}
}

func (h *Hub) Subscribe(groupID int64) chan Event {
	ch := make(chan Event, 16)
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[groupID] == nil {
		h.clients[groupID] = make(map[chan Event]bool)
	}
	h.clients[groupID][ch] = true
	return ch
}

func (h *Hub) Unsubscribe(groupID int64, ch chan Event) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if clients, ok := h.clients[groupID]; ok {
		delete(clients, ch)
		if len(clients) == 0 {
			delete(h.clients, groupID)
		}
	}
	close(ch)
}

func (h *Hub) Broadcast(groupID int64, event Event) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if clients, ok := h.clients[groupID]; ok {
		for ch := range clients {
			select {
			case ch <- event:
			default:
			}
		}
	}
}

// MembershipChecker is a function that checks if a user belongs to a group.
type MembershipChecker func(groupID, userID int64) (bool, error)

// HandleSSE creates an SSE handler that verifies group membership.
func HandleSSE(hub *Hub, isMember MembershipChecker) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := middleware.GetUserID(r)
		if !ok {
			http.Error(w, `{"ok":false,"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}

		groupID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
		if err != nil || groupID <= 0 {
			http.Error(w, `{"ok":false,"error":"invalid group id"}`, http.StatusBadRequest)
			return
		}

		// Verify group membership
		member, err := isMember(groupID, userID)
		if err != nil || !member {
			http.Error(w, `{"ok":false,"error":"not a member of this group"}`, http.StatusForbidden)
			return
		}

		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming unsupported", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("X-Accel-Buffering", "no")

		ch := hub.Subscribe(groupID)
		defer hub.Unsubscribe(groupID, ch)

		// Send connected event
		data, _ := json.Marshal(map[string]interface{}{"user_id": userID, "group_id": groupID})
		fmt.Fprintf(w, "event: connected\ndata: %s\n\n", data)
		flusher.Flush()

		// Heartbeat ticker
		heartbeat := time.NewTicker(30 * time.Second)
		defer heartbeat.Stop()

		ctx := r.Context()
		for {
			select {
			case <-ctx.Done():
				return
			case <-heartbeat.C:
				fmt.Fprintf(w, ":heartbeat\n\n")
				flusher.Flush()
			case event := <-ch:
				fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event.Type, event.Data)
				flusher.Flush()
			}
		}
	}
}
