package auth

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestTokenRoundTrip(t *testing.T) {
	tm := NewTokenManager("test-secret", time.Hour, "test-issuer")

	token, err := tm.Generate("user-123", RoleChurchAdmin, "church-9")
	if err != nil {
		t.Fatalf("Generate() error = %v", err)
	}

	claims, err := tm.Parse(token)
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}

	if claims.UserID != "user-123" {
		t.Errorf("UserID = %q, want user-123", claims.UserID)
	}
	if claims.Role != RoleChurchAdmin {
		t.Errorf("Role = %q, want church_admin", claims.Role)
	}
	if claims.ChurchID != "church-9" {
		t.Errorf("ChurchID = %q, want church-9", claims.ChurchID)
	}
}

func TestParseRejectsBadSecret(t *testing.T) {
	signer := NewTokenManager("secret-a", time.Hour, "iss")
	verifier := NewTokenManager("secret-b", time.Hour, "iss")

	token, err := signer.Generate("u1", RoleUser, "")
	if err != nil {
		t.Fatalf("Generate() error = %v", err)
	}
	if _, err := verifier.Parse(token); err == nil {
		t.Error("Parse() with wrong secret should fail")
	}
}

func TestParseRejectsExpired(t *testing.T) {
	tm := NewTokenManager("secret", -time.Minute, "iss")
	token, err := tm.Generate("u1", RoleUser, "")
	if err != nil {
		t.Fatalf("Generate() error = %v", err)
	}
	if _, err := tm.Parse(token); err == nil {
		t.Error("Parse() of expired token should fail")
	}
}

func TestPasswordHashing(t *testing.T) {
	hash, err := HashPassword("s3cret-password")
	if err != nil {
		t.Fatalf("HashPassword() error = %v", err)
	}
	if !CheckPassword(hash, "s3cret-password") {
		t.Error("CheckPassword() should accept correct password")
	}
	if CheckPassword(hash, "wrong") {
		t.Error("CheckPassword() should reject wrong password")
	}
}

func TestDebugMiddlewareInjectsIdentity(t *testing.T) {
	var got Identity
	var ok bool
	next := http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		got, ok = FromContext(r.Context())
	})

	// No headers: defaults to a super_admin using the fixed DebugUserID.
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	DebugMiddleware()(next).ServeHTTP(httptest.NewRecorder(), req)
	if !ok {
		t.Fatal("expected an identity in context")
	}
	if got.UserID != DebugUserID || got.Role != RoleSuperAdmin {
		t.Errorf("default identity = %+v, want %s/super_admin", got, DebugUserID)
	}

	// Headers override the synthetic identity.
	req = httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Debug-User-Id", "u-42")
	req.Header.Set("X-Debug-Role", string(RoleChurchAdmin))
	req.Header.Set("X-Debug-Church-Id", "c-7")
	DebugMiddleware()(next).ServeHTTP(httptest.NewRecorder(), req)
	if got.UserID != "u-42" || got.Role != RoleChurchAdmin || got.ChurchID != "c-7" {
		t.Errorf("overridden identity = %+v, want u-42/church_admin/c-7", got)
	}

	// An invalid role falls back to super_admin.
	req = httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Debug-Role", "nonsense")
	DebugMiddleware()(next).ServeHTTP(httptest.NewRecorder(), req)
	if got.Role != RoleSuperAdmin {
		t.Errorf("invalid role fallback = %q, want super_admin", got.Role)
	}
}

func TestRoleHelpers(t *testing.T) {
	if !RoleSuperAdmin.IsAdmin() || !RoleChurchAdmin.IsAdmin() {
		t.Error("super_admin and church_admin should be admins")
	}
	if RoleUser.IsAdmin() {
		t.Error("user should not be admin")
	}
	if !RoleSuperAdmin.IsSuperAdmin() || RoleChurchAdmin.IsSuperAdmin() {
		t.Error("IsSuperAdmin mismatch")
	}
	if ValidRole("nonsense") {
		t.Error("ValidRole should reject unknown role")
	}
}

func TestIsChurchStaff(t *testing.T) {
	staff := []Role{RolePriest, RoleAssociatePriest, RoleChurchAdmin}
	for _, r := range staff {
		if !r.IsChurchStaff() {
			t.Errorf("%q should be church staff", r)
		}
	}
	for _, r := range []Role{RoleUser, RoleSuperAdmin} {
		if r.IsChurchStaff() {
			t.Errorf("%q should not be church staff", r)
		}
	}
}

func TestCanManageChurchContent(t *testing.T) {
	tests := []struct {
		name string
		id   Identity
		want bool
	}{
		{"super_admin any church", Identity{Role: RoleSuperAdmin}, true},
		{"church_admin own church", Identity{Role: RoleChurchAdmin, ChurchID: "c1"}, true},
		{"priest own church", Identity{Role: RolePriest, ChurchID: "c1"}, true},
		{"associate_priest own church", Identity{Role: RoleAssociatePriest, ChurchID: "c1"}, true},
		{"priest other church", Identity{Role: RolePriest, ChurchID: "c2"}, false},
		{"priest no church", Identity{Role: RolePriest, ChurchID: ""}, false},
		{"regular user", Identity{Role: RoleUser, ChurchID: "c1"}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := CanManageChurchContent(tt.id, "c1"); got != tt.want {
				t.Errorf("CanManageChurchContent() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestCanManageChurchExcludesPriests(t *testing.T) {
	// Administrative actions must NOT be available to priests.
	if CanManageChurch(Identity{Role: RolePriest, ChurchID: "c1"}, "c1") {
		t.Error("priest must not pass CanManageChurch (administrative)")
	}
	if !CanManageChurch(Identity{Role: RoleChurchAdmin, ChurchID: "c1"}, "c1") {
		t.Error("church_admin should pass CanManageChurch for own church")
	}
	if CanManageChurch(Identity{Role: RoleChurchAdmin, ChurchID: "c2"}, "c1") {
		t.Error("church_admin should not manage a different church")
	}
}
