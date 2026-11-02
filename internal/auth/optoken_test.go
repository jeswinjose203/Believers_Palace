package auth

import "testing"

func TestGenerateOpaqueTokenIsRandomAndHashes(t *testing.T) {
	raw1, hash1, err := GenerateOpaqueToken()
	if err != nil {
		t.Fatalf("GenerateOpaqueToken() error = %v", err)
	}
	raw2, hash2, err := GenerateOpaqueToken()
	if err != nil {
		t.Fatalf("GenerateOpaqueToken() error = %v", err)
	}

	if raw1 == "" || hash1 == "" {
		t.Fatal("expected non-empty token and hash")
	}
	if raw1 == raw2 {
		t.Error("expected two generated tokens to differ")
	}
	if hash1 == hash2 {
		t.Error("expected two generated hashes to differ")
	}
	if raw1 == hash1 {
		t.Error("raw token must not equal its hash")
	}
	// The stored hash must be derivable from the raw token.
	if HashToken(raw1) != hash1 {
		t.Error("HashToken(raw) did not match the returned hash")
	}
}

func TestHashTokenIsDeterministic(t *testing.T) {
	if HashToken("abc") != HashToken("abc") {
		t.Error("HashToken must be deterministic for the same input")
	}
	if HashToken("abc") == HashToken("abd") {
		t.Error("HashToken must differ for different inputs")
	}
}
