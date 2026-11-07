package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

// Config holds all application configuration loaded from the environment.
type Config struct {
	AppEnv   string
	HTTPPort string
	// PublicBaseURL is the externally reachable base URL of the API, used to
	// build links in emails (e.g. https://api.example.com). No trailing slash.
	PublicBaseURL string
	DB            DBConfig
	JWT           JWTConfig
	Storage       StorageConfig
	Mail          MailConfig

	// SkipJWTValidation, when true, disables JWT authentication and injects a
	// synthetic identity. Intended ONLY for local API testing (e.g. Postman).
	// It is refused in production.
	SkipJWTValidation bool

	// CORSAllowedOrigins is the list of origins permitted by CORS. In
	// development it defaults to ["*"]; in production it must be set explicitly.
	CORSAllowedOrigins []string

	// RateLimit holds request rate-limiting settings.
	RateLimit RateLimitConfig
}

// RateLimitConfig holds per-IP rate-limiting settings (requests per minute).
type RateLimitConfig struct {
	// Enabled toggles rate limiting. Defaults to true; forced off when
	// SkipJWTValidation is on so local testing is not throttled.
	Enabled bool
	// General is the per-IP requests/minute for most endpoints.
	General int
	// Auth is the stricter per-IP requests/minute for /auth/* endpoints.
	Auth int
}

// MailConfig holds email delivery settings.
type MailConfig struct {
	// Provider selects the mailer implementation: "log" (default; writes to the
	// server log) or "smtp" (sends real email).
	Provider string
	SMTPHost string
	SMTPPort string
	SMTPUser string
	SMTPPass string
	From     string
}

// DBConfig holds PostgreSQL connection settings.
type DBConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	Name     string
	SSLMode  string
}

// JWTConfig holds JWT signing settings.
type JWTConfig struct {
	Secret string
	// TTL is the access-token lifetime.
	TTL time.Duration
	// RefreshTTL is the refresh-token lifetime.
	RefreshTTL time.Duration
	// ResetTTL is the password-reset-token lifetime.
	ResetTTL time.Duration
	Issuer   string
}

// StorageConfig holds file storage settings (certificate uploads).
type StorageConfig struct {
	// Dir is the base directory where uploaded files are stored.
	Dir string
	// MaxUploadBytes is the maximum allowed size for an uploaded file.
	MaxUploadBytes int64
	// MediaDir is the base directory where uploaded images are stored.
	MediaDir string
	// MaxImageBytes is the maximum allowed size for an uploaded image.
	MaxImageBytes int64
}

// DSN returns a PostgreSQL connection string.
func (c DBConfig) DSN() string {
	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, c.Password, c.Name, c.SSLMode,
	)
}

// Load reads configuration from a .env file (if present) and the environment.
// Real environment variables take precedence over values in the .env file.
func Load() (*Config, error) {
	// Ignore error: .env is optional (e.g. in production real env vars are used).
	_ = godotenv.Load()

	cfg := &Config{
		AppEnv:        getEnv("APP_ENV", "development"),
		HTTPPort:      getEnv("HTTP_PORT", "8080"),
		PublicBaseURL: strings.TrimRight(getEnv("PUBLIC_BASE_URL", "http://localhost:8080"), "/"),
		DB: DBConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", "postgres"),
			Name:     getEnv("DB_NAME", "believers_palace"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		JWT: JWTConfig{
			Secret:     getEnv("JWT_SECRET", ""),
			TTL:        getEnvDuration("ACCESS_TOKEN_TTL", getEnvDuration("JWT_TTL", 15*time.Minute)),
			RefreshTTL: getEnvDuration("REFRESH_TOKEN_TTL", 30*24*time.Hour),
			ResetTTL:   getEnvDuration("RESET_TOKEN_TTL", time.Hour),
			Issuer:     getEnv("JWT_ISSUER", "believers_palace"),
		},
		Storage: StorageConfig{
			Dir:            getEnv("STORAGE_DIR", "./storage/certificates"),
			MaxUploadBytes: getEnvInt64("MAX_UPLOAD_BYTES", 10*1024*1024), // 10 MiB
			MediaDir:       getEnv("MEDIA_DIR", "./storage/media"),
			MaxImageBytes:  getEnvInt64("MAX_IMAGE_BYTES", 5*1024*1024), // 5 MiB
		},
		Mail: MailConfig{
			Provider: getEnv("MAIL_PROVIDER", "log"),
			SMTPHost: getEnv("SMTP_HOST", ""),
			SMTPPort: getEnv("SMTP_PORT", "587"),
			SMTPUser: getEnv("SMTP_USERNAME", ""),
			SMTPPass: getEnv("SMTP_PASSWORD", ""),
			From:     getEnv("MAIL_FROM", ""),
		},
		SkipJWTValidation:  getEnvBool("SKIP_JWT_VALIDATION", false),
		CORSAllowedOrigins: getEnvList("CORS_ALLOWED_ORIGINS", nil),
		RateLimit: RateLimitConfig{
			Enabled: getEnvBool("RATE_LIMIT_ENABLED", true),
			General: int(getEnvInt64("RATE_LIMIT_GENERAL_PER_MIN", 120)),
			Auth:    int(getEnvInt64("RATE_LIMIT_AUTH_PER_MIN", 10)),
		},
	}

	if err := cfg.validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

func (c *Config) validate() error {
	if c.JWT.Secret == "" {
		// In development we allow a weak default so the app boots, but warn.
		if c.AppEnv == "production" {
			return fmt.Errorf("JWT_SECRET is required in production")
		}
		c.JWT.Secret = "dev-insecure-secret-change-me"
	}
	// Never allow authentication to be bypassed in production.
	if c.SkipJWTValidation && c.AppEnv == "production" {
		return fmt.Errorf("SKIP_JWT_VALIDATION must not be enabled in production")
	}
	// Local testing bypass also disables rate limiting to avoid throttling.
	if c.SkipJWTValidation {
		c.RateLimit.Enabled = false
	}

	// Resolve CORS allowed origins. In production the origins must be set
	// explicitly; defaulting to a wildcard would be unsafe.
	if len(c.CORSAllowedOrigins) == 0 {
		if c.AppEnv == "production" {
			return fmt.Errorf("CORS_ALLOWED_ORIGINS is required in production")
		}
		c.CORSAllowedOrigins = []string{"*"}
	}

	// When SMTP email is selected, the connection and sender settings are
	// required.
	if c.Mail.Provider == "smtp" {
		missing := []string{}
		if c.Mail.SMTPHost == "" {
			missing = append(missing, "SMTP_HOST")
		}
		if c.Mail.SMTPUser == "" {
			missing = append(missing, "SMTP_USERNAME")
		}
		if c.Mail.SMTPPass == "" {
			missing = append(missing, "SMTP_PASSWORD")
		}
		if c.Mail.From == "" {
			missing = append(missing, "MAIL_FROM")
		}
		if len(missing) > 0 {
			return fmt.Errorf("MAIL_PROVIDER=smtp requires: %s", strings.Join(missing, ", "))
		}
	}
	return nil
}

func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func getEnvBool(key string, fallback bool) bool {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			return b
		}
	}
	return fallback
}

// getEnvList reads a comma-separated environment variable into a slice,
// trimming whitespace and dropping empty entries.
func getEnvList(key string, fallback []string) []string {
	v, ok := os.LookupEnv(key)
	if !ok || v == "" {
		return fallback
	}
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if s := strings.TrimSpace(p); s != "" {
			out = append(out, s)
		}
	}
	if len(out) == 0 {
		return fallback
	}
	return out
}

func getEnvInt64(key string, fallback int64) int64 {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return fallback
}

func getEnvDuration(key string, fallback time.Duration) time.Duration {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return fallback
}
