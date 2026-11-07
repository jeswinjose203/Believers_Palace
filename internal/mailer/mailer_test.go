package mailer

import (
	"bytes"
	"context"
	"log"
	"strings"
	"testing"
)

// captureLog redirects the standard logger to a buffer for the duration of fn
// and returns everything written.
func captureLog(fn func()) string {
	var buf bytes.Buffer
	prevOut := log.Writer()
	prevFlags := log.Flags()
	log.SetOutput(&buf)
	log.SetFlags(0)
	defer func() {
		log.SetOutput(prevOut)
		log.SetFlags(prevFlags)
	}()
	fn()
	return buf.String()
}

func TestLogMailerSendEmailVerification(t *testing.T) {
	m := NewLogMailer("http://localhost:8080")

	out := captureLog(func() {
		if err := m.SendEmailVerification(context.Background(), "jane@example.com", "verify-tok-123"); err != nil {
			t.Fatalf("SendEmailVerification returned error: %v", err)
		}
	})

	if !strings.Contains(out, "jane@example.com") {
		t.Errorf("log output missing recipient; got: %q", out)
	}
	if !strings.Contains(out, "verify-tok-123") {
		t.Errorf("log output missing token; got: %q", out)
	}
	want := "http://localhost:8080/api/auth/verify-email?token=verify-tok-123"
	if !strings.Contains(out, want) {
		t.Errorf("log output missing verification link %q; got: %q", want, out)
	}
}

func TestLogMailerSendPasswordReset(t *testing.T) {
	m := NewLogMailer("http://localhost:8080")

	out := captureLog(func() {
		if err := m.SendPasswordReset(context.Background(), "jane@example.com", "reset-tok-456"); err != nil {
			t.Fatalf("SendPasswordReset returned error: %v", err)
		}
	})

	if !strings.Contains(out, "jane@example.com") {
		t.Errorf("log output missing recipient; got: %q", out)
	}
	if !strings.Contains(out, "reset-tok-456") {
		t.Errorf("log output missing token; got: %q", out)
	}
	want := "http://localhost:8080/api/auth/reset-password?token=reset-tok-456"
	if !strings.Contains(out, want) {
		t.Errorf("log output missing reset link %q; got: %q", want, out)
	}
}

// TestLinkBuildersEscapeTokens ensures tokens with URL-special characters are
// safely encoded into the emailed links.
func TestLinkBuildersEscapeTokens(t *testing.T) {
	const base = "https://api.example.com"
	token := "a b/c?d&e"

	if got, want := emailVerificationLink(base, token),
		"https://api.example.com/api/auth/verify-email?token=a+b%2Fc%3Fd%26e"; got != want {
		t.Errorf("emailVerificationLink = %q, want %q", got, want)
	}
	if got, want := passwordResetLink(base, token),
		"https://api.example.com/api/auth/reset-password?token=a+b%2Fc%3Fd%26e"; got != want {
		t.Errorf("passwordResetLink = %q, want %q", got, want)
	}
}
