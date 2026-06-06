package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"inkconnect/internal/catalog"
	"inkconnect/internal/config"
	"inkconnect/internal/users"
)

type MasterServicesHandler struct {
	authService *users.AuthenticationService
	service     *catalog.MasterServicesService
	cookieName  string
}

func NewMasterServicesHandler(cfg config.Config, authService *users.AuthenticationService, service *catalog.MasterServicesService) *MasterServicesHandler {
	return &MasterServicesHandler{
		authService: authService,
		service:     service,
		cookieName:  cfg.SessionCookieName,
	}
}

func (h *MasterServicesHandler) ServeCollectionHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.ListCurrentMasterServicesJSON(w, r)
	case http.MethodPost:
		h.CreateCurrentMasterServiceJSON(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *MasterServicesHandler) ServeSettingsHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.GetCurrentMasterSettingsJSON(w, r)
	case http.MethodPatch:
		h.UpdateCurrentMasterSettingsJSON(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *MasterServicesHandler) ServeScheduleHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.GetCurrentMasterScheduleJSON(w, r)
	case http.MethodPut:
		h.UpdateCurrentMasterScheduleJSON(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *MasterServicesHandler) ServeItemHTTP(w http.ResponseWriter, r *http.Request) {
	serviceID := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/masters/me/services/"), "/")
	if serviceID == "" || strings.Contains(serviceID, "/") {
		http.NotFound(w, r)
		return
	}

	switch r.Method {
	case http.MethodPatch:
		h.UpdateCurrentMasterServiceJSON(w, r, serviceID)
	case http.MethodDelete:
		h.DeleteCurrentMasterServiceJSON(w, r, serviceID)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *MasterServicesHandler) GetCurrentMasterSettingsJSON(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	settings, err := h.service.GetSettings(ctx, user.ID)
	if err != nil {
		http.Error(w, "failed to load master settings", http.StatusInternalServerError)
		return
	}

	writeJSON(w, map[string]any{
		"settings": settings,
	})
}

func (h *MasterServicesHandler) UpdateCurrentMasterSettingsJSON(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	var payload struct {
		Category            string   `json:"category"`
		Styles              []string `json:"styles"`
		MinSessionPrice     int      `json:"min_session_price"`
		HourlyRate          int      `json:"hourly_rate"`
		BreakBetweenClients string   `json:"break_between_clients"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid master settings payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	settings, err := h.service.UpdateSettings(ctx, user.ID, catalog.MasterSettingsInput{
		Category:            payload.Category,
		Styles:              payload.Styles,
		MinSessionPrice:     payload.MinSessionPrice,
		HourlyRate:          payload.HourlyRate,
		BreakBetweenClients: payload.BreakBetweenClients,
	})
	if err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, map[string]any{
		"settings": settings,
	})
}

func (h *MasterServicesHandler) GetCurrentMasterScheduleJSON(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	schedule, err := h.service.GetSchedule(ctx, user.ID)
	if err != nil {
		http.Error(w, "failed to load master schedule", http.StatusInternalServerError)
		return
	}

	writeJSON(w, map[string]any{
		"schedule": schedule,
	})
}

func (h *MasterServicesHandler) UpdateCurrentMasterScheduleJSON(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	var payload struct {
		Days []catalog.WorkScheduleDay `json:"days"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid master schedule payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	schedule, err := h.service.UpdateSchedule(ctx, user.ID, catalog.MasterWorkSchedule{
		Days: payload.Days,
	})
	if err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, map[string]any{
		"schedule": schedule,
	})
}

func (h *MasterServicesHandler) ListCurrentMasterServicesJSON(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	services, err := h.service.List(ctx, user.ID)
	if err != nil {
		http.Error(w, "failed to load master services", http.StatusInternalServerError)
		return
	}

	writeJSON(w, map[string]any{
		"items": services,
	})
}

func (h *MasterServicesHandler) CreateCurrentMasterServiceJSON(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	input, ok := decodeServiceInput(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	service, err := h.service.Create(ctx, user.ID, input)
	if err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSONStatus(w, http.StatusCreated, map[string]any{
		"service": service,
	})
}

func (h *MasterServicesHandler) UpdateCurrentMasterServiceJSON(w http.ResponseWriter, r *http.Request, serviceID string) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	input, ok := decodeServiceInput(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	service, err := h.service.Update(ctx, user.ID, serviceID, input)
	if err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, map[string]any{
		"service": service,
	})
}

func (h *MasterServicesHandler) DeleteCurrentMasterServiceJSON(w http.ResponseWriter, r *http.Request, serviceID string) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	if err := h.service.Delete(ctx, user.ID, serviceID); err != nil {
		writeServiceError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *MasterServicesHandler) authenticateMaster(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
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
	if user.Role != users.RoleMaster {
		http.Error(w, "master role required", http.StatusForbidden)
		return users.AuthenticatedUser{}, false
	}

	return user, true
}

func (h *MasterServicesHandler) sessionTokenFromRequest(r *http.Request) string {
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

type servicePayload struct {
	Name          string              `json:"name"`
	Description   string              `json:"description"`
	Type          catalog.ServiceType `json:"type"`
	DurationHours *float64            `json:"duration_hours"`
	Price         int                 `json:"price"`
	UseAutoPrice  bool                `json:"use_auto_price"`
	FromPrice     bool                `json:"from_price"`
}

func decodeServiceInput(w http.ResponseWriter, r *http.Request) (catalog.ServiceInput, bool) {
	var payload servicePayload
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid service payload", http.StatusBadRequest)
		return catalog.ServiceInput{}, false
	}

	return catalog.ServiceInput{
		Name:          payload.Name,
		Description:   payload.Description,
		Type:          payload.Type,
		DurationHours: payload.DurationHours,
		Price:         payload.Price,
		UseAutoPrice:  payload.UseAutoPrice,
		FromPrice:     payload.FromPrice,
	}, true
}

func writeServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, catalog.ErrServiceNotFound):
		http.Error(w, "service not found", http.StatusNotFound)
	case errors.Is(err, catalog.ErrServiceTitleRequired),
		errors.Is(err, catalog.ErrServiceInvalidType),
		errors.Is(err, catalog.ErrServiceInvalidPrice),
		errors.Is(err, catalog.ErrServiceInvalidTime),
		errors.Is(err, catalog.ErrServiceFieldTooLong),
		errors.Is(err, catalog.ErrScheduleInvalidDay),
		errors.Is(err, catalog.ErrScheduleInvalidTime),
		errors.Is(err, catalog.ErrScheduleInvalidType),
		errors.Is(err, catalog.ErrScheduleOverlap):
		http.Error(w, err.Error(), http.StatusBadRequest)
	default:
		http.Error(w, "failed to save master service", http.StatusInternalServerError)
	}
}

func writeJSON(w http.ResponseWriter, payload any) {
	writeJSONStatus(w, http.StatusOK, payload)
}

func writeJSONStatus(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
