package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"inkconnect/internal/appointments"
	"inkconnect/internal/config"
	"inkconnect/internal/users"
)

type AppointmentsHandler struct {
	authService *users.AuthenticationService
	service     *appointments.Service
	cookieName  string
}

func NewAppointmentsHandler(cfg config.Config, authService *users.AuthenticationService, service *appointments.Service) *AppointmentsHandler {
	return &AppointmentsHandler{
		authService: authService,
		service:     service,
		cookieName:  cfg.SessionCookieName,
	}
}

func (h *AppointmentsHandler) ServeAvailabilityHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/masters/"), "/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] != "availability" {
		http.NotFound(w, r)
		return
	}

	date := time.Now().UTC()
	if rawDate := strings.TrimSpace(r.URL.Query().Get("date")); rawDate != "" {
		parsed, err := time.Parse("2006-01-02", rawDate)
		if err != nil {
			http.Error(w, "invalid date", http.StatusBadRequest)
			return
		}
		date = parsed
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	result, err := h.service.Availability(ctx, parts[0], date, strings.TrimSpace(r.URL.Query().Get("service_id")))
	if err != nil {
		if errors.Is(err, appointments.ErrMasterNotFound) ||
			errors.Is(err, appointments.ErrServiceNotFound) {
			http.NotFound(w, r)
			return
		}
		http.Error(w, "failed to load availability", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"availability": result})
}

func (h *AppointmentsHandler) ServeCollectionHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}

	var payload struct {
		MasterUsername string `json:"master_username"`
		ServiceID      string `json:"service_id"`
		ScheduledAt    string `json:"scheduled_at"`
		ClientNote     string `json:"client_note"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid appointment payload", http.StatusBadRequest)
		return
	}

	scheduledAt, err := time.Parse(time.RFC3339, strings.TrimSpace(payload.ScheduledAt))
	if err != nil {
		http.Error(w, "invalid scheduled_at", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	appointment, err := h.service.Create(ctx, appointments.CreateAppointmentInput{
		ClientID:       user.ID,
		MasterUsername: payload.MasterUsername,
		ServiceID:      payload.ServiceID,
		ScheduledAt:    scheduledAt,
		ClientNote:     strings.TrimSpace(payload.ClientNote),
	})
	if err != nil {
		switch {
		case errors.Is(err, appointments.ErrMasterNotFound), errors.Is(err, appointments.ErrServiceNotFound):
			http.Error(w, "booking target not found", http.StatusNotFound)
		case errors.Is(err, appointments.ErrSlotUnavailable):
			http.Error(w, "slot unavailable", http.StatusConflict)
		default:
			http.Error(w, "failed to create appointment", http.StatusInternalServerError)
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(map[string]any{"appointment": appointment})
}

func (h *AppointmentsHandler) ServeClientHTTP(w http.ResponseWriter, r *http.Request) {
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

	items, err := h.service.ListClient(ctx, user.ID)
	if err != nil {
		http.Error(w, "failed to load appointments", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"items":  items,
		"counts": appointments.CountsFromAppointments(items),
	})
}

func (h *AppointmentsHandler) ServeMasterHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	items, err := h.service.ListMaster(ctx, user.ID)
	if err != nil {
		http.Error(w, "failed to load master appointments", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"items":  items,
		"counts": appointments.CountsFromAppointments(items),
	})
}

func (h *AppointmentsHandler) ServeMasterItemHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPatch {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	path := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/master/appointments/"), "/")
	parts := strings.Split(path, "/")
	if len(parts) == 2 && parts[1] == "duration" {
		h.updateMasterDurationHTTP(w, r, user.ID, parts[0])
		return
	}
	if len(parts) != 1 || parts[0] == "" {
		http.NotFound(w, r)
		return
	}
	appointmentID := parts[0]

	var payload struct {
		Status string `json:"status"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid status payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	appointment, err := h.service.UpdateMasterStatus(ctx, user.ID, appointmentID, payload.Status)
	if err != nil {
		if errors.Is(err, appointments.ErrInvalidStatus) {
			http.Error(w, "invalid appointment status", http.StatusBadRequest)
			return
		}
		if errors.Is(err, appointments.ErrAppointmentNotFound) {
			http.NotFound(w, r)
			return
		}
		http.Error(w, "failed to update appointment", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"appointment": appointment})
}

func (h *AppointmentsHandler) updateMasterDurationHTTP(w http.ResponseWriter, r *http.Request, masterID string, appointmentID string) {
	if strings.TrimSpace(appointmentID) == "" {
		http.NotFound(w, r)
		return
	}

	var payload struct {
		DurationMinutes int `json:"duration_minutes"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid duration payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	result, err := h.service.UpdateMasterDuration(ctx, masterID, appointmentID, payload.DurationMinutes)
	if err != nil {
		if errors.Is(err, appointments.ErrInvalidDuration) {
			http.Error(w, "invalid appointment duration", http.StatusBadRequest)
			return
		}
		if errors.Is(err, appointments.ErrAppointmentNotFound) {
			http.NotFound(w, r)
			return
		}
		http.Error(w, "failed to update appointment duration", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(result)
}

func (h *AppointmentsHandler) authenticate(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
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

func (h *AppointmentsHandler) authenticateMaster(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return users.AuthenticatedUser{}, false
	}
	if user.Role != users.RoleMaster {
		http.Error(w, "master role required", http.StatusForbidden)
		return users.AuthenticatedUser{}, false
	}
	return user, true
}

func (h *AppointmentsHandler) sessionTokenFromRequest(r *http.Request) string {
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
