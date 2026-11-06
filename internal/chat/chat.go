// Package chat implements per-event chat messages. Any authenticated user who
// can see an event may read and post messages. A message may be deleted by its
// author or by an administrator of the event's church (or a super admin).
package chat

import "time"

// Message is a single chat message posted to an event's chat.
type Message struct {
	ID      string `json:"id"`
	EventID string `json:"eventId"`
	// Seq is a monotonically increasing number used as a paging/polling cursor.
	Seq        int64     `json:"seq"`
	UserID     *string   `json:"userId"`
	AuthorName string    `json:"authorName"`
	AuthorPic  *string   `json:"authorPic"`
	Content    string    `json:"content"`
	CreatedAt  time.Time `json:"createdAt"`
}

// CreateRequest is the payload for posting a message.
type CreateRequest struct {
	Content string `json:"content"`
}

// CursorPage is the response of the cursor-based message listing. Data is
// always ordered oldest-first. HasMore means more messages exist beyond the
// returned window in the direction that was requested (older for latest/before,
// newer for after).
type CursorPage struct {
	Data    []Message `json:"data"`
	HasMore bool      `json:"hasMore"`
}

// CursorQuery selects a window of messages. With neither Before nor After set,
// the latest messages are returned. Before and After are mutually exclusive.
type CursorQuery struct {
	Before int64
	After  int64
	Limit  int
}
