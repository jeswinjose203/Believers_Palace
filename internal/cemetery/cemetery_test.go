package cemetery

import (
	"testing"

	"believers_palace/internal/auth"
)

func TestValidators(t *testing.T) {
	if !ValidPlotStatus(PlotAvailable) || ValidPlotStatus("bogus") {
		t.Error("ValidPlotStatus failed")
	}
	if !ValidServiceType(ServiceBurial) || ValidServiceType("bogus") {
		t.Error("ValidServiceType failed")
	}
	if !ValidRequestStatus(RequestScheduled) || ValidRequestStatus("bogus") {
		t.Error("ValidRequestStatus failed")
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
		{"church_admin same church", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c1"}, "c1", true},
		{"church_admin other church", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c2"}, "c1", false},
		{"church_admin no church", auth.Identity{Role: auth.RoleChurchAdmin}, "c1", false},
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
