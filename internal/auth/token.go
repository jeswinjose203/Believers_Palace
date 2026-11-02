package auth

import (
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims is the JWT claim set carried in access tokens.
type Claims struct {
	UserID   string `json:"uid"`
	Role     Role   `json:"role"`
	ChurchID string `json:"cid,omitempty"`
	jwt.RegisteredClaims
}

// TokenManager issues and verifies JWT access tokens.
type TokenManager struct {
	secret []byte
	ttl    time.Duration
	issuer string
}

// NewTokenManager creates a TokenManager.
func NewTokenManager(secret string, ttl time.Duration, issuer string) *TokenManager {
	return &TokenManager{secret: []byte(secret), ttl: ttl, issuer: issuer}
}

// AccessTTL returns the configured access-token lifetime.
func (m *TokenManager) AccessTTL() time.Duration { return m.ttl }

// Generate creates a signed JWT for the given user.
func (m *TokenManager) Generate(userID string, role Role, churchID string) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID:   userID,
		Role:     role,
		ChurchID: churchID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    m.issuer,
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(m.ttl)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(m.secret)
}

// Parse validates the token string and returns its claims.
func (m *TokenManager) Parse(tokenStr string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return m.secret, nil
	})
	if err != nil {
		return nil, err
	}
	if !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}
	return claims, nil
}
