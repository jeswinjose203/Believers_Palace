package user

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"believers_palace/internal/auth"
)

var (
	signupPhonePattern        = regexp.MustCompile(`^\+[1-9][0-9]{7,14}$`)
	errSignupProofInvalid     = errors.New("Mobile verification expired or does not match. Request a new code.")
	errSignupProofUnavailable = errors.New("Mobile verification is temporarily unavailable. Try again later.")
	ErrPhoneExists            = errors.New("This mobile number is already registered. Sign in or use a different number.")
)

func normalizeSignupPhone(input string) (string, error) {
	phone := strings.NewReplacer(" ", "", "-", "", "(", "", ")", "").Replace(strings.TrimSpace(input))
	if !signupPhonePattern.MatchString(phone) {
		return "", invalid("Enter a mobile number with its country code, such as +919876543210.")
	}
	return phone, nil
}

const firebaseCertURL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"

type firebasePhoneVerifier struct {
	project string
	client  *http.Client
	certURL string

	mu         sync.Mutex
	keys       map[string]*rsa.PublicKey
	expires    time.Time
	retryAfter time.Time
}

type firebasePhoneClaims struct {
	jwt.RegisteredClaims
	Phone    string `json:"phone_number"`
	AuthTime int64  `json:"auth_time"`
	Firebase struct {
		Provider string `json:"sign_in_provider"`
	} `json:"firebase"`
}

// SetFirebaseSignupProject enables phone verification for the given Firebase project.
func (s *Service) SetFirebaseSignupProject(project string) {
	verifier := &firebasePhoneVerifier{
		project: project,
		client:  &http.Client{Timeout: 5 * time.Second},
		certURL: firebaseCertURL,
	}
	s.verifySignupPhone = verifier.verify
}

func (v *firebasePhoneVerifier) verify(ctx context.Context, token, phone string) error {
	if len(token) == 0 || len(token) > 8192 {
		return errSignupProofInvalid
	}
	claims := new(firebasePhoneClaims)
	_, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (any, error) {
		kid, ok := t.Header["kid"].(string)
		if !ok || kid == "" {
			return nil, errSignupProofInvalid
		}
		return v.key(ctx, kid)
	},
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithIssuer("https://securetoken.google.com/"+v.project),
		jwt.WithAudience(v.project),
		jwt.WithExpirationRequired(),
		jwt.WithIssuedAt(),
	)
	if errors.Is(err, errSignupProofUnavailable) {
		return errSignupProofUnavailable
	}
	now := time.Now()
	authenticatedAt := time.Unix(claims.AuthTime, 0)
	if err != nil || claims.Subject == "" || len(claims.Subject) > 128 ||
		claims.IssuedAt == nil || claims.Firebase.Provider != "phone" || claims.Phone != phone ||
		authenticatedAt.After(now) || now.Sub(authenticatedAt) > 10*time.Minute ||
		authenticatedAt.After(claims.IssuedAt.Time) {
		return errSignupProofInvalid
	}
	return nil
}

func (v *firebasePhoneVerifier) key(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if !time.Now().Before(v.expires) {
		if time.Now().Before(v.retryAfter) {
			return nil, errSignupProofUnavailable
		}
		if err := v.refreshKeys(ctx); err != nil {
			v.retryAfter = time.Now().Add(5 * time.Second)
			slog.Warn("Firebase signup signing keys unavailable", "error", err)
			return nil, errSignupProofUnavailable
		}
	}
	key := v.keys[kid]
	if key == nil {
		return nil, errSignupProofInvalid
	}
	return key, nil
}

func (v *firebasePhoneVerifier) refreshKeys(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, v.certURL, nil)
	if err != nil {
		return err
	}
	resp, err := v.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Firebase certificates returned HTTP %d", resp.StatusCode)
	}
	var certs map[string]string
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&certs); err != nil {
		return err
	}
	keys := make(map[string]*rsa.PublicKey, len(certs))
	for id, cert := range certs {
		block, _ := pem.Decode([]byte(cert))
		if block == nil {
			continue
		}
		parsed, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			continue
		}
		if key, ok := parsed.PublicKey.(*rsa.PublicKey); ok {
			keys[id] = key
		}
	}
	if len(keys) == 0 {
		return errors.New("Firebase returned no usable signing keys")
	}
	var maxAge int64
	for _, directive := range strings.Split(resp.Header.Get("Cache-Control"), ",") {
		name, value, found := strings.Cut(strings.TrimSpace(directive), "=")
		if found && name == "max-age" {
			maxAge, _ = strconv.ParseInt(value, 10, 32)
			break
		}
	}
	age, _ := strconv.ParseInt(resp.Header.Get("Age"), 10, 32)
	v.keys = keys
	v.expires = time.Now().Add(time.Duration(maxAge-age) * time.Second)
	return nil
}

func (s *Service) completeVerifiedSignup(ctx context.Context, in RegisterInput) (*AuthResponse, error) {
	passwordHash, err := auth.HashPassword(in.Password)
	if err != nil {
		return nil, err
	}
	tx, err := s.repo.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	u, err := s.repo.createVerified(ctx, tx, in, passwordHash)
	if err != nil {
		return nil, err
	}
	response, err := s.issueSession(ctx, tx, u)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return response, nil
}
