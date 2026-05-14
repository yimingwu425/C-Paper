package sse

import (
	"testing"
)

func TestHub_SubscribeUnsubscribe(t *testing.T) {
	hub := NewHub()

	ch := hub.Subscribe(100)
	if ch == nil {
		t.Fatal("expected non-nil channel")
	}

	hub.mu.RLock()
	count := len(hub.clients[100])
	hub.mu.RUnlock()
	if count != 1 {
		t.Errorf("expected 1 subscriber, got %d", count)
	}

	hub.Unsubscribe(100, ch)

	hub.mu.RLock()
	_, exists := hub.clients[100]
	hub.mu.RUnlock()
	if exists {
		t.Error("expected group to be cleaned up after last unsubscribe")
	}
}

func TestHub_Broadcast(t *testing.T) {
	hub := NewHub()

	ch := hub.Subscribe(100)
	event := Event{Type: "test", Data: "hello"}
	hub.Broadcast(100, event)

	select {
	case received := <-ch:
		if received.Type != "test" {
			t.Errorf("expected type test, got %s", received.Type)
		}
		if received.Data != "hello" {
			t.Errorf("expected data hello, got %s", received.Data)
		}
	default:
		t.Error("expected event on channel")
	}
}

func TestHub_BroadcastNoSubscribers(t *testing.T) {
	hub := NewHub()
	// Should not panic
	hub.Broadcast(999, Event{Type: "test", Data: "data"})
}

func TestHub_MultipleSubscribers(t *testing.T) {
	hub := NewHub()

	ch1 := hub.Subscribe(100)
	ch2 := hub.Subscribe(100)

	hub.mu.RLock()
	count := len(hub.clients[100])
	hub.mu.RUnlock()
	if count != 2 {
		t.Errorf("expected 2 subscribers, got %d", count)
	}

	hub.Broadcast(100, Event{Type: "msg", Data: "hi"})

	for _, ch := range []chan Event{ch1, ch2} {
		select {
		case received := <-ch:
			if received.Type != "msg" {
				t.Errorf("expected type msg, got %s", received.Type)
			}
			if received.Data != "hi" {
				t.Errorf("expected data hi, got %s", received.Data)
			}
		default:
			t.Error("expected event on channel")
		}
	}
}

func TestHub_DifferentGroups(t *testing.T) {
	hub := NewHub()

	ch1 := hub.Subscribe(100)
	ch2 := hub.Subscribe(200)

	hub.Broadcast(100, Event{Type: "group1", Data: "data1"})
	hub.Broadcast(200, Event{Type: "group2", Data: "data2"})

	// ch1 should receive group1 event
	select {
	case received := <-ch1:
		if received.Type != "group1" {
			t.Errorf("expected type group1, got %s", received.Type)
		}
	default:
		t.Error("expected event on ch1")
	}

	// ch2 should receive group2 event
	select {
	case received := <-ch2:
		if received.Type != "group2" {
			t.Errorf("expected type group2, got %s", received.Type)
		}
	default:
		t.Error("expected event on ch2")
	}

	// ch1 should NOT have group2 event
	select {
	case <-ch1:
		t.Error("ch1 should not have received group2 event")
	default:
		// expected
	}
}

func TestHub_PartialUnsubscribe(t *testing.T) {
	hub := NewHub()

	ch1 := hub.Subscribe(100)
	ch2 := hub.Subscribe(100)

	hub.Unsubscribe(100, ch1)

	// Group should still exist because ch2 is still subscribed
	hub.mu.RLock()
	_, exists := hub.clients[100]
	hub.mu.RUnlock()
	if !exists {
		t.Error("group should still exist with remaining subscriber")
	}

	hub.mu.RLock()
	count := len(hub.clients[100])
	hub.mu.RUnlock()
	if count != 1 {
		t.Errorf("expected 1 remaining subscriber, got %d", count)
	}

	// ch2 should still receive events
	hub.Broadcast(100, Event{Type: "test", Data: "after_unsub"})
	select {
	case received := <-ch2:
		if received.Data != "after_unsub" {
			t.Errorf("expected data after_unsub, got %s", received.Data)
		}
	default:
		t.Error("expected event on remaining channel")
	}
}

func TestHub_BroadcastFullChannel(t *testing.T) {
	hub := NewHub()

	// Channel buffer is 16, fill it up
	ch := hub.Subscribe(100)
	for i := 0; i < 16; i++ {
		hub.Broadcast(100, Event{Type: "fill", Data: "data"})
	}

	// 17th broadcast should not block or panic (select default)
	hub.Broadcast(100, Event{Type: "overflow", Data: "should_not_block"})

	// Verify we can still read the first 16
	for i := 0; i < 16; i++ {
		select {
		case <-ch:
		default:
			t.Errorf("expected event %d on channel", i)
		}
	}
}

func TestEvent_Fields(t *testing.T) {
	event := Event{Type: "progress_update", Data: `{"status":"done"}`}
	if event.Type != "progress_update" {
		t.Errorf("expected type progress_update, got %s", event.Type)
	}
	if event.Data != `{"status":"done"}` {
		t.Errorf("expected data {\"status\":\"done\"}, got %s", event.Data)
	}
}
