package church

import (
	"testing"

	"believers_palace/internal/auth"
)

func TestCanManage(t *testing.T) {
	s := &Service{}

	tests := []struct {
		name     string
		id       auth.Identity
		churchID string
		want     bool
	}{
		{
			name:     "super_admin any church",
			id:       auth.Identity{Role: auth.RoleSuperAdmin},
			churchID: "church-1",
			want:     true,
		},
		{
			name:     "church_admin own church",
			id:       auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "church-1"},
			churchID: "church-1",
			want:     true,
		},
		{
			name:     "church_admin other church",
			id:       auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "church-1"},
			churchID: "church-2",
			want:     false,
		},
		{
			name:     "church_admin with no church",
			id:       auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: ""},
			churchID: "church-1",
			want:     false,
		},
		{
			name:     "regular user",
			id:       auth.Identity{Role: auth.RoleUser, ChurchID: "church-1"},
			churchID: "church-1",
			want:     false,
		},
		{
			name:     "priest",
			id:       auth.Identity{Role: auth.RolePriest, ChurchID: "church-1"},
			churchID: "church-1",
			want:     false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := s.canManage(tt.id, tt.churchID); got != tt.want {
				t.Errorf("canManage() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestValidate(t *testing.T) {
	if err := validate(Request{Name: "St. Mary"}); err != nil {
		t.Errorf("validate(valid) = %v, want nil", err)
	}
	if err := validate(Request{Name: "   "}); err == nil {
		t.Error("validate(blank name) should fail")
	}
}
