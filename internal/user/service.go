package user

import (
	"context"
	"errors"
	"log"
	"log/slog"
	"net/mail"
	"strings"
	"time"

	"believers_palace/internal/auth"
	"believers_palace/internal/mailer"
)

// ErrInvalidCredentials is returned when login fails.
var ErrInvalidCredentials = errors.New("invalid email or password")

// ValidationError describes a request validation failure.
type ValidationError struct {
	Message string
}

func (e *ValidationError) Error() string { return e.Message }

func invalid(msg string) error { return &ValidationError{Message: msg} }

// Service holds user business logic.
type Service struct {
	repo       *Repository
	tokens     *auth.TokenManager
	mailer     mailer.Mailer
	refreshTTL time.Duration
	resetTTL   time.Duration
	verifyTTL  time.Duration
	logTokens bool
}

func(s *Service) SetLogTokens(v bool) {
	s.logTokens = v
}

// NewService creates a user service.
func NewService(repo *Repository, tokens *auth.TokenManager, m mailer.Mailer, refreshTTL, resetTTL time.Duration) *Service {
	return &Service{
		repo:       repo,
		tokens:     tokens,
		mailer:     m,
		refreshTTL: refreshTTL,
		resetTTL:   resetTTL,
		verifyTTL:  24 * time.Hour,
	}
}

// Register validates input, creates a user with the default role, and issues a token.
func (s *Service) Register(ctx context.Context, in RegisterInput) (*AuthResponse, error) {
	in.Name = strings.TrimSpace(in.Name)
	in.Email = strings.TrimSpace(in.Email)

	if in.Name == "" {
		return nil, invalid("name is required")
	}
	if !validEmail(in.Email) {
		return nil, invalid("a valid email is required")
	}
	if len(in.Password) < 8 {
		return nil, invalid("password must be at least 8 characters")
	}

	hash, err := auth.HashPassword(in.Password)
	if err != nil {
		return nil, err
	}

	u, err := s.repo.Create(ctx, in, hash, auth.RoleUser)
	if err != nil {
		return nil, err
	}

	// Send an email verification token (soft verification: the account is
	// usable immediately, emailVerified becomes true once verified). A failure
	// to send must not fail registration.
	if err := s.issueEmailVerification(ctx, u); err != nil {
		log.Printf("register: failed to send verification email to %s: %v", u.Email, err)
	}

	return s.authResponse(ctx, u)
}

// issueEmailVerification creates a verification token and sends it.
func (s *Service) issueEmailVerification(ctx context.Context, u *User) error {
	raw, hash, err := auth.GenerateOpaqueToken()
	if err != nil {
		return err
	}
	if err := s.repo.StoreEmailVerificationToken(ctx, u.ID, hash, time.Now().Add(s.verifyTTL)); err != nil {
		return err
	}
	if s.logTokens{
		slog.Info("email verification token issued",
			slog.String("email", u.Email),
			slog.String("token", raw),
		)
	}
	return s.mailer.SendEmailVerification(ctx, u.Email, raw)
}

// VerifyEmail consumes a verification token and marks the user's email verified.
func (s *Service) VerifyEmail(ctx context.Context, in VerifyEmailInput) error {
	if strings.TrimSpace(in.Token) == "" {
		return invalid("token is required")
	}
	userID, err := s.repo.ConsumeEmailVerificationToken(ctx, auth.HashToken(in.Token))
	if err != nil {
		return err
	}
	return s.repo.MarkEmailVerified(ctx, userID)
}

// ResendVerification re-issues a verification token. To avoid account
// enumeration it always succeeds regardless of whether the email exists or is
// already verified.
func (s *Service) ResendVerification(ctx context.Context, in ResendVerificationInput) error {
	email := strings.TrimSpace(in.Email)
	if !validEmail(email) {
		return nil
	}
	u, err := s.repo.GetByEmail(ctx, email)
	if errors.Is(err, ErrNotFound) {
		return nil
	}
	if err != nil {
		return err
	}
	if u.EmailVerified {
		return nil
	}
	return s.issueEmailVerification(ctx, u)
}

// Login verifies credentials and issues a token.
func (s *Service) Login(ctx context.Context, in LoginInput) (*AuthResponse, error) {
	if !validEmail(strings.TrimSpace(in.Email)) || in.Password == "" {
		return nil, invalid("email and password are required")
	}

	u, err := s.repo.GetByEmail(ctx, in.Email)
	if errors.Is(err, ErrNotFound) {
		return nil, ErrInvalidCredentials
	}
	if err != nil {
		return nil, err
	}

	if !auth.CheckPassword(u.PasswordHash, in.Password) {
		return nil, ErrInvalidCredentials
	}

	return s.authResponse(ctx, u)
}

// GetByID returns a user by ID.
func (s *Service) GetByID(ctx context.Context, id string) (*User, error) {
	return s.repo.GetByID(ctx, id)
}

// List returns a filtered, paginated list of users with the total count.
func (s *Service) List(ctx context.Context, f ListFilter) ([]User, int, error) {
	if f.Role != "" && !auth.ValidRole(f.Role) {
		return nil, 0, invalid("invalid role filter")
	}
	return s.repo.List(ctx, f)
}

// UpdateProfile updates the current user's profile.
func (s *Service) UpdateProfile(ctx context.Context, id string, in ProfileUpdateInput) (*User, error) {
	if in.Name != nil && strings.TrimSpace(*in.Name) == "" {
		return nil, invalid("name cannot be empty")
	}
	return s.repo.UpdateProfile(ctx, id, in)
}

// UpdateRole changes a user's role (super_admin action).
func (s *Service) UpdateRole(ctx context.Context, id string, role auth.Role) (*User, error) {
	if !auth.ValidRole(role) {
		return nil, invalid("invalid role")
	}
	return s.repo.UpdateRole(ctx, id, role)
}

// Refresh rotates a refresh token: it validates and revokes the presented
// token, then issues a new access + refresh pair. Reuse of a revoked or
// expired token yields ErrTokenInvalid.
func (s *Service) Refresh(ctx context.Context, in RefreshInput) (*AuthResponse, error) {
	if strings.TrimSpace(in.RefreshToken) == "" {
		return nil, invalid("refreshToken is required")
	}
	userID, err := s.repo.ConsumeRefreshToken(ctx, auth.HashToken(in.RefreshToken))
	if err != nil {
		return nil, err
	}
	u, err := s.repo.GetByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	return s.authResponse(ctx, u)
}

// Logout revokes a single refresh token (one session). It is idempotent.
func (s *Service) Logout(ctx context.Context, in LogoutInput) error {
	if strings.TrimSpace(in.RefreshToken) == "" {
		return invalid("refreshToken is required")
	}
	return s.repo.RevokeRefreshToken(ctx, auth.HashToken(in.RefreshToken))
}

// LogoutAll revokes every active refresh token for a user (log out everywhere).
func (s *Service) LogoutAll(ctx context.Context, userID string) error {
	return s.repo.RevokeAllRefreshTokens(ctx, userID)
}

// ForgotPassword issues a single-use reset token and delivers it via the
// mailer. To avoid account enumeration it never reveals whether the email
// exists: callers always receive a success response.
func (s *Service) ForgotPassword(ctx context.Context, in ForgotPasswordInput) error {
	email := strings.TrimSpace(in.Email)
	if !validEmail(email) {
		// Do not leak validity; treat as a no-op success.
		return nil
	}

	u, err := s.repo.GetByEmail(ctx, email)
	if errors.Is(err, ErrNotFound) {
		return nil
	}
	if err != nil {
		return err
	}

	raw, hash, err := auth.GenerateOpaqueToken()
	if err != nil {
		return err
	}
	if err := s.repo.StorePasswordResetToken(ctx, u.ID, hash, time.Now().Add(s.resetTTL)); err != nil {
		return err
	}
	if s.logTokens{
		slog.Info("password reset token issued",
			slog.String("email", u.Email),
			slog.String("token", raw),
		)
	}
	return s.mailer.SendPasswordReset(ctx, u.Email, raw)
}

// ResetPassword validates a reset token, sets the new password, and revokes all
// of the user's refresh tokens (forcing re-login everywhere).
func (s *Service) ResetPassword(ctx context.Context, in ResetPasswordInput) error {
	if strings.TrimSpace(in.Token) == "" {
		return invalid("token is required")
	}
	if len(in.NewPassword) < 8 {
		return invalid("password must be at least 8 characters")
	}

	userID, err := s.repo.ConsumePasswordResetToken(ctx, auth.HashToken(in.Token))
	if err != nil {
		return err
	}

	hash, err := auth.HashPassword(in.NewPassword)
	if err != nil {
		return err
	}
	if err := s.repo.UpdatePassword(ctx, userID, hash); err != nil {
		return err
	}
	// Invalidate existing sessions after a password change.
	return s.repo.RevokeAllRefreshTokens(ctx, userID)
}

func (s *Service) authResponse(ctx context.Context, u *User) (*AuthResponse, error) {
	churchID := ""
	if u.ChurchID != nil {
		churchID = *u.ChurchID
	}
	accessToken, err := s.tokens.Generate(u.ID, u.Role, churchID)
	if err != nil {
		return nil, err
	}

	rawRefresh, refreshHash, err := auth.GenerateOpaqueToken()
	if err != nil {
		return nil, err
	}
	if err := s.repo.StoreRefreshToken(ctx, u.ID, refreshHash, time.Now().Add(s.refreshTTL)); err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: rawRefresh,
		ExpiresIn:    int(s.tokens.AccessTTL().Seconds()),
		Token:        accessToken, // backward-compatible alias
		User:         u,
	}, nil
}

func validEmail(email string) bool {
	if email == "" {
		return false
	}
	_, err := mail.ParseAddress(email)
	return err == nil
}
