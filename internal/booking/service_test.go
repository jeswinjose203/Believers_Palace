package booking

import (
	"testing"

	"believers_palace/internal/auth"
)

func TestValidStatus(t *testing.T) {
	valid := []Status{StatusPending, StatusApproved, StatusRejected, StatusCancelled, StatusCompleted}
	for _, s := range valid {
		if !ValidStatus(s) {
			t.Errorf("ValidStatus(%q) = false, want true", s)
		}
	}
	for _, s := range []Status{"", "unknown", "PENDING"} {
		if ValidStatus(s) {
			t.Errorf("ValidStatus(%q) = true, want false", s)
		}
	}
}

func TestCanView(t *testing.T) {
	s := &Service{}
	b := &Booking{UserID: "u1", ChurchID: "c1"}

	tests := []struct {
		name string
		id   auth.Identity
		want bool
	}{
		{"owner", auth.Identity{UserID: "u1", Role: auth.RoleUser}, true},
		{"other user", auth.Identity{UserID: "u2", Role: auth.RoleUser}, false},
		{"super_admin", auth.Identity{UserID: "u9", Role: auth.RoleSuperAdmin}, true},
		{"church_admin same church", auth.Identity{UserID: "u9", Role: auth.RoleChurchAdmin, ChurchID: "c1"}, true},
		{"church_admin other church", auth.Identity{UserID: "u9", Role: auth.RoleChurchAdmin, ChurchID: "c2"}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := s.canView(tt.id, b); got != tt.want {
				t.Errorf("canView() = %v, want %v", got, tt.want)
			}
		})
	}
}
