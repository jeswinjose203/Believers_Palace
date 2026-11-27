package marketplace

import (
	"errors"
	"time"
)

var (
	ErrNotFound   = errors.New("not found")
	ErrForbidden  = errors.New("insufficient permissions")
	ErrConflict   = errors.New("conflict")
	ErrBadRequest = errors.New("bad request")
)

const (
	ScopeCommunity = "community"
	ScopeShop      = "shop"

	ConditionNew  = "new"
	ConditionUsed = "used"

	StatusPending   = "pending_approval"
	StatusApproved  = "approved"
	StatusRejected  = "rejected"
	StatusSold      = "sold"
	StatusRemoved   = "removed"
)

// ValidationError describes invalid input.
type ValidationError struct{ Message string }

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

type Category struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Scope     string    `json:"scope"`
	SortOrder int       `json:"sortOrder"`
	Active    bool      `json:"active"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type CategoryRequest struct {
	Name      string `json:"name"`
	SortOrder *int   `json:"sortOrder"`
	Active    *bool  `json:"active"`
}

type SellerSummary struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	ProfilePic  *string `json:"profilePic,omitempty"`
}

type CommunityAd struct {
	ID              string    `json:"id"`
	SellerID        string    `json:"sellerId"`
	CategoryID      string    `json:"categoryId"`
	CategoryName    string    `json:"categoryName,omitempty"`
	Title           string    `json:"title"`
	Description     string    `json:"description"`
	Images          []string  `json:"images"`
	PriceCents      int       `json:"priceCents"`
	Condition       string    `json:"condition"`
	Location        string    `json:"location"`
	ContactPhone    *string   `json:"contactPhone,omitempty"`
	ContactEmail    *string   `json:"contactEmail,omitempty"`
	Status          string    `json:"status"`
	RejectionReason *string   `json:"rejectionReason,omitempty"`
	ReviewedAt      *time.Time `json:"reviewedAt,omitempty"`
	CreatedAt       time.Time `json:"createdAt"`
	UpdatedAt       time.Time `json:"updatedAt"`
	Seller          *SellerSummary `json:"seller,omitempty"`
}

type CommunityAdRequest struct {
	CategoryID   string   `json:"categoryId"`
	Title        string   `json:"title"`
	Description  string   `json:"description"`
	Images       []string `json:"images"`
	PriceCents   int      `json:"priceCents"`
	Condition    string   `json:"condition"`
	Location     string   `json:"location"`
	ContactPhone *string  `json:"contactPhone"`
	ContactEmail *string  `json:"contactEmail"`
}

type RejectRequest struct {
	Reason *string `json:"reason"`
}

type ShopProduct struct {
	ID           string    `json:"id"`
	CategoryID   *string   `json:"categoryId,omitempty"`
	CategoryName string    `json:"categoryName,omitempty"`
	Title        string    `json:"title"`
	Description  string    `json:"description"`
	Images       []string  `json:"images"`
	PriceCents   int       `json:"priceCents"`
	Active       bool      `json:"active"`
	CreatedBy    string    `json:"createdBy"`
	CreatedAt    time.Time `json:"createdAt"`
	UpdatedAt    time.Time `json:"updatedAt"`
}

type ShopProductRequest struct {
	CategoryID  *string  `json:"categoryId"`
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Images      []string `json:"images"`
	PriceCents  int      `json:"priceCents"`
	Active      *bool    `json:"active"`
}

type AdListFilter struct {
	Statuses    []string
	SellerID    string
	CategoryID  string
	Search      string
	MinPrice    int
	MaxPrice    int
	ExcludeSold bool
	Limit       int
	Offset      int
}

type ShopListFilter struct {
	ActiveOnly bool
	CategoryID string
	Search     string
	MinPrice   int
	MaxPrice   int
	Limit      int
	Offset     int
}

func validScope(s string) bool {
	return s == ScopeCommunity || s == ScopeShop
}

func validCondition(c string) bool {
	return c == ConditionNew || c == ConditionUsed
}

func validAdStatus(s string) bool {
	switch s {
	case StatusPending, StatusApproved, StatusRejected, StatusSold, StatusRemoved:
		return true
	default:
		return false
	}
}