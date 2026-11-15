package personalcalendar

import (
	"net/http/httptest"
	"testing"
	"time"
)

func TestParseEventListQuery_upcomingDays(t *testing.T) {
	req := httptest.NewRequest("GET", "/events?upcomingDays=7&order=asc", nil)
	q, err := ParseEventListQuery(req)
	if err != nil {
		t.Fatal(err)
	}
	if !q.OrderAsc {
		t.Fatal("expected asc order")
	}
	if q.From == nil || q.To == nil {
		t.Fatal("expected from/to")
	}
	if q.To.Sub(*q.From) < 7*24*time.Hour {
		t.Fatalf("range too short: %v", q.To.Sub(*q.From))
	}
}

func TestParseEventListQuery_dateRange(t *testing.T) {
	req := httptest.NewRequest("GET", "/events?fromDate=2026-01-01&toDate=2026-01-07", nil)
	q, err := ParseEventListQuery(req)
	if err != nil {
		t.Fatal(err)
	}
	if q.From == nil || q.To == nil {
		t.Fatal("expected range")
	}
}