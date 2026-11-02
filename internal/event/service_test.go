package event

import (
	"testing"
	"time"

	"believers_palace/internal/auth"
)

func TestValidate(t *testing.T) {
	now := time.Now()
	later := now.Add(time.Hour)
	cap0 := 0

	tests := []struct {
		name    string
		in      Request
		wantErr bool
	}{
		{"valid minimal", Request{Title: "Service", StartDate: &now}, false},
		{"valid with end", Request{Title: "Service", StartDate: &now, EndDate: &later}, false},
		{"missing title", Request{StartDate: &now}, true},
		{"blank title", Request{Title: "   ", StartDate: &now}, true},
		{"missing start", Request{Title: "Service"}, true},
		{"end before start", Request{Title: "Service", StartDate: &later, EndDate: &now}, true},
		{"zero capacity", Request{Title: "Service", StartDate: &now, Capacity: &cap0}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validate(tt.in)
			if (err != nil) != tt.wantErr {
				t.Errorf("validate() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

// TestCanManageChurch covers the authorization used by ListRegistrations and
// the create/update/delete paths.
func TestCanManageChurch(t *testing.T) {
	tests := []struct {
		name     string
		id       auth.Identity
		churchID string
		want     bool
	}{
		{"super_admin", auth.Identity{Role: auth.RoleSuperAdmin}, "c1", true},
		{"church_admin same church", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c1"}, "c1", true},
		{"church_admin other church", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c2"}, "c1", false},
		{"priest own church", auth.Identity{Role: auth.RolePriest, ChurchID: "c1"}, "c1", true},
		{"regular user", auth.Identity{Role: auth.RoleUser}, "c1", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := canManageChurch(tt.id, tt.churchID); got != tt.want {
				t.Errorf("canManageChurch() = %v, want %v", got, tt.want)
			}
		})
	}
}
