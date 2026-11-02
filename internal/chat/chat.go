// Package chat implements per-event chat messages. Any authenticated user who
// can see an event may read and post messages. A message may be deleted by its
// author or by an administrator of the event's church (or a super admin).
package chat

import "time"

// Message is a single chat message posted to an event's chat.
type Message struct {
	ID         string    `json:"id"`
	EventID    string    `json:"eventId"`
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
