package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"net"
	"net/http"
	"strings"
	"time"

	"inkconnect/internal/config"
	"inkconnect/internal/users"
)

type AuthHandler struct {
	templates    *template.Template
	service      *users.AuthenticationService
	cookieName   string
	cookieMaxAge time.Duration
}

type loginViewData struct {
	Title      string
	Error      string
	User       *users.AuthenticatedUser
	FormValues map[string]string
}

func NewAuthHandler(cfg config.Config, service *users.AuthenticationService) (*AuthHandler, error) {
	tmpl, err := template.ParseFiles(
		cfg.TemplatesDir+"/login.html",
		cfg.TemplatesDir+"/dashboard.html",
	)
	if err != nil {
		return nil, fmt.Errorf("parse auth templates: %w", err)
	}

	return &AuthHandler{
		templates:    tmpl,
		service:      service,
		cookieName:   cfg.SessionCookieName,
		cookieMaxAge: cfg.SessionDuration,
	}, nil
}

func (h *AuthHandler) LoginPage(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		if user := h.currentUser(r); user != nil {
			http.Redirect(w, r, "/app", http.StatusSeeOther)
			return
		}
		h.renderLogin(w, loginViewData{
			Title:      "Вход в InkConnect",
			FormValues: map[string]string{},
		})
	case http.MethodPost:
		h.handleLoginSubmit(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *AuthHandler) LoginJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var payload struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}

	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, "invalid json payload", http.StatusBadRequest)
		return
	}

	result, err := h.login(r.Context(), payload.Email, payload.Password, r)
	if err != nil {
		http.Error(w, humanizeLoginError(err), http.StatusUnauthorized)
		return
	}

	h.setSessionCookie(w, result.SessionToken, result.ExpiresAt)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(result)
}

func (h *AuthHandler) CurrentUserJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, humanizeLoginError(err), http.StatusUnauthorized)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"user": user,
	})
}

func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	if token := h.sessionTokenFromRequest(r); token != "" {
		_ = h.service.Logout(r.Context(), token)
	}

	h.clearSessionCookie(w)
	http.Redirect(w, r, "/login", http.StatusSeeOther)
}

func (h *AuthHandler) LogoutJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	if token := h.sessionTokenFromRequest(r); token != "" {
		_ = h.service.Logout(r.Context(), token)
	}

	h.clearSessionCookie(w)
	w.WriteHeader(http.StatusNoContent)
}

func (h *AuthHandler) AppPage(w http.ResponseWriter, r *http.Request) {
	user := h.currentUser(r)
	if user == nil {
		http.Redirect(w, r, "/login", http.StatusSeeOther)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.templates.ExecuteTemplate(w, "dashboard.html", loginViewData{
		Title: "Профиль InkConnect",
		User:  user,
	}); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func (h *AuthHandler) handleLoginSubmit(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}

	email := r.FormValue("email")
	result, err := h.login(r.Context(), email, r.FormValue("password"), r)
	if err != nil {
		h.renderLogin(w, loginViewData{
			Title: "Вход в InkConnect",
			Error: humanizeLoginError(err),
			FormValues: map[string]string{
				"email": email,
			},
		})
		return
	}

	h.setSessionCookie(w, result.SessionToken, result.ExpiresAt)
	http.Redirect(w, r, "/app", http.StatusSeeOther)
}

func (h *AuthHandler) login(ctx context.Context, email, password string, r *http.Request) (users.LoginResult, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return h.service.Login(ctx, users.LoginInput{
		Email:    email,
		Password: password,
	}, r.UserAgent(), clientIP(r))
}

func (h *AuthHandler) authenticateRequest(r *http.Request) (users.AuthenticatedUser, error) {
	token := h.sessionTokenFromRequest(r)
	if strings.TrimSpace(token) == "" {
		return users.AuthenticatedUser{}, users.ErrSessionNotFound
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	return h.service.Authenticate(ctx, token)
}

func (h *AuthHandler) currentUser(r *http.Request) *users.AuthenticatedUser {
	user, err := h.authenticateRequest(r)
	if err != nil {
		return nil
	}

	return &user
}

func (h *AuthHandler) sessionTokenFromRequest(r *http.Request) string {
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

func (h *AuthHandler) setSessionCookie(w http.ResponseWriter, token string, expiresAt time.Time) {
	http.SetCookie(w, &http.Cookie{
		Name:     h.cookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Expires:  expiresAt,
		MaxAge:   int(h.cookieMaxAge.Seconds()),
	})
}

func (h *AuthHandler) clearSessionCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     h.cookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   -1,
		Expires:  time.Unix(0, 0),
	})
}

func (h *AuthHandler) renderLogin(w http.ResponseWriter, data loginViewData) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.templates.ExecuteTemplate(w, "login.html", data); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func humanizeLoginError(err error) string {
	if errors.Is(err, users.ErrInvalidCredentials) {
		return "Неверный email или пароль"
	}

	return "Не удалось выполнить вход. Попробуйте еще раз."
}

func clientIP(r *http.Request) string {
	if forwarded := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); forwarded != "" {
		return strings.TrimSpace(strings.Split(forwarded, ",")[0])
	}

	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}

	return host
}
