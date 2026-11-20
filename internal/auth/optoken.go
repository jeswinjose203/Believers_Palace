package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
)

// HashEmailVerificationCode keys the digest because six-digit codes have a
// small enough search space to recover from an unkeyed hash.
func (m *TokenManager) HashEmailVerificationCode(email, code string) string {
	mac := hmac.New(sha256.New, m.secret)
	mac.Write([]byte("email-verification\x00" + email + "\x00" + code))
	return hex.EncodeToString(mac.Sum(nil))
}

// GenerateOpaqueToken returns a cryptographically random, URL-safe token (the
// raw value given to the client) together with its SHA-256 hash (the value
// stored server-side). The raw token is never persisted.
func GenerateOpaqueToken() (raw string, hash string, err error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", "", err
	}
	raw = hex.EncodeToString(b)
	return raw, HashToken(raw), nil
}

// HashToken returns the hex-encoded SHA-256 hash of an opaque token. Used to
// look up stored refresh/reset tokens without keeping the raw value.
func HashToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
