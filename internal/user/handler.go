package user

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

// Handler handles authentication and user HTTP requests.
type Handler struct {
	svc *Service
	tm  *auth.TokenManager
}

// NewHandler creates a user handler.
func NewHandler(svc *Service, tm *auth.TokenManager) *Handler {
	return &Handler{svc: svc, tm: tm}
}

// AuthRoutes returns the public authentication routes (no auth required).
func (h *Handler) AuthRoutes() chi.Router {
	r := chi.NewRouter()
	r.Post("/register", h.register)
	r.Post("/login", h.login)
	r.Post("/refresh", h.refresh)
	r.Post("/logout", h.logout)
	r.Post("/forgot-password", h.forgotPassword)
	r.Post("/reset-password", h.resetPassword)
	r.Post("/verify-email", h.verifyEmail)
	r.Get("/verify-email", h.verifyEmailPage)
	r.Post("/resend-verification", h.resendVerification)
	return r
}

// UserRoutes returns the authenticated user routes.
func (h *Handler) UserRoutes() chi.Router {
	r := chi.NewRouter()
	// List users: church_admin or super_admin only.
	r.With(auth.RequireRole(auth.RoleChurchAdmin, auth.RoleSuperAdmin)).Get("/", h.list)
	r.Get("/me", h.getMe)
	r.Put("/me", h.updateMe)
	r.Post("/logout-all", h.logoutAll)
	// Update role: super_admin only.
	r.With(auth.RequireRole(auth.RoleSuperAdmin)).Patch("/{userId}/role", h.updateRole)
	return r
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var in RegisterInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	resp, err := h.svc.Register(r.Context(), in)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, resp)
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var in LoginInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	resp, err := h.svc.Login(r.Context(), in)
	if errors.Is(err, ErrInvalidCredentials) {
		httpx.ErrorCode(w, http.StatusUnauthorized, "invalid email or password", "unauthorized")
		return
	}
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, resp)
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	var in RefreshInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	resp, err := h.svc.Refresh(r.Context(), in)
	if errors.Is(err, ErrTokenInvalid) {
		httpx.ErrorCode(w, http.StatusUnauthorized, "invalid or expired refresh token", "unauthorized")
		return
	}
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, resp)
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	var in LogoutInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	if err := h.svc.Logout(r.Context(), in); err != nil {
		h.writeServiceError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) logoutAll(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	if err := h.svc.LogoutAll(r.Context(), id.UserID); err != nil {
		h.writeServiceError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) forgotPassword(w http.ResponseWriter, r *http.Request) {
	var in ForgotPasswordInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	// Always succeed to avoid account enumeration.
	if err := h.svc.ForgotPassword(r.Context(), in); err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{
		"message": "if the email is registered, a reset link has been sent",
	})
}

func (h *Handler) resetPassword(w http.ResponseWriter, r *http.Request) {
	var in ResetPasswordInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	err := h.svc.ResetPassword(r.Context(), in)
	if errors.Is(err, ErrTokenInvalid) {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid or expired reset token", "bad_request")
		return
	}
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"message": "password updated"})
}

func (h *Handler) verifyEmail(w http.ResponseWriter, r *http.Request) {
	var in VerifyEmailInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	err := h.svc.VerifyEmail(r.Context(), in)
	if errors.Is(err, ErrTokenInvalid) {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid or expired verification token", "bad_request")
		return
	}
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"message": "email verified"})
}

// verifyEmailPage handles the GET link embedded in verification emails and
// returns a minimal HTML confirmation page (so it works from any email client).
func (h *Handler) verifyEmailPage(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	err := h.svc.VerifyEmail(r.Context(), VerifyEmailInput{Token: token})

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(verifyHTML(false)))
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(verifyHTML(true)))
}

func verifyHTML(ok bool) string {
	title, msg := "Email verified", "Your email address has been verified. You can return to the app."
	if !ok {
		title, msg = "Verification failed", "This verification link is invalid or has expired. Request a new one from the app."
	}
	return `<!doctype html><html><head><meta charset="utf-8">` +
		`<meta name="viewport" content="width=device-width, initial-scale=1">` +
		`<title>` + title + `</title></head>` +
		`<body style="font-family:sans-serif;max-width:32rem;margin:4rem auto;padding:0 1rem;text-align:center">` +
		`<h1>` + title + `</h1><p>` + msg + `</p></body></html>`
}

func (h *Handler) resendVerification(w http.ResponseWriter, r *http.Request) {
	var in ResendVerificationInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	// Always succeed to avoid account enumeration.
	if err := h.svc.ResendVerification(r.Context(), in); err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{
		"message": "if the email is registered and unverified, a verification link has been sent",
	})
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	pp := httpx.ParsePageParams(r)

	f := ListFilter{
		ChurchID: r.URL.Query().Get("churchId"),
		Role:     auth.Role(r.URL.Query().Get("role")),
		Limit:    pp.Limit,
		Offset:   pp.Offset,
	}

	// A church_admin may only list users within their own church.
	if id.Role == auth.RoleChurchAdmin {
		f.ChurchID = id.ChurchID
	}

	users, total, err := h.svc.List(r.Context(), f)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.Paged(w, users, pp.Page, pp.Limit, total)
}

func (h *Handler) getMe(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	u, err := h.svc.GetByID(r.Context(), id.UserID)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, u)
}

func (h *Handler) updateMe(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())

	var in ProfileUpdateInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	u, err := h.svc.UpdateProfile(r.Context(), id.UserID, in)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, u)
}

func (h *Handler) updateRole(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "userId")

	var in struct {
		Role auth.Role `json:"role"`
	}
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}

	u, err := h.svc.UpdateRole(r.Context(), userID, in.Role)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, u)
}

// writeServiceError maps service/repository errors to HTTP responses.
func (h *Handler) writeServiceError(w http.ResponseWriter, err error) {
	var ve *ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.ErrorCode(w, http.StatusBadRequest, ve.Message, "bad_request")
	case errors.Is(err, ErrEmailExists):
		httpx.ErrorCode(w, http.StatusConflict, "email already registered", "conflict")
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, "user not found", "not_found")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}
