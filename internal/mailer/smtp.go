package mailer

import (
	"context"
	"fmt"
	"net/smtp"
	"strings"
)

// SMTPConfig holds the settings for an SMTP mailer.
type SMTPConfig struct {
	Host     string // e.g. smtp.gmail.com
	Port     string // e.g. 587
	Username string // SMTP auth username (for Gmail, the full address)
	Password string // SMTP auth password (for Gmail, a 16-char App Password)
	From     string // From address, e.g. believerspalace400@gmail.com
	BaseURL  string // public base URL used to build links in emails
}

// SMTPMailer sends email over SMTP using STARTTLS (the standard library's
// smtp.SendMail negotiates STARTTLS when the server advertises it, as Gmail
// does on port 587).
type SMTPMailer struct {
	cfg  SMTPConfig
	auth smtp.Auth
}

// NewSMTPMailer creates an SMTPMailer from the given configuration.
func NewSMTPMailer(cfg SMTPConfig) *SMTPMailer {
	return &SMTPMailer{
		cfg:  cfg,
		auth: smtp.PlainAuth("", cfg.Username, cfg.Password, cfg.Host),
	}
}

// SendPasswordReset sends a password reset email.
func (m *SMTPMailer) SendPasswordReset(_ context.Context, email, resetToken string) error {
	link := passwordResetLink(m.cfg.BaseURL, resetToken)
	body := "You requested a password reset for your Believers Palace account.\r\n\r\n" +
		"Open this link to reset your password:\r\n\r\n" +
		link + "\r\n\r\n" +
		"Or use this token directly: " + resetToken + "\r\n\r\n" +
		"If you did not request this, you can ignore this email."
	return m.send(email, "Believers Palace - Password Reset", body)
}

// SendEmailVerification sends an email verification email.
func (m *SMTPMailer) SendEmailVerification(_ context.Context, email, verifyToken string) error {
	link := emailVerificationLink(m.cfg.BaseURL, verifyToken)
	body := "Welcome to Believers Palace!\r\n\r\n" +
		"Please verify your email address by opening this link:\r\n\r\n" +
		link + "\r\n\r\n" +
		"Or use this token directly: " + verifyToken + "\r\n\r\n" +
		"If you did not create an account, you can ignore this email."
	return m.send(email, "Believers Palace - Verify Your Email", body)
}

// send composes and delivers a plain-text message to a single recipient.
func (m *SMTPMailer) send(to, subject, body string) error {
	var msg strings.Builder
	msg.WriteString("From: " + m.cfg.From + "\r\n")
	msg.WriteString("To: " + to + "\r\n")
	msg.WriteString("Subject: " + subject + "\r\n")
	msg.WriteString("MIME-Version: 1.0\r\n")
	msg.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	msg.WriteString("\r\n")
	msg.WriteString(body)

	addr := m.cfg.Host + ":" + m.cfg.Port
	if err := smtp.SendMail(addr, m.auth, m.cfg.From, []string{to}, []byte(msg.String())); err != nil {
		return fmt.Errorf("send email: %w", err)
	}
	return nil
}
