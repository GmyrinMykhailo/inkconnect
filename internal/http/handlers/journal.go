package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"inkconnect/internal/config"
	"inkconnect/internal/journal"
	"inkconnect/internal/users"
)

type JournalHandler struct {
	authService *users.AuthenticationService
	service     *journal.Service
	cookieName  string
}

func NewJournalHandler(cfg config.Config, authService *users.AuthenticationService, service *journal.Service) *JournalHandler {
	return &JournalHandler{
		authService: authService,
		service:     service,
		cookieName:  cfg.SessionCookieName,
	}
}

func (h *JournalHandler) ServeAppointmentHTTP(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/appointments/"), "/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] != "journal" {
		http.NotFound(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	detail, err := h.service.CreateForAppointment(ctx, user.ID, parts[0])
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeDetail(w, detail)
}

func (h *JournalHandler) ServeAppointmentListHTTP(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/appointments/"), "/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] != "journals" {
		http.NotFound(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	items, err := h.service.ListForAppointment(ctx, user.ID, parts[0])
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeAppointmentJournals(w, items)
}

func (h *JournalHandler) ServeClientListHTTP(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	items, err := h.service.ListClient(ctx, user.ID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeList(w, items)
}

func (h *JournalHandler) ServeMasterListHTTP(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticateMaster(w, r)
	if !ok {
		return
	}
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	items, err := h.service.ListMaster(ctx, user.ID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeList(w, items)
}

func (h *JournalHandler) ServeJournalHTTP(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}

	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/journals/"), "/"), "/")
	if len(parts) == 2 && parts[0] != "" && parts[1] == "integrity" {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.getIntegrity(w, r, user, parts[0])
		return
	}
	if len(parts) == 2 && parts[0] != "" && parts[1] == "events" {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.getEvents(w, r, user, parts[0])
		return
	}
	if len(parts) == 2 && parts[0] != "" && parts[1] == "unavailability" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.createUnavailabilityNotice(w, r, user.ID, parts[0])
		return
	}
	if len(parts) == 2 && parts[0] != "" && parts[1] == "client-problem" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.createClientProblemReport(w, r, user.ID, parts[0])
		return
	}
	if len(parts) == 2 && parts[0] != "" && parts[1] == "stop" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.stopJournal(w, r, user.ID, parts[0])
		return
	}
	if len(parts) == 2 && parts[0] != "" && parts[1] == "replacement" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.createReplacementJournal(w, r, user.ID, parts[0])
		return
	}
	if len(parts) == 1 && parts[0] != "" {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.getDetail(w, r, user, parts[0])
		return
	}
	if len(parts) == 4 && parts[0] != "" && parts[1] == "steps" && parts[2] != "" && parts[3] == "confirm" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.confirmStep(w, r, user.ID, parts[0], parts[2])
		return
	}
	if len(parts) == 4 && parts[0] != "" && parts[1] == "steps" && parts[2] != "" && parts[3] == "deadline-extension" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.extendStepDeadline(w, r, user.ID, parts[0], parts[2])
		return
	}
	if len(parts) == 5 && parts[0] != "" && parts[1] == "steps" && parts[2] != "" && parts[3] == "confirm" && parts[4] == "prepare" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.prepareStepConfirmation(w, r, user.ID, parts[0], parts[2])
		return
	}
	if len(parts) == 5 && parts[0] != "" && parts[1] == "steps" && parts[2] != "" && parts[3] == "confirm" && parts[4] == "commit" {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		h.commitStepConfirmation(w, r, user.ID, parts[0], parts[2])
		return
	}

	http.NotFound(w, r)
}

func (h *JournalHandler) getDetail(w http.ResponseWriter, r *http.Request, user users.AuthenticatedUser, journalID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	detail, err := h.service.Detail(ctx, user.ID, journalID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeDetail(w, detail)
}

func (h *JournalHandler) getIntegrity(w http.ResponseWriter, r *http.Request, user users.AuthenticatedUser, journalID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	report, err := h.service.Integrity(ctx, user.ID, journalID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeIntegrity(w, report)
}

func (h *JournalHandler) getEvents(w http.ResponseWriter, r *http.Request, user users.AuthenticatedUser, journalID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	events, err := h.service.Events(ctx, user.ID, journalID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeEvents(w, events)
}

func (h *JournalHandler) confirmStep(w http.ResponseWriter, r *http.Request, clientID string, journalID string, stepID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	detail, err := h.service.ConfirmStep(ctx, clientID, journalID, stepID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeDetail(w, detail)
}

func (h *JournalHandler) prepareStepConfirmation(w http.ResponseWriter, r *http.Request, clientID string, journalID string, stepID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	prepare, err := h.service.PrepareStepConfirmation(ctx, clientID, journalID, stepID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeStepConfirmationPrepare(w, prepare)
}

func (h *JournalHandler) commitStepConfirmation(w http.ResponseWriter, r *http.Request, clientID string, journalID string, stepID string) {
	var request journal.StepConfirmationCommit
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid signed confirmation payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	detail, err := h.service.CommitStepConfirmation(ctx, clientID, journalID, stepID, request)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeDetail(w, detail)
}

func (h *JournalHandler) createUnavailabilityNotice(w http.ResponseWriter, r *http.Request, clientID string, journalID string) {
	var request journal.ClientUnavailabilityNoticeInput
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid unavailability notice payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	result, err := h.service.CreateClientUnavailabilityNotice(ctx, clientID, journalID, request)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeJournalEventResult(w, result)
}

func (h *JournalHandler) createClientProblemReport(w http.ResponseWriter, r *http.Request, clientID string, journalID string) {
	var request journal.ClientProblemReportInput
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid client problem payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	result, err := h.service.CreateClientProblemReport(ctx, clientID, journalID, request)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeJournalEventResult(w, result)
}

func (h *JournalHandler) extendStepDeadline(w http.ResponseWriter, r *http.Request, masterID string, journalID string, stepID string) {
	var request journal.DeadlineExtensionInput
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid deadline extension payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	result, err := h.service.CreateDeadlineExtension(ctx, masterID, journalID, stepID, request)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeDeadlineExtensionResult(w, result)
}

func (h *JournalHandler) stopJournal(w http.ResponseWriter, r *http.Request, masterID string, journalID string) {
	var request journal.JournalStopInput
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid journal stop payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	result, err := h.service.StopJournal(ctx, masterID, journalID, request)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeJournalStopResult(w, result)
}

func (h *JournalHandler) createReplacementJournal(w http.ResponseWriter, r *http.Request, masterID string, journalID string) {
	var request journal.ReplacementJournalInput
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid replacement journal payload", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	result, err := h.service.CreateReplacementJournal(ctx, masterID, journalID, request)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.writeReplacementJournalResult(w, result)
}

func (h *JournalHandler) authenticate(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
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

func (h *JournalHandler) authenticateMaster(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
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

func (h *JournalHandler) sessionTokenFromRequest(r *http.Request) string {
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

func (h *JournalHandler) writeDetail(w http.ResponseWriter, detail journal.Detail) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(detail)
}

func (h *JournalHandler) writeList(w http.ResponseWriter, items []journal.Summary) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"items": items})
}

func (h *JournalHandler) writeAppointmentJournals(w http.ResponseWriter, items []journal.AppointmentJournalSummary) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(items)
}

func (h *JournalHandler) writeIntegrity(w http.ResponseWriter, report journal.IntegrityReport) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(report)
}

func (h *JournalHandler) writeEvents(w http.ResponseWriter, events []journal.JournalEventView) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"items": events})
}

func (h *JournalHandler) writeStepConfirmationPrepare(w http.ResponseWriter, prepare journal.StepConfirmationPrepare) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(prepare)
}

func (h *JournalHandler) writeJournalEventResult(w http.ResponseWriter, result journal.JournalEventResult) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(result)
}

func (h *JournalHandler) writeDeadlineExtensionResult(w http.ResponseWriter, result journal.DeadlineExtensionResult) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(result)
}

func (h *JournalHandler) writeJournalStopResult(w http.ResponseWriter, result journal.JournalStopResult) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(result)
}

func (h *JournalHandler) writeReplacementJournalResult(w http.ResponseWriter, result journal.ReplacementJournalResult) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(result)
}

func (h *JournalHandler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, journal.ErrJournalNotFound),
		errors.Is(err, journal.ErrAppointmentNotFound),
		errors.Is(err, journal.ErrStepNotFound):
		http.NotFound(w, r)
	case errors.Is(err, journal.ErrInvalidCommit):
		http.Error(w, "invalid signed confirmation payload", http.StatusBadRequest)
	case errors.Is(err, journal.ErrInvalidDeadline):
		http.Error(w, "invalid deadline extension payload", http.StatusBadRequest)
	case errors.Is(err, journal.ErrInvalidProblem):
		http.Error(w, "invalid client problem payload", http.StatusBadRequest)
	case errors.Is(err, journal.ErrInvalidNotice):
		http.Error(w, "invalid unavailability notice payload", http.StatusBadRequest)
	case errors.Is(err, journal.ErrInvalidStop):
		http.Error(w, "invalid journal stop payload", http.StatusBadRequest)
	case errors.Is(err, journal.ErrInvalidReplacement):
		http.Error(w, "invalid replacement journal payload", http.StatusBadRequest)
	case errors.Is(err, journal.ErrInvalidSignature):
		http.Error(w, "invalid journal event signature", http.StatusUnauthorized)
	case errors.Is(err, journal.ErrForbidden):
		http.Error(w, "journal access forbidden", http.StatusForbidden)
	case errors.Is(err, journal.ErrNotReady):
		http.Error(w, "journal is not ready", http.StatusConflict)
	case errors.Is(err, journal.ErrSigningKeyNotFound):
		http.Error(w, "active signing key not found", http.StatusConflict)
	default:
		log.Printf("journal handler error: %v", err)
		http.Error(w, "failed to process journal", http.StatusInternalServerError)
	}
}
