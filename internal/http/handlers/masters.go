package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"inkconnect/internal/users"
)

type MasterSearchHandler struct {
	repository users.Repository
}

func NewMasterSearchHandler(repository users.Repository) *MasterSearchHandler {
	return &MasterSearchHandler{repository: repository}
}

func (h *MasterSearchHandler) SearchJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	query := strings.TrimSpace(r.URL.Query().Get("q"))
	limit := 100
	if rawLimit := strings.TrimSpace(r.URL.Query().Get("limit")); rawLimit != "" {
		if parsed, err := strconv.Atoi(rawLimit); err == nil && parsed > 0 {
			limit = parsed
		}
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	masters, err := h.repository.SearchMasters(ctx, query, limit)
	if err != nil {
		http.Error(w, "failed to search masters", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"items": masters,
		"query": query,
	})
}

func (h *MasterSearchHandler) PublicProfileJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	username := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/masters/"), "/")
	if username == "" || strings.Contains(username, "/") || username == "search" || username == "me" {
		http.NotFound(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	master, err := h.repository.FindPublicMasterByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, users.ErrUserNotFound) {
			http.NotFound(w, r)
			return
		}
		http.Error(w, "failed to load master profile", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"profile": master,
	})
}

type UsernameHandler struct {
	repository users.Repository
}

func NewUsernameHandler(repository users.Repository) *UsernameHandler {
	return &UsernameHandler{repository: repository}
}

func (h *UsernameHandler) CheckAvailabilityJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	username := strings.TrimSpace(r.URL.Query().Get("username"))
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	available := false
	if username != "" {
		exists, err := h.repository.UsernameExists(ctx, username)
		if err != nil {
			http.Error(w, "failed to check username", http.StatusInternalServerError)
			return
		}
		available = !exists
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"username":  username,
		"available": available,
	})
}

type AuthAvailabilityHandler struct {
	repository users.Repository
}

func NewAuthAvailabilityHandler(repository users.Repository) *AuthAvailabilityHandler {
	return &AuthAvailabilityHandler{repository: repository}
}

func (h *AuthAvailabilityHandler) CheckEmailAvailabilityJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	email := strings.TrimSpace(strings.ToLower(r.URL.Query().Get("email")))
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	available := false
	if email != "" {
		exists, err := h.repository.EmailExists(ctx, email)
		if err != nil {
			http.Error(w, "failed to check email", http.StatusInternalServerError)
			return
		}
		available = !exists
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"email":     email,
		"available": available,
	})
}

func (h *AuthAvailabilityHandler) CheckPhoneAvailabilityJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	phone := strings.TrimSpace(r.URL.Query().Get("phone"))
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	available := false
	if phone != "" {
		exists, err := h.repository.PhoneExists(ctx, phone)
		if err != nil {
			http.Error(w, "failed to check phone", http.StatusInternalServerError)
			return
		}
		available = !exists
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"phone":     phone,
		"available": available,
	})
}
