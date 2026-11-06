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

func TestImagesRoundTrip(t *testing.T) {
	enc, err := encodeStrings([]string{"a.png", "b.png"})
	if err != nil {
		t.Fatal(err)
	}
	got, err := decodeStrings([]byte(enc))
	if err != nil || len(got) != 2 || got[0] != "a.png" || got[1] != "b.png" {
		t.Errorf("round trip = %v, %v", got, err)
	}
	if empty, _ := decodeStrings(nil); empty == nil || len(empty) != 0 {
		t.Errorf("decodeStrings(nil) = %v, want non-nil empty slice", empty)
	}
	if enc, _ := encodeStrings(nil); enc != "[]" {
		t.Errorf("encodeStrings(nil) = %q, want []", enc)
	}
}
