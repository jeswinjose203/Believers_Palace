package personalcalendar

import (
	"testing"
	"time"
)

func TestCalendarDateUTCIndia(t *testing.T) {
	loc := loadLocation("Asia/Kolkata")
	// Local midnight 15 Nov in IST is still 14 Nov 18:30 UTC.
	utc := time.Date(2026, 11, 14, 18, 30, 0, 0, time.UTC)
	d := calendarDateUTC(utc, loc)
	want := time.Date(2026, 11, 15, 0, 0, 0, 0, time.UTC)
	if !d.Equal(want) {
		t.Fatalf("got %v want %v", d, want)
	}
}