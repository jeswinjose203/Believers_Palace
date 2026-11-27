package user

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"believers_palace/internal/auth"
	"believers_palace/internal/mailer"
)

func TestRegisterRequiresPhoneProof(t *testing.T) {
	phone := "+91 (98765) 43210"
	in := RegisterInput{Name: "Signup test", Email: "signup@example.test", Password: "test-password", Phone: &phone}
	svc := newValidationOnlyService()
	if _, err := svc.Register(context.Background(), in); err == nil {
		t.Fatal("registration without phone proof succeeded")
	}
	in.FirebaseIDToken = "untrusted"
	if _, err := svc.Register(context.Background(), in); !errors.Is(err, errSignupProofUnavailable) {
		t.Fatalf("unconfigured registration error = %v", err)
	}
	svc.verifySignupPhone = func(_ context.Context, token, normalized string) error {
		if token != in.FirebaseIDToken || normalized != "+919876543210" {
			t.Fatal("verification received unexpected signup data")
		}
		return errSignupProofInvalid
	}
	if _, err := svc.Register(context.Background(), in); !errors.Is(err, errSignupProofInvalid) {
		t.Fatalf("invalid proof error = %v", err)
	}
}

func TestFirebaseSignupTokenVerification(t *testing.T) {
	signingKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().Truncate(time.Second)
	cert := &x509.Certificate{SerialNumber: big.NewInt(1), NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour)}
	der, err := x509.CreateCertificate(rand.Reader, cert, cert, &signingKey.PublicKey, signingKey)
	if err != nil {
		t.Fatal(err)
	}
	encoded := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	var requests atomic.Int32
	keys := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		w.Header().Set("Cache-Control", "public, max-age=3600")
		json.NewEncoder(w).Encode(map[string]string{"test-key": string(encoded)})
	}))
	defer keys.Close()

	const project = "test-project"
	const phone = "+919876543210"
	verifier := &firebasePhoneVerifier{project: project, client: keys.Client(), certURL: keys.URL}
	for _, tc := range []struct {
		name string
		edit func(*firebasePhoneClaims, *jwt.Token)
		want error
	}{
		{name: "valid"},
		{name: "wrong project", edit: func(c *firebasePhoneClaims, _ *jwt.Token) { c.Audience = jwt.ClaimStrings{"wrong-project"} }, want: errSignupProofInvalid},
		{name: "wrong issuer", edit: func(c *firebasePhoneClaims, _ *jwt.Token) { c.Issuer = "https://securetoken.google.com/other-project" }, want: errSignupProofInvalid},
		{name: "wrong phone", edit: func(c *firebasePhoneClaims, _ *jwt.Token) { c.Phone = "+919876543211" }, want: errSignupProofInvalid},
		{name: "another provider", edit: func(c *firebasePhoneClaims, _ *jwt.Token) { c.Firebase.Provider = "password" }, want: errSignupProofInvalid},
		{name: "stale authentication", edit: func(c *firebasePhoneClaims, _ *jwt.Token) { c.AuthTime = now.Add(-11 * time.Minute).Unix() }, want: errSignupProofInvalid},
		{name: "wrong algorithm", edit: func(_ *firebasePhoneClaims, t *jwt.Token) { t.Header["alg"] = "HS256" }, want: errSignupProofInvalid},
		{name: "expired", edit: func(c *firebasePhoneClaims, _ *jwt.Token) { c.ExpiresAt = jwt.NewNumericDate(now.Add(-time.Second)) }, want: errSignupProofInvalid},
		{name: "unknown key", edit: func(_ *firebasePhoneClaims, t *jwt.Token) { t.Header["kid"] = "other-key" }, want: errSignupProofInvalid},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := &firebasePhoneClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					Issuer:    "https://securetoken.google.com/" + project,
					Audience:  jwt.ClaimStrings{project},
					Subject:   "firebase-user",
					IssuedAt:  jwt.NewNumericDate(now),
					ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
				},
				Phone:    phone,
				AuthTime: now.Unix(),
			}
			c.Firebase.Provider = "phone"
			token := jwt.NewWithClaims(jwt.SigningMethodRS256, c)
			token.Header["kid"] = "test-key"
			if tc.edit != nil {
				tc.edit(c, token)
			}
			raw, err := token.SignedString(signingKey)
			if err != nil {
				t.Fatal(err)
			}
			if err := verifier.verify(context.Background(), raw, phone); !errors.Is(err, tc.want) {
				t.Fatalf("verify error = %v, want %v", err, tc.want)
			}
		})
	}
	if requests.Load() != 1 {
		t.Fatalf("certificate fetches = %d, want 1", requests.Load())
	}
}

func TestDBSignupPhoneVerification(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("requires a migrated disposable database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	svc := NewService(NewRepository(pool), auth.NewTokenManager("signup-test-secret", time.Hour, "signup-test"),
		mailer.NewLogMailer("http://localhost"), time.Hour, time.Hour)
	now := time.Now().UnixNano()
	email := fmt.Sprintf("signup-%d@example.test", now)
	phone := fmt.Sprintf("+1555%07d", now%10_000_000)
	duplicateEmail := "duplicate-" + email
	username := fmt.Sprintf("Signup_%d", now)
	otherUsername := fmt.Sprintf("Other_%d", now)
	otherPhone := fmt.Sprintf("+1556%07d", now%10_000_000)
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		pool.Exec(cleanupCtx, "DELETE FROM users WHERE email IN ($1, $2)", email, duplicateEmail)
	}()

	svc.verifySignupPhone = func(_ context.Context, token, destination string) error {
		if token != "test-proof" || (destination != phone && destination != otherPhone) {
			return errSignupProofInvalid
		}
		return nil
	}
	in := RegisterInput{Name: "Signup test", Email: email, Password: "test-password", Phone: &phone, FirebaseIDToken: "test-proof", Username: &username}
	duplicate := in
	duplicate.Email = duplicateEmail
	duplicate.Username = &otherUsername
	type result struct {
		response *AuthResponse
		err      error
	}
	results := make(chan result, 2)
	for _, input := range []RegisterInput{in, duplicate} {
		go func(input RegisterInput) {
			response, err := svc.Register(ctx, input)
			results <- result{response, err}
		}(input)
	}
	successes := 0
	var storedUsername string
	for i := 0; i < cap(results); i++ {
		got := <-results
		switch {
		case got.err == nil:
			successes++
			want := username
			if got.response.User.Email == duplicateEmail {
				want = otherUsername
			}
			if err := pool.QueryRow(ctx, "SELECT username FROM users WHERE id=$1", got.response.User.ID).Scan(&storedUsername); err != nil || storedUsername != want {
				t.Fatalf("stored username = %q, want %q, err = %v", storedUsername, want, err)
			}
			if !got.response.User.PhoneVerified || got.response.RefreshToken == "" {
				t.Fatal("successful signup did not verify the phone and issue a session")
			}
		case !errors.Is(got.err, ErrPhoneExists):
			t.Fatal(got.err)
		}
	}
	if successes != 1 {
		t.Fatalf("successful signups for one phone = %d, want 1", successes)
	}
	taken := strings.ToLower(storedUsername)
	collision := RegisterInput{Name: "Collision test", Email: "collision-" + email, Password: in.Password, Phone: &otherPhone, FirebaseIDToken: in.FirebaseIDToken, Username: &taken}
	defer pool.Exec(context.Background(), "DELETE FROM users WHERE email=$1", collision.Email)
	if _, err := svc.Register(ctx, collision); !errors.Is(err, ErrUsernameExists) {
		t.Fatalf("case-insensitive username collision returned %v", err)
	}
}
