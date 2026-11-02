package user

import (
	"context"
	"testing"

	"believers_palace/internal/mailer"
)

// newValidationOnlyService builds a Service whose methods under test return
// before touching the (nil) repository. Using a nil repo guarantees the test
// fails loudly if a code path unexpectedly reaches the database.
func newValidationOnlyService() *Service {
	return &Service{mailer: mailer.NewLogMailer("http://localhost:8080")}
}

func TestRefreshRequiresToken(t *testing.T) {
	s := newValidationOnlyService()
	if _, err := s.Refresh(context.Background(), RefreshInput{RefreshToken: ""}); err == nil {
		t.Error("Refresh with empty token should return a validation error")
	}
}

func TestLogoutRequiresToken(t *testing.T) {
	s := newValidationOnlyService()
	if err := s.Logout(context.Background(), LogoutInput{RefreshToken: ""}); err == nil {
		t.Error("Logout with empty token should return a validation error")
	}
}

func TestResetPasswordValidation(t *testing.T) {
	s := newValidationOnlyService()

	if err := s.ResetPassword(context.Background(), ResetPasswordInput{Token: "", NewPassword: "longenough"}); err == nil {
		t.Error("ResetPassword with empty token should fail validation")
	}
	if err := s.ResetPassword(context.Background(), ResetPasswordInput{Token: "tok", NewPassword: "short"}); err == nil {
		t.Error("ResetPassword with a short password should fail validation")
	}
}

func TestForgotPasswordInvalidEmailIsNoOp(t *testing.T) {
	s := newValidationOnlyService()
	// Invalid email must return nil (no enumeration) without touching the repo.
	if err := s.ForgotPassword(context.Background(), ForgotPasswordInput{Email: "not-an-email"}); err != nil {
		t.Errorf("ForgotPassword with invalid email should be a no-op success, got %v", err)
	}
}

func TestVerifyEmailRequiresToken(t *testing.T) {
	s := newValidationOnlyService()
	if err := s.VerifyEmail(context.Background(), VerifyEmailInput{Token: ""}); err == nil {
		t.Error("VerifyEmail with empty token should fail validation")
	}
}

func TestResendVerificationInvalidEmailIsNoOp(t *testing.T) {
	s := newValidationOnlyService()
	// Invalid email must return nil without touching the repo (no enumeration).
	if err := s.ResendVerification(context.Background(), ResendVerificationInput{Email: "not-an-email"}); err != nil {
		t.Errorf("ResendVerification with invalid email should be a no-op success, got %v", err)
	}
}
