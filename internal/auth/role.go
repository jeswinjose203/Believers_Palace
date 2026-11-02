// Package auth provides JWT token management, password hashing, role
// definitions, and HTTP middleware for authentication and authorization.
package auth

// Role is a user role as defined by the API spec.
type Role string

const (
	RoleUser            Role = "user"
	RolePriest          Role = "priest"
	RoleAssociatePriest Role = "associate_priest"
	RoleChurchAdmin     Role = "church_admin"
	RoleSuperAdmin      Role = "super_admin"
)

// ValidRole reports whether r is a recognized role.
func ValidRole(r Role) bool {
	switch r {
	case RoleUser, RolePriest, RoleAssociatePriest, RoleChurchAdmin, RoleSuperAdmin:
		return true
	default:
		return false
	}
}

// IsAdmin reports whether the role has administrative privileges
// (church_admin or super_admin).
func (r Role) IsAdmin() bool {
	return r == RoleChurchAdmin || r == RoleSuperAdmin
}

// IsChurchStaff reports whether the role is church staff scoped to a church:
// priest, associate_priest, or church_admin. These roles may manage pastoral
// content (announcements, events) for their own church. super_admin is not
// included here because it is not church-scoped (it is handled separately).
func (r Role) IsChurchStaff() bool {
	return r == RolePriest || r == RoleAssociatePriest || r == RoleChurchAdmin
}

// IsSuperAdmin reports whether the role is super_admin.
func (r Role) IsSuperAdmin() bool {
	return r == RoleSuperAdmin
}
