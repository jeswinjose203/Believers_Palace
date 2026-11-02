// Package announcement implements church announcements: a per-church resource
// supporting list, create, update, and delete.
package announcement

import "time"

// Announcement is a church announcement record.
type Announcement struct {
	ID          string     `json:"id"`
	ChurchID    string     `json:"churchId"`
	Title       string     `json:"title"`
	Content     string     `json:"content"`
	Image       *string    `json:"image"`
	PublishedAt *time.Time `json:"publishedAt"`
	CreatedAt   time.Time  `json:"createdAt"`
	UpdatedAt   time.Time  `json:"updatedAt"`
}

// CreateRequest is the payload for creating an announcement.
type CreateRequest struct {
	Title       string     `json:"title"`
	Content     string     `json:"content"`
	Image       *string    `json:"image"`
	PublishedAt *time.Time `json:"publishedAt"`
}

// UpdateRequest is the payload for updating an announcement. Pointer fields
// distinguish "not provided" from an explicit value.
type UpdateRequest struct {
	Title       *string    `json:"title"`
	Content     *string    `json:"content"`
	Image       *string    `json:"image"`
	PublishedAt *time.Time `json:"publishedAt"`
}
