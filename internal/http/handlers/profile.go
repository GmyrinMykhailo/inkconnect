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

type ProfileHandler struct {
	authService    *users.AuthenticationService
	profileService *users.ProfileService
	cookieName     string
}

func NewProfileHandler(cfg config.Config, authService *users.AuthenticationService, profileService *users.ProfileService) *ProfileHandler {
	return &ProfileHandler{
		authService:    authService,
		profileService: profileService,
		cookieName:     cfg.SessionCookieName,
	}
}

func (h *ProfileHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.GetCurrentProfileJSON(w, r)
	case http.MethodPatch:
		h.UpdateCurrentProfileJSON(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *ProfileHandler) GetCurrentProfileJSON(w http.ResponseWriter, r *http.Request) {
	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	profile, err := h.profileService.GetProfile(ctx, user.ID)
	if err != nil {
		if errors.Is(err, users.ErrUserNotFound) {
			http.Error(w, "profile not found", http.StatusNotFound)
			return
		}
		http.Error(w, "failed to load profile", http.StatusInternalServerError)
		return
	}

	writeProfileJSON(w, profile)
}

func (h *ProfileHandler) UpdateCurrentProfileJSON(w http.ResponseWriter, r *http.Request) {
	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var payload struct {
		LastName              *string `json:"last_name"`
		FirstName             *string `json:"first_name"`
		MiddleName            *string `json:"middle_name"`
		StudioName            *string `json:"studio_name"`
		City                  *string `json:"city"`
		Bio                   *string `json:"bio"`
		ShowFullNameInProfile *bool   `json:"show_full_name_in_profile"`
		ShowCityInProfile     *bool   `json:"show_city_in_profile"`
	}

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid profile payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	profile, err := h.profileService.UpdateProfile(ctx, user.ID, users.ProfileUpdateInput{
		LastName:              payload.LastName,
		FirstName:             payload.FirstName,
		MiddleName:            payload.MiddleName,
		StudioName:            payload.StudioName,
		City:                  payload.City,
		Bio:                   payload.Bio,
		ShowFullNameInProfile: payload.ShowFullNameInProfile,
		ShowCityInProfile:     payload.ShowCityInProfile,
	})
	if err != nil {
		if errors.Is(err, users.ErrUserNotFound) {
			http.Error(w, "profile not found", http.StatusNotFound)
			return
		}
		if isProfileValidationError(err) {
			http.Error(w, humanizeRegistrationError(err), http.StatusBadRequest)
			return
		}
		http.Error(w, "failed to update profile", http.StatusInternalServerError)
		return
	}

	writeProfileJSON(w, profile)
}

func (h *ProfileHandler) ServePublicProfileHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if _, err := h.authenticateRequest(r); err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	username := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/profiles/"), "/")
	if username == "" || strings.Contains(username, "/") {
		http.NotFound(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	profile, err := h.profileService.GetPublicProfile(ctx, username)
	if err != nil {
		if errors.Is(err, users.ErrUserNotFound) {
			http.NotFound(w, r)
			return
		}
		http.Error(w, "failed to load profile", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"profile": profile,
	})
}

func (h *ProfileHandler) authenticateRequest(r *http.Request) (users.AuthenticatedUser, error) {
	token := h.sessionTokenFromRequest(r)
	if strings.TrimSpace(token) == "" {
		return users.AuthenticatedUser{}, users.ErrSessionNotFound
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	return h.authService.Authenticate(ctx, token)
}

func (h *ProfileHandler) sessionTokenFromRequest(r *http.Request) string {
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

func writeProfileJSON(w http.ResponseWriter, profile users.UserProfile) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"profile": profile,
	})
}

func isProfileValidationError(err error) bool {
	return errors.Is(err, users.ErrLastNameRequired) ||
		errors.Is(err, users.ErrFirstNameRequired) ||
		errors.Is(err, users.ErrInvalidName) ||
		errors.Is(err, users.ErrNameScriptMismatch) ||
		errors.Is(err, users.ErrCityRequired) ||
		errors.Is(err, users.ErrInvalidCity) ||
		errors.Is(err, users.ErrBioTooLong) ||
		errors.Is(err, users.ErrFieldTooLong)
}
