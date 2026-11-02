package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
)

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
