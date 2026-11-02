package announcement

import (
	"testing"

	"believers_palace/internal/auth"
)

func TestCanManageChurch(t *testing.T) {
	tests := []struct {
		name     string
		id       auth.Identity
		churchID string
		want     bool
	}{
		{"super_admin any church", auth.Identity{Role: auth.RoleSuperAdmin}, "c1", true},
		{"church_admin own church", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c1"}, "c1", true},
		{"church_admin other church", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c1"}, "c2", false},
		{"church_admin no church", auth.Identity{Role: auth.RoleChurchAdmin}, "c1", false},
		{"regular user", auth.Identity{Role: auth.RoleUser, ChurchID: "c1"}, "c1", false},
		{"priest own church", auth.Identity{Role: auth.RolePriest, ChurchID: "c1"}, "c1", true},
		{"priest other church", auth.Identity{Role: auth.RolePriest, ChurchID: "c1"}, "c2", false},
		{"associate_priest own church", auth.Identity{Role: auth.RoleAssociatePriest, ChurchID: "c1"}, "c1", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := canManageChurch(tt.id, tt.churchID); got != tt.want {
				t.Errorf("canManageChurch() = %v, want %v", got, tt.want)
			}
		})
	}
}
