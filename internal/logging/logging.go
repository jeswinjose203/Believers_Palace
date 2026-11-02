// Package logging configures the application's structured logger (slog).
package logging

import (
	"log/slog"
	"os"
	"strings"
)

// Setup configures slog as the default logger. In production it emits JSON;
// otherwise it emits human-readable text. The level is controlled by the
// LOG_LEVEL env var (debug, info, warn, error); it defaults to info.
func Setup(appEnv string) {
	level := parseLevel(os.Getenv("LOG_LEVEL"))
	opts := &slog.HandlerOptions{Level: level}

	var handler slog.Handler
	if appEnv == "production" {
		handler = slog.NewJSONHandler(os.Stdout, opts)
	} else {
		handler = slog.NewTextHandler(os.Stdout, opts)
	}
	slog.SetDefault(slog.New(handler))
}

func parseLevel(s string) slog.Level {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
