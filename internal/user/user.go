package user

import (
	"time"

	"believers_palace/internal/auth"
)

// User represents an application user. The password hash is never serialized.
type User struct {
	ID            string    `json:"id"`
	Name          string    `json:"name"`
	Email         string    `json:"email"`
	Phone         *string   `json:"phone"`
	Unit          *string   `json:"unit"`
	ProfilePic    *string   `json:"profilePic"`
	Role          auth.Role `json:"role"`
	ChurchID      *string   `json:"churchId"`
	EmailVerified bool      `json:"emailVerified"`
	CreatedAt     time.Time `json:"createdAt"`

	// PasswordHash is internal only and must never be marshaled to JSON.
	PasswordHash string `json:"-"`
}

// RegisterInput is the payload for user registration.
type RegisterInput struct {
	Name     string  `json:"name"`
	Email    string  `json:"email"`
	Password string  `json:"password"`
	Phone    *string `json:"phone"`
	Unit     *string `json:"unit"`
	ChurchID *string `json:"churchId"`
}

// LoginInput is the payload for login.
type LoginInput struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// ProfileUpdateInput is the payload for updating the current user's profile.
// Pointer fields distinguish "not provided" from "set to null".
type ProfileUpdateInput struct {
	Name       *string `json:"name"`
	Phone      *string `json:"phone"`
	Unit       *string `json:"unit"`
	ProfilePic *string `json:"profilePic"`
	// ChurchID selects the user's church. Only regular users (role "user") may
	// change it; an empty string clears the selection.
	ChurchID *string `json:"churchId"`
}

// AuthResponse is returned on successful register/login/refresh.
// Token is a backward-compatible alias of AccessToken.
type AuthResponse struct {
	AccessToken  string `json:"accessToken"`
	RefreshToken string `json:"refreshToken"`
	ExpiresIn    int    `json:"expiresIn"` // access-token lifetime in seconds
	Token        string `json:"token"`     // deprecated alias of accessToken
	User         *User  `json:"user"`
}

// RefreshInput is the payload for refreshing tokens.
type RefreshInput struct {
	RefreshToken string `json:"refreshToken"`
}

// LogoutInput is the payload for logging out a single session.
type LogoutInput struct {
	RefreshToken string `json:"refreshToken"`
}

// ForgotPasswordInput is the payload for requesting a password reset.
type ForgotPasswordInput struct {
	Email string `json:"email"`
}

// ResetPasswordInput is the payload for completing a password reset.
type ResetPasswordInput struct {
	Token       string `json:"token"`
	NewPassword string `json:"newPassword"`
}

// VerifyEmailInput is the payload for verifying an email address.
type VerifyEmailInput struct {
	Token string `json:"token"`
}

// ResendVerificationInput is the payload for re-issuing a verification token.
type ResendVerificationInput struct {
	Email string `json:"email"`
}
