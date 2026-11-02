// Package httpx contains shared HTTP helpers for JSON responses, errors,
// and pagination.
package httpx

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
)

// JSON writes v as a JSON response with the given status code.
func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("httpx: encode response: %v", err)
	}
}

// ErrorBody is the standard error response envelope defined by the API spec.
type ErrorBody struct {
	Message string         `json:"message"`
	Code    string         `json:"code,omitempty"`
	Details map[string]any `json:"details,omitempty"`
}

// Error writes a JSON error response with the given status code and message.
func Error(w http.ResponseWriter, status int, message string) {
	JSON(w, status, ErrorBody{Message: message})
}

// ErrorCode writes a JSON error response with a machine-readable code.
func ErrorCode(w http.ResponseWriter, status int, message, code string) {
	JSON(w, status, ErrorBody{Message: message, Code: code})
}

// ErrorDetails writes a JSON error response with a code and details map.
func ErrorDetails(w http.ResponseWriter, status int, message, code string, details map[string]any) {
	JSON(w, status, ErrorBody{Message: message, Code: code, Details: details})
}

// Pagination is the pagination metadata envelope defined by the API spec.
type Pagination struct {
	Page       int `json:"page"`
	Limit      int `json:"limit"`
	Total      int `json:"total"`
	TotalPages int `json:"totalPages"`
}

// NewPagination builds pagination metadata from the page, limit, and total count.
func NewPagination(page, limit, total int) Pagination {
	totalPages := 0
	if limit > 0 {
		totalPages = (total + limit - 1) / limit
	}
	return Pagination{Page: page, Limit: limit, Total: total, TotalPages: totalPages}
}

// Page is a generic paginated list envelope: {data, pagination}.
type Page[T any] struct {
	Data       []T        `json:"data"`
	Pagination Pagination `json:"pagination"`
}

// Paged writes a 200 response with a {data, pagination} envelope.
func Paged[T any](w http.ResponseWriter, items []T, page, limit, total int) {
	if items == nil {
		items = []T{}
	}
	JSON(w, http.StatusOK, Page[T]{
		Data:       items,
		Pagination: NewPagination(page, limit, total),
	})
}

// PageParams holds normalized pagination query parameters.
type PageParams struct {
	Page   int
	Limit  int
	Offset int
}

const (
	defaultPage  = 1
	defaultLimit = 20
	maxLimit     = 100
)

// ParsePageParams reads and clamps the page/limit query parameters per the spec
// (page >= 1 default 1; limit 1..100 default 20).
func ParsePageParams(r *http.Request) PageParams {
	page := defaultPage
	if v := r.URL.Query().Get("page"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 1 {
			page = n
		}
	}

	limit := defaultLimit
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 1 {
			limit = n
		}
	}
	if limit > maxLimit {
		limit = maxLimit
	}

	return PageParams{
		Page:   page,
		Limit:  limit,
		Offset: (page - 1) * limit,
	}
}

// DecodeJSON decodes the request body into dst, rejecting unknown fields.
func DecodeJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}
