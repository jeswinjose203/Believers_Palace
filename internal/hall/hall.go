// Package hall implements church halls: bookable venues belonging to a church,
// supporting list, create, get, update, and delete.
package hall

import "time"

// Hall is a bookable venue belonging to a church.
type Hall struct {
	ID          string    `json:"id"`
	ChurchID    string    `json:"churchId"`
	Name        string    `json:"name"`
	Description string    `json:"description,omitempty"`
	Capacity    *int      `json:"capacity,omitempty"`
	Location    string    `json:"location,omitempty"`
	Images      []string  `json:"images"`
	Amenities   []string  `json:"amenities"`
	Price       *float64  `json:"price,omitempty"`
	CreatedAt   time.Time `json:"createdAt"`
}

// CreateRequest is the payload for creating a hall.
type CreateRequest struct {
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Capacity    *int     `json:"capacity"`
	Location    string   `json:"location"`
	Images      []string `json:"images"`
	Amenities   []string `json:"amenities"`
	Price       *float64 `json:"price"`
}

// UpdateRequest is the payload for updating a hall. Pointer/slice fields
// distinguish "not provided" from an explicit value.
type UpdateRequest struct {
	Name        *string   `json:"name"`
	Description *string   `json:"description"`
	Capacity    *int      `json:"capacity"`
	Location    *string   `json:"location"`
	Images      *[]string `json:"images"`
	Amenities   *[]string `json:"amenities"`
	Price       *float64  `json:"price"`
}
