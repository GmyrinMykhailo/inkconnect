package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"inkconnect/internal/config"
	"inkconnect/internal/recommendations"
	"inkconnect/internal/users"
)

type RecommendationsHandler struct {
	authService *users.AuthenticationService
	service     *recommendations.Service
	cookieName  string
}

func NewRecommendationsHandler(cfg config.Config, authService *users.AuthenticationService, service *recommendations.Service) *RecommendationsHandler {
	return &RecommendationsHandler{
		authService: authService,
		service:     service,
		cookieName:  cfg.SessionCookieName,
	}
}

func (h *RecommendationsHandler) ServeMasterHTTP(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}

	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/master/appointments/"), "/"), "/")
	if len(parts) == 2 && parts[1] == "recommendations" {
		switch r.Method {
		case http.MethodGet:
			h.getMasterRecommendations(w, r, user.ID, parts[0])
		case http.MethodPut:
			h.saveMasterRecommendations(w, r, user.ID, parts[0])
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
		return
	}
	if len(parts) == 3 && parts[1] == "recommendations" && parts[2] == "send" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.sendMasterRecommendations(w, r, user.ID, parts[0])
		return
	}

	http.NotFound(w, r)
}

func (h *RecommendationsHandler) ServeClientHTTP(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}

	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/appointments/"), "/"), "/")
	if len(parts) == 2 && parts[1] == "recommendations" {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.getClientRecommendations(w, r, user.ID, parts[0])
		return
	}
	if len(parts) == 3 && parts[1] == "recommendations" && parts[2] == "approve" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.approveClientRecommendations(w, r, user.ID, parts[0])
		return
	}

	http.NotFound(w, r)
}

func (h *RecommendationsHandler) getMasterRecommendations(w http.ResponseWriter, r *http.Request, masterID string, appointmentID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	response, err := h.service.GetForMaster(ctx, masterID, appointmentID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeResponse(w, response)
}

func (h *RecommendationsHandler) saveMasterRecommendations(w http.ResponseWriter, r *http.Request, masterID string, appointmentID string) {
	steps, ok := h.decodeSteps(w, r)
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	response, err := h.service.SaveDraft(ctx, masterID, appointmentID, steps)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeResponse(w, response)
}

func (h *RecommendationsHandler) sendMasterRecommendations(w http.ResponseWriter, r *http.Request, masterID string, appointmentID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	response, err := h.service.Send(ctx, masterID, appointmentID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeResponse(w, response)
}

func (h *RecommendationsHandler) getClientRecommendations(w http.ResponseWriter, r *http.Request, clientID string, appointmentID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	response, err := h.service.GetForClient(ctx, clientID, appointmentID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeResponse(w, response)
}

func (h *RecommendationsHandler) approveClientRecommendations(w http.ResponseWriter, r *http.Request, clientID string, appointmentID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	response, err := h.service.Approve(ctx, clientID, appointmentID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeResponse(w, response)
}

func (h *RecommendationsHandler) decodeSteps(w http.ResponseWriter, r *http.Request) ([]recommendations.Step, bool) {
	var payload struct {
		Steps []struct {
			StepNumber    int     `json:"step_number"`
			Title         string  `json:"title"`
			Description   string  `json:"description"`
			DueOffsetDays *int    `json:"due_offset_days"`
			DueAt         *string `json:"due_at"`
		} `json:"steps"`
	}

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "invalid recommendations payload", http.StatusBadRequest)
		return nil, false
	}

	steps := make([]recommendations.Step, 0, len(payload.Steps))
	for _, raw := range payload.Steps {
		var dueAt *time.Time
		if raw.DueAt != nil && strings.TrimSpace(*raw.DueAt) != "" {
			parsed, err := time.Parse(time.RFC3339, strings.TrimSpace(*raw.DueAt))
			if err != nil {
				http.Error(w, "invalid recommendation due_at", http.StatusBadRequest)
				return nil, false
			}
			dueAt = &parsed
		}
		steps = append(steps, recommendations.Step{
			StepNumber:    raw.StepNumber,
			Title:         raw.Title,
			Description:   raw.Description,
			DueOffsetDays: raw.DueOffsetDays,
			DueAt:         dueAt,
		})
	}
	return steps, true
}

func (h *RecommendationsHandler) authenticate(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
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

func (h *RecommendationsHandler) authenticateMaster(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
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

func (h *RecommendationsHandler) sessionTokenFromRequest(r *http.Request) string {
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

func (h *RecommendationsHandler) writeResponse(w http.ResponseWriter, response recommendations.Response) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(response)
}

func (h *RecommendationsHandler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, recommendations.ErrAppointmentNotFound),
		errors.Is(err, recommendations.ErrRecommendationsNone):
		http.NotFound(w, r)
	case errors.Is(err, recommendations.ErrForbidden):
		http.Error(w, "recommendation access forbidden", http.StatusForbidden)
	case errors.Is(err, recommendations.ErrInvalidInput):
		http.Error(w, "invalid recommendations", http.StatusBadRequest)
	case errors.Is(err, recommendations.ErrAppointmentNotReady):
		http.Error(w, "appointment is not ready for recommendations", http.StatusConflict)
	case errors.Is(err, recommendations.ErrRecommendationsDone):
		http.Error(w, "recommendations already approved", http.StatusConflict)
	case errors.Is(err, recommendations.ErrRecommendationsDraft):
		http.Error(w, "recommendations are not sent", http.StatusConflict)
	default:
		http.Error(w, "failed to process recommendations", http.StatusInternalServerError)
	}
}
