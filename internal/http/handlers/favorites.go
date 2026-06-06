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

type FavoritesHandler struct {
	cookieName  string
	authService *users.AuthenticationService
	repository  users.Repository
}

func NewFavoritesHandler(cfg config.Config, authService *users.AuthenticationService, repository users.Repository) *FavoritesHandler {
	return &FavoritesHandler{
		cookieName:  cfg.SessionCookieName,
		authService: authService,
		repository:  repository,
	}
}

func (h *FavoritesHandler) ServeMasterCollectionHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	masters, err := h.repository.ListFavoriteMasters(ctx, user.ID)
	if err != nil {
		http.Error(w, "failed to load favorite masters", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"items": masters,
	})
}

func (h *FavoritesHandler) ServeMasterItemHTTP(w http.ResponseWriter, r *http.Request) {
	masterID := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/favorites/masters/"), "/")
	if masterID == "" || strings.Contains(masterID, "/") {
		http.NotFound(w, r)
		return
	}

	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	switch r.Method {
	case http.MethodPost:
		if err := h.repository.AddFavoriteMaster(ctx, user.ID, masterID); err != nil {
			if errors.Is(err, users.ErrCannotFavoriteSelf) {
				http.Error(w, "cannot add own profile to favorites", http.StatusForbidden)
				return
			}
			if errors.Is(err, users.ErrUserNotFound) {
				http.NotFound(w, r)
				return
			}
			http.Error(w, "failed to add favorite master", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	case http.MethodDelete:
		if err := h.repository.RemoveFavoriteMaster(ctx, user.ID, masterID); err != nil {
			http.Error(w, "failed to remove favorite master", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *FavoritesHandler) authenticate(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
	token := h.sessionTokenFromRequest(r)
	if strings.TrimSpace(token) == "" {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return users.AuthenticatedUser{}, false
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	user, err := h.authService.Authenticate(ctx, token)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return users.AuthenticatedUser{}, false
	}
	return user, true
}

func (h *FavoritesHandler) sessionTokenFromRequest(r *http.Request) string {
	authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
		return strings.TrimSpace(authHeader[7:])
	}

	cookie, err := r.Cookie(h.cookieName)
	if err != nil {
		return ""
	}
	return cookie.Value
}
