package auth

import (
	"context"
	"net/http"
	"strings"

	"believers_palace/internal/httpx"
)

type ctxKey int

const identityKey ctxKey = iota

// DebugUserID is the fixed user ID used by DebugMiddleware when no
// X-Debug-User-Id header is supplied. A matching row is inserted by the
// development seed (migrations are schema-only), so foreign-key-bound
// operations (bookings, service requests, etc.) work out of the box when
// SKIP_JWT_VALIDATION is enabled.
const DebugUserID = "00000000-0000-0000-0000-000000000001"

// Identity is the authenticated principal extracted from a valid JWT.
type Identity struct {
	UserID   string
	Role     Role
	ChurchID string
}

// CanManageChurch reports whether the identity may perform administrative
// actions on the given church: super_admin anywhere, or a church_admin scoped
// to their own church. Use this for administrative resources (halls, booking
// status, cemetery plots/requests).
func CanManageChurch(id Identity, churchID string) bool {
	if id.Role.IsSuperAdmin() {
		return true
	}
	return id.Role == RoleChurchAdmin && id.ChurchID != "" && id.ChurchID == churchID
}

// CanManageChurchContent reports whether the identity may manage pastoral
// content (announcements, events) for the given church: super_admin anywhere,
// or church staff (priest, associate_priest, church_admin) scoped to their own
// church.
func CanManageChurchContent(id Identity, churchID string) bool {
	if id.Role.IsSuperAdmin() {
		return true
	}
	return id.Role.IsChurchStaff() && id.ChurchID != "" && id.ChurchID == churchID
}

// Middleware returns HTTP middleware that requires a valid bearer token and
// stores the resulting Identity in the request context.
func Middleware(tm *TokenManager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token, ok := bearerToken(r)
			if !ok {
				httpx.ErrorCode(w, http.StatusUnauthorized, "authentication required", "unauthorized")
				return
			}

			claims, err := tm.Parse(token)
			if err != nil {
				httpx.ErrorCode(w, http.StatusUnauthorized, "invalid or expired token", "unauthorized")
				return
			}

			id := Identity{
				UserID:   claims.UserID,
				Role:     claims.Role,
				ChurchID: claims.ChurchID,
			}
			ctx := context.WithValue(r.Context(), identityKey, id)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// DebugMiddleware returns HTTP middleware that BYPASSES JWT validation and
// injects a synthetic Identity. It is intended ONLY for local API testing
// (e.g. with Postman) and must never be enabled in production.
//
// The injected identity defaults to a super_admin so every endpoint is
// reachable. Individual requests may override it with optional headers:
//
//	X-Debug-User-Id    sets the user ID    (default DebugUserID)
//	X-Debug-Role       sets the role       (default "super_admin")
//	X-Debug-Church-Id  sets the church ID  (default empty)
//
// An unrecognized X-Debug-Role falls back to super_admin.
func DebugMiddleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			userID := r.Header.Get("X-Debug-User-Id")
			if userID == "" {
				userID = DebugUserID
			}

			role := Role(r.Header.Get("X-Debug-Role"))
			if !ValidRole(role) {
				role = RoleSuperAdmin
			}

			id := Identity{
				UserID:   userID,
				Role:     role,
				ChurchID: r.Header.Get("X-Debug-Church-Id"),
			}
			ctx := context.WithValue(r.Context(), identityKey, id)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireRole returns middleware that permits only the given roles.
// It must be used after Middleware.
func RequireRole(roles ...Role) func(http.Handler) http.Handler {
	allowed := make(map[Role]bool, len(roles))
	for _, r := range roles {
		allowed[r] = true
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			id, ok := FromContext(r.Context())
			if !ok {
				httpx.ErrorCode(w, http.StatusUnauthorized, "authentication required", "unauthorized")
				return
			}
			if !allowed[id.Role] {
				httpx.ErrorCode(w, http.StatusForbidden, "insufficient permissions", "forbidden")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// FromContext returns the Identity stored in ctx, if any.
func FromContext(ctx context.Context) (Identity, bool) {
	id, ok := ctx.Value(identityKey).(Identity)
	return id, ok
}

// MustFromContext returns the Identity stored in ctx, panicking if absent.
// Use only in handlers mounted behind Middleware.
func MustFromContext(ctx context.Context) Identity {
	id, ok := FromContext(ctx)
	if !ok {
		panic("auth: identity missing from context")
	}
	return id
}

func bearerToken(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	if h == "" {
		return "", false
	}
	const prefix = "Bearer "
	if len(h) <= len(prefix) || !strings.EqualFold(h[:len(prefix)], prefix) {
		return "", false
	}
	return strings.TrimSpace(h[len(prefix):]), true
}
