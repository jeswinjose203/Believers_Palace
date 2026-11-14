package community

import "time"

type Community struct {
	ID          string    `json:"id"`
	CreatorID   string    `json:"creatorId"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"createdAt"`
	Status      string    `json:"status,omitempty"`
	IsAdmin     bool      `json:"isAdmin,omitempty"`
}

type Membership struct {
	ID          string    `json:"id"`
	CommunityID string    `json:"communityId"`
	UserID      string    `json:"userId"`
	UserName    string    `json:"userName"`
	Status      string    `json:"status"`
	IsAdmin     bool      `json:"isAdmin"`
	CreatedAt   time.Time `json:"createdAt"`
}

type Message struct {
	ID          string    `json:"id"`
	CommunityID string    `json:"communityId"`
	Seq         int64     `json:"seq"`
	UserID      *string   `json:"userId"`
	AuthorName  string    `json:"authorName"`
	AuthorPic   *string   `json:"authorPic"`
	Content     string    `json:"content"`
	CreatedAt   time.Time `json:"createdAt"`
}

type CreateRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

type MessageRequest struct {
	Content string `json:"content"`
}

type CursorQuery struct {
	Before int64
	After  int64
	Limit  int
}

type CursorPage struct {
	Data    []Message `json:"data"`
	HasMore bool      `json:"hasMore"`
}
