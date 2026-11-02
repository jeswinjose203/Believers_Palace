package user

import "testing"

func TestValidEmail(t *testing.T) {
	valid := []string{"a@b.com", "john.doe@example.org", "x+tag@test.io"}
	invalid := []string{"", "notanemail", "@no-local.com", "no-at-sign.com"}

	for _, e := range valid {
		if !validEmail(e) {
			t.Errorf("validEmail(%q) = false, want true", e)
		}
	}
	for _, e := range invalid {
		if validEmail(e) {
			t.Errorf("validEmail(%q) = true, want false", e)
		}
	}
}
