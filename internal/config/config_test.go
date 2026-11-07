package config

import "testing"

func TestValidateRejectsSkipJWTInProduction(t *testing.T) {
	c := &Config{
		AppEnv:            "production",
		JWT:               JWTConfig{Secret: "a-real-secret"},
		SkipJWTValidation: true,
	}
	if err := c.validate(); err == nil {
		t.Error("validate() should reject SKIP_JWT_VALIDATION in production")
	}
}

func TestValidateAllowsSkipJWTInDevelopment(t *testing.T) {
	c := &Config{
		AppEnv:            "development",
		SkipJWTValidation: true,
	}
	if err := c.validate(); err != nil {
		t.Errorf("validate() should allow SKIP_JWT_VALIDATION in development, got %v", err)
	}
	// A dev default secret should have been filled in.
	if c.JWT.Secret == "" {
		t.Error("expected a development default JWT secret to be set")
	}
}

func TestValidateCORSDefaultsInDevelopment(t *testing.T) {
	c := &Config{AppEnv: "development"}
	if err := c.validate(); err != nil {
		t.Fatalf("validate() error = %v", err)
	}
	if len(c.CORSAllowedOrigins) != 1 || c.CORSAllowedOrigins[0] != "*" {
		t.Errorf("expected development CORS default [*], got %v", c.CORSAllowedOrigins)
	}
}

func TestValidateCORSRequiredInProduction(t *testing.T) {
	c := &Config{
		AppEnv: "production",
		JWT:    JWTConfig{Secret: "a-real-secret"},
	}
	if err := c.validate(); err == nil {
		t.Error("validate() should require CORS_ALLOWED_ORIGINS in production")
	}

	c = &Config{
		AppEnv:             "production",
		JWT:                JWTConfig{Secret: "a-real-secret"},
		CORSAllowedOrigins: []string{"https://app.example.com"},
	}
	if err := c.validate(); err != nil {
		t.Errorf("validate() should pass with explicit CORS origins in production, got %v", err)
	}
}

func TestValidateDisablesRateLimitUnderSkipJWT(t *testing.T) {
	c := &Config{
		AppEnv:            "development",
		SkipJWTValidation: true,
		RateLimit:         RateLimitConfig{Enabled: true, General: 100, Auth: 10},
	}
	if err := c.validate(); err != nil {
		t.Fatalf("validate() error = %v", err)
	}
	if c.RateLimit.Enabled {
		t.Error("rate limiting should be disabled when SKIP_JWT_VALIDATION is on")
	}
}

func TestValidateKeepsRateLimitWhenNotBypassing(t *testing.T) {
	c := &Config{
		AppEnv:    "development",
		RateLimit: RateLimitConfig{Enabled: true, General: 100, Auth: 10},
	}
	if err := c.validate(); err != nil {
		t.Fatalf("validate() error = %v", err)
	}
	if !c.RateLimit.Enabled {
		t.Error("rate limiting should remain enabled when not bypassing auth")
	}
}

func TestValidateSMTPRequiresSettings(t *testing.T) {
	// MAIL_PROVIDER=smtp without connection settings must fail.
	c := &Config{
		AppEnv: "development",
		Mail:   MailConfig{Provider: "smtp"},
	}
	if err := c.validate(); err == nil {
		t.Error("validate() should require SMTP settings when MAIL_PROVIDER=smtp")
	}

	// Fully configured SMTP passes.
	c = &Config{
		AppEnv: "development",
		Mail: MailConfig{
			Provider: "smtp",
			SMTPHost: "smtp.gmail.com",
			SMTPPort: "587",
			SMTPUser: "believers_palace",
			SMTPPass: "qrqh rfcn sjyl tway",
			From:     "believerspalace400gmail.com",
		},
	}
	if err := c.validate(); err != nil {
		t.Errorf("validate() should pass with full SMTP config, got %v", err)
	}

	// The default "log" provider needs no SMTP settings.
	c = &Config{AppEnv: "development", Mail: MailConfig{Provider: "log"}}
	if err := c.validate(); err != nil {
		t.Errorf("validate() should pass with log provider, got %v", err)
	}
}
