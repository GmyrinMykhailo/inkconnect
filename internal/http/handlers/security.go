package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"inkconnect/internal/config"
	"inkconnect/internal/users"
)

type SecurityHandler struct {
	authService     *users.AuthenticationService
	securityService *users.SecurityService
	cookieName      string
}

func NewSecurityHandler(cfg config.Config, authService *users.AuthenticationService, securityService *users.SecurityService) *SecurityHandler {
	return &SecurityHandler{
		authService:     authService,
		securityService: securityService,
		cookieName:      cfg.SessionCookieName,
	}
}

func (h *SecurityHandler) ServePasswordHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPatch {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var payload struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
		PasswordConfirm string `json:"password_confirm"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid password payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	err = h.securityService.ChangePassword(ctx, user.ID, users.PasswordChangeInput{
		CurrentPassword: payload.CurrentPassword,
		NewPassword:     payload.NewPassword,
		PasswordConfirm: payload.PasswordConfirm,
	})
	if err != nil {
		if errors.Is(err, users.ErrUserNotFound) {
			http.Error(w, "user not found", http.StatusNotFound)
			return
		}
		if isPasswordChangeValidationError(err) {
			http.Error(w, humanizePasswordChangeError(err), http.StatusBadRequest)
			return
		}
		http.Error(w, "failed to change password", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *SecurityHandler) ServeContactHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	contact, err := h.securityService.GetContact(ctx, user.ID)
	if err != nil {
		if errors.Is(err, users.ErrUserNotFound) {
			http.Error(w, "user not found", http.StatusNotFound)
			return
		}
		http.Error(w, "failed to load security contact", http.StatusInternalServerError)
		return
	}

	writeJSON(w, map[string]any{
		"contact": contact,
	})
}

func (h *SecurityHandler) ServeEmailHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPatch {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var payload struct {
		CurrentPassword string `json:"current_password"`
		Email           string `json:"email"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid email payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	contact, err := h.securityService.UpdateEmail(ctx, user.ID, users.EmailUpdateInput{
		CurrentPassword: payload.CurrentPassword,
		Email:           payload.Email,
	})
	if err != nil {
		writeSecurityError(w, err, "failed to update email")
		return
	}

	writeJSON(w, map[string]any{
		"contact": contact,
	})
}

func (h *SecurityHandler) ServePhoneHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPatch {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var payload struct {
		CurrentPassword string `json:"current_password"`
		Phone           string `json:"phone"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid phone payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	contact, err := h.securityService.UpdatePhone(ctx, user.ID, users.PhoneUpdateInput{
		CurrentPassword: payload.CurrentPassword,
		Phone:           payload.Phone,
	})
	if err != nil {
		writeSecurityError(w, err, "failed to update phone")
		return
	}

	writeJSON(w, map[string]any{
		"contact": contact,
	})
}

func (h *SecurityHandler) ServeAccountHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var payload struct {
		CurrentPassword string `json:"current_password"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid account payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	err = h.securityService.DeleteAccount(ctx, user.ID, users.AccountDeleteInput{
		CurrentPassword: payload.CurrentPassword,
	})
	if err != nil {
		writeSecurityError(w, err, "failed to delete account")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *SecurityHandler) authenticateRequest(r *http.Request) (users.AuthenticatedUser, error) {
	token := h.sessionTokenFromRequest(r)
	if strings.TrimSpace(token) == "" {
		return users.AuthenticatedUser{}, users.ErrSessionNotFound
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	return h.authService.Authenticate(ctx, token)
}

func (h *SecurityHandler) sessionTokenFromRequest(r *http.Request) string {
	authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
		return strings.TrimSpace(authHeader[7:])
	}

	cookie, err := r.Cookie(h.cookieName)
	if err != nil {
		return ""
	}

	return strings.TrimSpace(cookie.Value)
}

func isPasswordChangeValidationError(err error) bool {
	return errors.Is(err, users.ErrCurrentPasswordRequired) ||
		errors.Is(err, users.ErrCurrentPasswordInvalid) ||
		errors.Is(err, users.ErrWeakPassword) ||
		errors.Is(err, users.ErrPasswordConfirmWeak) ||
		errors.Is(err, users.ErrPasswordMismatch) ||
		errors.Is(err, users.ErrFieldTooLong)
}

func humanizePasswordChangeError(err error) string {
	switch {
	case errors.Is(err, users.ErrCurrentPasswordRequired):
		return "Введите текущий пароль."
	case errors.Is(err, users.ErrCurrentPasswordInvalid):
		return "Текущий пароль указан неверно."
	default:
		return humanizeRegistrationError(err)
	}
}

func writeSecurityError(w http.ResponseWriter, err error, fallback string) {
	if errors.Is(err, users.ErrUserNotFound) {
		http.Error(w, "user not found", http.StatusNotFound)
		return
	}
	if isSecurityValidationError(err) {
		http.Error(w, humanizeSecurityError(err), http.StatusBadRequest)
		return
	}
	http.Error(w, fallback, http.StatusInternalServerError)
}

func isSecurityValidationError(err error) bool {
	return isPasswordChangeValidationError(err) ||
		errors.Is(err, users.ErrEmailRequired) ||
		errors.Is(err, users.ErrInvalidEmail) ||
		errors.Is(err, users.ErrEmailAlreadyExists) ||
		errors.Is(err, users.ErrPhoneRequired) ||
		errors.Is(err, users.ErrInvalidPhone) ||
		errors.Is(err, users.ErrPhoneAlreadyExists)
}

func humanizeSecurityError(err error) string {
	switch {
	case errors.Is(err, users.ErrCurrentPasswordRequired):
		return "Введите текущий пароль."
	case errors.Is(err, users.ErrCurrentPasswordInvalid):
		return "Текущий пароль указан неверно."
	default:
		return humanizeRegistrationError(err)
	}
}
