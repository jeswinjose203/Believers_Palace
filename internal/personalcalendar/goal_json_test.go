package personalcalendar

import "testing"

func TestFlexibleGoalRequest_dateOnly(t *testing.T) {
	ymd := "2026-11-15"
	f := flexibleGoalRequest{
		Title:      "read",
		TargetDays: ptrInt(7),
		StartDate:  &ymd,
	}
	in, err := f.toGoalRequest()
	if err != nil {
		t.Fatal(err)
	}
	if in.StartDate == nil || in.StartDate.Format("2006-01-02") != ymd {
		t.Fatalf("startDate = %v", in.StartDate)
	}
}

func ptrInt(n int) *int { return &n }