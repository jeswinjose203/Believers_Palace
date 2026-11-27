package mailer

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/smtp"
	"strings"
	"time"
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

// SMTPMailer sends email over SMTP with a bounded, cancelable connection.
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
func (m *SMTPMailer) SendPasswordReset(ctx context.Context, email, resetToken string) error {
	link := passwordResetLink(m.cfg.BaseURL, resetToken)
	body := "You requested a password reset for your Believers Palace account.\r\n\r\n" +
		"Open this link to reset your password:\r\n\r\n" +
		link + "\r\n\r\n" +
		"Or use this token directly: " + resetToken + "\r\n\r\n" +
		"If you did not request this, you can ignore this email."
	return m.send(ctx, email, "Believers Palace - Password Reset", body)
}

// SendEmailVerification sends an email verification email.
func (m *SMTPMailer) SendEmailVerification(ctx context.Context, email, code string) error {
	body := "Your Believers Palace verification code is " + code + ".\r\n\r\n" +
		"Enter this code in the app within 10 minutes to verify your email.\r\n\r\n" +
		"If you did not request this code, you can ignore this email."
	return m.send(ctx, email, "Believers Palace - Verify Your Email", body)
}

// send composes and delivers a plain-text message to a single recipient.
func (m *SMTPMailer) send(ctx context.Context, to, subject, body string) error {
	if strings.ContainsAny(to, "\r\n") || strings.ContainsAny(m.cfg.From, "\r\n") {
		return fmt.Errorf("invalid email envelope address")
	}
	var msg strings.Builder
	msg.WriteString("From: " + m.cfg.From + "\r\n")
	msg.WriteString("To: " + to + "\r\n")
	msg.WriteString("Subject: " + subject + "\r\n")
	msg.WriteString("MIME-Version: 1.0\r\n")
	msg.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	msg.WriteString("\r\n")
	msg.WriteString(body)

	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	var dialer net.Dialer
	conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(m.cfg.Host, m.cfg.Port))
	if err != nil {
		return fmt.Errorf("connect to SMTP: %w", err)
	}
	defer conn.Close()
	stop := context.AfterFunc(ctx, func() { _ = conn.Close() })
	defer stop()
	deadline, _ := ctx.Deadline()
	if err := conn.SetDeadline(deadline); err != nil {
		return err
	}
	client, err := smtp.NewClient(conn, m.cfg.Host)
	if err != nil {
		return err
	}
	defer client.Close()
	if supported, _ := client.Extension("STARTTLS"); supported {
		if err := client.StartTLS(&tls.Config{ServerName: m.cfg.Host, MinVersion: tls.VersionTLS12}); err != nil {
			return err
		}
	}
	if err := client.Auth(m.auth); err != nil {
		return err
	}
	if err := client.Mail(m.cfg.From); err != nil {
		return err
	}
	if err := client.Rcpt(to); err != nil {
		return err
	}
	data, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := data.Write([]byte(msg.String())); err != nil {
		return err
	}
	if err := data.Close(); err != nil {
		return err
	}
	return client.Quit()
}
