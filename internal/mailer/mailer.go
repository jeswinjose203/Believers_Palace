// Package mailer defines a pluggable email-sending abstraction. The default
// implementation logs messages to the server log, which keeps the application
// dependency-free and fully testable in development. A production deployment
// can provide an SMTP/SES implementation behind the same Mailer interface.
package mailer

import (
	"context"
	"log"
	"net/url"
)

// emailVerificationLink builds the URL a user visits to verify their email.
func emailVerificationLink(baseURL, token string) string {
	return baseURL + "/api/auth/verify-email?token=" + url.QueryEscape(token)
}

// passwordResetLink builds the URL a user visits to reset their password.
func passwordResetLink(baseURL, token string) string {
	return baseURL + "/api/auth/reset-password?token=" + url.QueryEscape(token)
}

// Mailer sends transactional emails.
type Mailer interface {
	// SendPasswordReset delivers a password reset link/token to the given email.
	SendPasswordReset(ctx context.Context, email, resetToken string) error
	// SendEmailVerification delivers an email verification token to the given email.
	SendEmailVerification(ctx context.Context, email, verifyToken string) error
}

// LogMailer is a development Mailer that writes messages to the standard logger
// instead of sending real email. It never fails.
type LogMailer struct {
	baseURL string
}

// NewLogMailer returns a LogMailer. baseURL is used to build links shown in the
// logged messages (may be empty).
func NewLogMailer(baseURL string) *LogMailer {
	return &LogMailer{baseURL: baseURL}
}

// SendPasswordReset logs the password reset token and link for the recipient.
func (m *LogMailer) SendPasswordReset(_ context.Context, email, resetToken string) error {
	log.Printf("[mailer] password reset for %s: token=%s link=%s",
		email, resetToken, passwordResetLink(m.baseURL, resetToken))
	return nil
}

// SendEmailVerification logs the email verification token and link.
func (m *LogMailer) SendEmailVerification(_ context.Context, email, verifyToken string) error {
	log.Printf("[mailer] email verification for %s: token=%s link=%s",
		email, verifyToken, emailVerificationLink(m.baseURL, verifyToken))
	return nil
}
