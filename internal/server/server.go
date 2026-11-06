package server

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/go-chi/httprate"
	"github.com/jackc/pgx/v5/pgxpool"

	"believers_palace/internal/announcement"
	"believers_palace/internal/auth"
	"believers_palace/internal/booking"
	"believers_palace/internal/cemetery"
	"believers_palace/internal/certificate"
	"believers_palace/internal/chat"
	"believers_palace/internal/church"
	"believers_palace/internal/config"
	"believers_palace/internal/event"
	"believers_palace/internal/hall"
	"believers_palace/internal/httpx"
	"believers_palace/internal/mailer"
	"believers_palace/internal/media"
	"believers_palace/internal/user"
)

// New builds the application HTTP handler with all routes and middleware.
func New(cfg *config.Config, pool *pgxpool.Pool) (http.Handler, error) {
	r := chi.NewRouter()

	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(requestLogger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(securityHeaders)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   cfg.CORSAllowedOrigins,
		AllowedMethods:   []string{http.MethodGet, http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete, http.MethodOptions},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Debug-User-Id", "X-Debug-Role", "X-Debug-Church-Id"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: false,
		MaxAge:           300,
	}))
	if cfg.RateLimit.Enabled {
		// General per-IP limit across all endpoints.
		r.Use(httprate.LimitByIP(cfg.RateLimit.General, time.Minute))
	}

	tm := auth.NewTokenManager(cfg.JWT.Secret, cfg.JWT.TTL, cfg.JWT.Issuer)

	// Select the authentication middleware. When SKIP_JWT_VALIDATION is set
	// (never allowed in production; enforced in config), requests bypass JWT
	// validation and receive a synthetic identity for local API testing.
	authMiddleware := auth.Middleware(tm)
	if cfg.SkipJWTValidation {
		slog.Warn("SKIP_JWT_VALIDATION is enabled - authentication is BYPASSED; do not use outside local testing")
		authMiddleware = auth.DebugMiddleware()
	}

	// Dependencies.
	var mail mailer.Mailer = mailer.NewLogMailer(cfg.PublicBaseURL)
	if cfg.Mail.Provider == "smtp" {
		mail = mailer.NewSMTPMailer(mailer.SMTPConfig{
			Host:     cfg.Mail.SMTPHost,
			Port:     cfg.Mail.SMTPPort,
			Username: cfg.Mail.SMTPUser,
			Password: cfg.Mail.SMTPPass,
			From:     cfg.Mail.From,
			BaseURL:  cfg.PublicBaseURL,
		})
		slog.Info("mailer: using SMTP", slog.String("host", cfg.Mail.SMTPHost), slog.String("from", cfg.Mail.From))
	}
	userRepo := user.NewRepository(pool)
	userSvc := user.NewService(userRepo, tm, mail, cfg.JWT.RefreshTTL, cfg.JWT.ResetTTL)
	userSvc.SetLogTokens(cfg.AppEnv != "production") // log tokens in dev/test, not in prod
	userHandler := user.NewHandler(userSvc, tm)

	churchRepo := church.NewRepository(pool)
	churchSvc := church.NewService(churchRepo)
	churchHandler := church.NewHandler(churchSvc)

	announcementRepo := announcement.NewRepository(pool)
	announcementSvc := announcement.NewService(announcementRepo, churchRepo)
	announcementHandler := announcement.NewHandler(announcementSvc)

	hallRepo := hall.NewRepository(pool)
	hallSvc := hall.NewService(hallRepo, churchRepo)
	hallHandler := hall.NewHandler(hallSvc)

	bookingRepo := booking.NewRepository(pool)
	bookingSvc := booking.NewService(bookingRepo, hallRepo)
	bookingHandler := booking.NewHandler(bookingSvc)

	eventRepo := event.NewRepository(pool)
	eventSvc := event.NewService(eventRepo, churchRepo)
	eventHandler := event.NewHandler(eventSvc)

	chatRepo := chat.NewRepository(pool)
	chatSvc := chat.NewService(
		chatRepo,
		eventChurchResolver{eventRepo},
		userDisplayResolver{userRepo},
		eventRepo, // satisfies chat's registrationChecker (IsRegistered)
	)
	chatHandler := chat.NewHandler(chatSvc)

	cemeteryRepo := cemetery.NewRepository(pool)
	cemeterySvc := cemetery.NewService(cemeteryRepo, churchRepo)
	cemeteryHandler := cemetery.NewHandler(cemeterySvc)

	certStorage, err := certificate.NewStorage(cfg.Storage.Dir)
	if err != nil {
		return nil, err
	}
	certificateRepo := certificate.NewRepository(pool)
	certificateSvc := certificate.NewService(certificateRepo, certStorage, userRepo, cfg.Storage.MaxUploadBytes)
	certificateHandler := certificate.NewHandler(certificateSvc)

	mediaStorage, err := media.NewStorage(cfg.Storage.MediaDir)
	if err != nil {
		return nil, err
	}
	mediaSvc := media.NewService(mediaStorage, cfg.PublicBaseURL, cfg.Storage.MaxImageBytes)
	mediaHandler := media.NewHandler(mediaSvc)

	// Health check.
	r.Get("/health", func(w http.ResponseWriter, req *http.Request) {
		if err := pool.Ping(req.Context()); err != nil {
			httpx.Error(w, http.StatusServiceUnavailable, "database unavailable")
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// API routes (spec base path is /api).
	r.Route("/api", func(api chi.Router) {
		// Public authentication routes, with a stricter per-IP rate limit to
		// resist brute-force login and email-bomb abuse of password reset and
		// verification resend.
		api.Group(func(authGroup chi.Router) {
			if cfg.RateLimit.Enabled {
				authGroup.Use(httprate.LimitByIP(cfg.RateLimit.Auth, time.Minute))
			}
			authGroup.Mount("/auth", userHandler.AuthRoutes())
		})

		// Media: public image download (GET /media/{key}) plus authenticated
		// image upload (POST /media/upload). Mounted once; the router applies
		// auth only to the upload route. Images are referenced by URL in
		// resource fields (logos, profile pictures, event/hall images) and must
		// be loadable without an Authorization header.
		api.Mount("/media", mediaHandler.Routes(authMiddleware))

		// Authenticated routes.
		api.Group(func(protected chi.Router) {
			protected.Use(authMiddleware)
			protected.Mount("/users", userHandler.UserRoutes())
			protected.Mount("/users/{userId}/certificates", certificateHandler.UserRoutes())
			protected.Mount("/churches", churchHandler.Routes())

			// Church-nested sub-resources.
			protected.Mount("/churches/{churchId}/announcements", announcementHandler.ChurchRoutes())
			protected.Mount("/churches/{churchId}/halls", hallHandler.ChurchRoutes())
			protected.Mount("/churches/{churchId}/bookings", bookingHandler.ChurchRoutes())
			protected.Mount("/churches/{churchId}/events", eventHandler.ChurchRoutes())
			protected.Mount("/churches/{churchId}/cemetery-plots", cemeteryHandler.PlotChurchRoutes())
			protected.Mount("/churches/{churchId}/cemetery-service-requests", cemeteryHandler.RequestChurchRoutes())

			// Top-level sub-resource routes.
			protected.Mount("/announcements", announcementHandler.Routes())
			protected.Mount("/halls", hallHandler.Routes())
			protected.Mount("/bookings", bookingHandler.Routes())
			protected.Mount("/events", eventHandler.RoutesWith(chatHandler.EventRoutes()))
			protected.Mount("/cemetery-service-requests", cemeteryHandler.RequestRoutes())
			protected.Mount("/cemetery-plots", cemeteryHandler.PlotRoutes())
			protected.Mount("/certificates", certificateHandler.Routes())
		})
	})

	return r, nil
}

// eventChurchResolver adapts the event repository to the chat package's
// eventResolver interface.
type eventChurchResolver struct {
	repo *event.Repository
}

func (a eventChurchResolver) ChurchIDOfEvent(ctx context.Context, eventID string) (string, bool, error) {
	ev, err := a.repo.GetByID(ctx, eventID)
	if errors.Is(err, event.ErrNotFound) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return ev.ChurchID, true, nil
}

// userDisplayResolver adapts the user repository to the chat package's
// userResolver interface.
type userDisplayResolver struct {
	repo *user.Repository
}

func (a userDisplayResolver) DisplayOf(ctx context.Context, userID string) (string, *string, bool, error) {
	u, err := a.repo.GetByID(ctx, userID)
	if errors.Is(err, user.ErrNotFound) {
		return "", nil, false, nil
	}
	if err != nil {
		return "", nil, false, err
	}
	return u.Name, u.ProfilePic, true, nil
}
