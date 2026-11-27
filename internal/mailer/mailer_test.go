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
		if err := m.SendEmailVerification(context.Background(), "jane@example.com", "012345"); err != nil {
			t.Fatalf("SendEmailVerification returned error: %v", err)
		}
	})

	if !strings.Contains(out, "jane@example.com") {
		t.Errorf("log output missing recipient; got: %q", out)
	}
	if !strings.Contains(out, "code=012345") {
		t.Errorf("log output missing code; got: %q", out)
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

func TestPasswordResetLinkEscapesToken(t *testing.T) {
	const base = "https://api.example.com"
	token := "a b/c?d&e"

	if got, want := passwordResetLink(base, token),
		"https://api.example.com/api/auth/reset-password?token=a+b%2Fc%3Fd%26e"; got != want {
		t.Errorf("passwordResetLink = %q, want %q", got, want)
	}
}
