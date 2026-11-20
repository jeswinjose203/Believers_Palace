package catechism

import (
	"testing"
	"time"

	"believers_palace/internal/auth"
)

func TestValidateClassRequest(t *testing.T) {
	start := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	end := time.Date(2027, 5, 1, 0, 0, 0, 0, time.UTC)
	badEnd := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	cap20 := 20

	tests := []struct {
		name    string
		in      ClassRequest
		wantErr bool
	}{
		{
			name: "valid",
			in: ClassRequest{
				Name: "First Communion", Level: LevelFirstCommunion,
				StartDate: &start, EndDate: &end, Capacity: &cap20, Status: StatusOpen,
			},
		},
		{"missing name", ClassRequest{Level: LevelAdult, StartDate: &start, EndDate: &end, Capacity: &cap20}, true},
		{"bad level", ClassRequest{Name: "X", Level: "invalid", StartDate: &start, EndDate: &end, Capacity: &cap20}, true},
		{"end before start", ClassRequest{Name: "X", Level: LevelAdult, StartDate: &start, EndDate: &badEnd, Capacity: &cap20}, true},
		{"zero capacity", ClassRequest{Name: "X", Level: LevelAdult, StartDate: &start, EndDate: &end, Capacity: intPtr(0)}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateClassRequest(tt.in)
			if (err != nil) != tt.wantErr {
				t.Errorf("validateClassRequest() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestValidateEnrollmentAge(t *testing.T) {
	minAge, maxAge := 7, 12
	cls := &Class{MinAge: &minAge, MaxAge: &maxAge}
	tooYoung := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	okDOB := time.Date(2016, 1, 1, 0, 0, 0, 0, time.UTC)
	future := time.Now().Add(24 * time.Hour)

	if err := validateEnrollmentRequest(EnrollmentRequest{StudentName: "Ann", DateOfBirth: &okDOB}, cls); err != nil {
		t.Fatalf("expected valid enrollment, got %v", err)
	}
	if err := validateEnrollmentRequest(EnrollmentRequest{StudentName: "Bob", DateOfBirth: &tooYoung}, cls); err == nil {
		t.Fatal("expected age validation error")
	}
	if err := validateEnrollmentRequest(EnrollmentRequest{StudentName: "Bob", DateOfBirth: &future}, cls); err == nil {
		t.Fatal("expected future DOB error")
	}
}

func TestCanManageChurch(t *testing.T) {
	tests := []struct {
		name     string
		id       auth.Identity
		churchID string
		want     bool
	}{
		{"super_admin", auth.Identity{Role: auth.RoleSuperAdmin}, "c1", true},
		{"church_admin same", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c1"}, "c1", true},
		{"church_admin other", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c2"}, "c1", false},
		{"priest own", auth.Identity{Role: auth.RolePriest, ChurchID: "c1"}, "c1", true},
		{"user", auth.Identity{Role: auth.RoleUser, ChurchID: "c1"}, "c1", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := canManageChurch(tt.id, tt.churchID); got != tt.want {
				t.Errorf("canManageChurch() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestValidEnums(t *testing.T) {
	if !ValidClassLevel(LevelSundaySchool) || ValidClassLevel("nope") {
		t.Fatal("ValidClassLevel")
	}
	if !ValidClassStatus(StatusOpen) || ValidClassStatus("nope") {
		t.Fatal("ValidClassStatus")
	}
	if !ValidEnrollmentStatus(EnrollPending) || ValidEnrollmentStatus("nope") {
		t.Fatal("ValidEnrollmentStatus")
	}
}

func intPtr(n int) *int { return &n }