package hall

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
		{"super_admin", auth.Identity{Role: auth.RoleSuperAdmin}, "c1", true},
		{"church_admin own", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c1"}, "c1", true},
		{"church_admin other", auth.Identity{Role: auth.RoleChurchAdmin, ChurchID: "c1"}, "c2", false},
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

func TestEncodeDecodeStrings(t *testing.T) {
	// nil encodes to "[]" and decodes back to a non-nil empty slice.
	enc, err := encodeStrings(nil)
	if err != nil {
		t.Fatalf("encodeStrings(nil) error: %v", err)
	}
	if enc != "[]" {
		t.Errorf("encodeStrings(nil) = %q, want %q", enc, "[]")
	}

	got, err := decodeStrings([]byte("null"))
	if err != nil {
		t.Fatalf("decodeStrings(null) error: %v", err)
	}
	if got == nil || len(got) != 0 {
		t.Errorf("decodeStrings(null) = %v, want empty non-nil slice", got)
	}

	roundtrip, err := encodeStrings([]string{"a", "b"})
	if err != nil {
		t.Fatalf("encodeStrings error: %v", err)
	}
	vals, err := decodeStrings([]byte(roundtrip))
	if err != nil {
		t.Fatalf("decodeStrings error: %v", err)
	}
	if len(vals) != 2 || vals[0] != "a" || vals[1] != "b" {
		t.Errorf("roundtrip = %v, want [a b]", vals)
	}
}
