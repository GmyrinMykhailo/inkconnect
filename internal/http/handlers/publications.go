package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"inkconnect/internal/config"
	"inkconnect/internal/publications"
	"inkconnect/internal/users"
)

const publicationMultipartOverheadBytes = 10 * 1024 * 1024

type PublicationsHandler struct {
	authService *users.AuthenticationService
	service     *publications.Service
	cookieName  string
}

func NewPublicationsHandler(cfg config.Config, authService *users.AuthenticationService, service *publications.Service) *PublicationsHandler {
	return &PublicationsHandler{
		authService: authService,
		service:     service,
		cookieName:  cfg.SessionCookieName,
	}
}

func (h *PublicationsHandler) ServeCurrentMasterCollectionHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	h.CreateCurrentMasterPublicationJSON(w, r)
}

func (h *PublicationsHandler) ServeCurrentMasterItemHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	publicationID := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/master/publications/"), "/")
	if publicationID == "" || strings.Contains(publicationID, "/") {
		http.NotFound(w, r)
		return
	}

	h.DeleteCurrentMasterPublicationJSON(w, r, publicationID)
}

func (h *PublicationsHandler) ServeMasterPublicationsHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if h.service == nil {
		http.Error(w, "publication service is unavailable", http.StatusServiceUnavailable)
		return
	}

	path := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/masters/"), "/")
	parts := strings.Split(path, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] != "publications" {
		http.NotFound(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	items, err := h.service.ListByMasterUsername(ctx, parts[0])
	if err != nil {
		writePublicationReadError(w, err)
		return
	}

	writeJSON(w, map[string]any{
		"items": items,
	})
}

func (h *PublicationsHandler) ServePublicationHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if h.service == nil {
		http.Error(w, "publication service is unavailable", http.StatusServiceUnavailable)
		return
	}

	publicationID := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/publications/"), "/")
	if publicationID == "" || strings.Contains(publicationID, "/") {
		http.NotFound(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	publication, err := h.service.Get(ctx, publicationID)
	if err != nil {
		writePublicationReadError(w, err)
		return
	}

	writeJSON(w, map[string]any{
		"publication": publication,
	})
}

func (h *PublicationsHandler) CreateCurrentMasterPublicationJSON(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	if h.service == nil {
		http.Error(w, "publication service is unavailable", http.StatusServiceUnavailable)
		return
	}

	input, cleanup, ok := decodePublicationMultipart(w, r)
	if cleanup != nil {
		defer cleanup()
	}
	if !ok {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
	defer cancel()

	publication, err := h.service.CreateWithPhotos(ctx, user.ID, input)
	if err != nil {
		writePublicationError(w, err)
		return
	}

	writeJSONStatus(w, http.StatusCreated, map[string]any{
		"publication": publication,
	})
}

func (h *PublicationsHandler) DeleteCurrentMasterPublicationJSON(w http.ResponseWriter, r *http.Request, publicationID string) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	if h.service == nil {
		http.Error(w, "publication service is unavailable", http.StatusServiceUnavailable)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	if err := h.service.Delete(ctx, user.ID, publicationID); err != nil {
		writePublicationDeleteError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *PublicationsHandler) authenticate(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
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

func (h *PublicationsHandler) sessionTokenFromRequest(r *http.Request) string {
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

func decodePublicationMultipart(w http.ResponseWriter, r *http.Request) (publications.CreatePublicationWithPhotosInput, func(), bool) {
	maxBodyBytes := int64(publications.MaxPublicationPhotos*publications.MaxPublicationPhotoBytes + publicationMultipartOverheadBytes)
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	if err := r.ParseMultipartForm(8 << 20); err != nil {
		if isMultipartTooLargeError(err) {
			http.Error(w, "publication payload is too large", http.StatusBadRequest)
			return publications.CreatePublicationWithPhotosInput{}, nil, false
		}
		http.Error(w, "invalid publication multipart payload", http.StatusBadRequest)
		return publications.CreatePublicationWithPhotosInput{}, nil, false
	}

	cleanup := func() {
		if r.MultipartForm != nil {
			_ = r.MultipartForm.RemoveAll()
		}
	}

	if r.MultipartForm == nil {
		http.Error(w, "photo is required", http.StatusBadRequest)
		return publications.CreatePublicationWithPhotosInput{}, cleanup, false
	}

	fileHeaders := r.MultipartForm.File["photos"]
	if len(fileHeaders) == 0 {
		http.Error(w, "photo is required", http.StatusBadRequest)
		return publications.CreatePublicationWithPhotosInput{}, cleanup, false
	}
	if len(fileHeaders) > publications.MaxPublicationPhotos {
		http.Error(w, "publication has too many photos", http.StatusBadRequest)
		return publications.CreatePublicationWithPhotosInput{}, cleanup, false
	}

	photos := make([]publications.PublicationPhotoUpload, 0, len(fileHeaders))
	openedFiles := make([]io.Closer, 0, len(fileHeaders))
	cleanupFiles := func() {
		for _, file := range openedFiles {
			_ = file.Close()
		}
		cleanup()
	}

	for _, header := range fileHeaders {
		if header.Size <= 0 {
			cleanupFiles()
			http.Error(w, "photo is required", http.StatusBadRequest)
			return publications.CreatePublicationWithPhotosInput{}, nil, false
		}
		if header.Size > publications.MaxPublicationPhotoBytes {
			cleanupFiles()
			http.Error(w, "photo is too large", http.StatusBadRequest)
			return publications.CreatePublicationWithPhotosInput{}, nil, false
		}

		file, err := header.Open()
		if err != nil {
			cleanupFiles()
			http.Error(w, "failed to read publication photo", http.StatusBadRequest)
			return publications.CreatePublicationWithPhotosInput{}, nil, false
		}
		openedFiles = append(openedFiles, file)
		photos = append(photos, publications.PublicationPhotoUpload{
			Reader:    file,
			SizeBytes: header.Size,
		})
	}

	commentsDisabled, ok := parseOptionalBool(w, r.FormValue("comments_disabled"), "comments_disabled")
	if !ok {
		cleanupFiles()
		return publications.CreatePublicationWithPhotosInput{}, nil, false
	}

	styles, ok := parsePublicationStyles(w, r.FormValue("styles_json"))
	if !ok {
		cleanupFiles()
		return publications.CreatePublicationWithPhotosInput{}, nil, false
	}

	return publications.CreatePublicationWithPhotosInput{
		Description:      r.FormValue("description"),
		Styles:           styles,
		CommentsDisabled: commentsDisabled,
		Photos:           photos,
	}, cleanupFiles, true
}

func parsePublicationStyles(w http.ResponseWriter, raw string) ([]string, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return []string{}, true
	}

	var styles []string
	if err := json.Unmarshal([]byte(raw), &styles); err != nil {
		normalized := strings.ReplaceAll(raw, `\"`, `"`)
		if normalized == raw || json.Unmarshal([]byte(normalized), &styles) != nil {
			looseStyles, ok := parseBracketedStyleList(raw)
			if ok {
				return looseStyles, true
			}
			http.Error(w, "invalid styles_json", http.StatusBadRequest)
			return nil, false
		}
	}

	if styles == nil {
		styles = []string{}
	}

	return styles, true
}

func parseBracketedStyleList(raw string) ([]string, bool) {
	raw = strings.TrimSpace(strings.ReplaceAll(raw, `\"`, `"`))
	if !strings.HasPrefix(raw, "[") || !strings.HasSuffix(raw, "]") {
		return nil, false
	}

	body := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(raw, "["), "]"))
	if body == "" {
		return []string{}, true
	}

	parts := strings.Split(body, ",")
	styles := make([]string, 0, len(parts))
	for _, part := range parts {
		style := strings.TrimSpace(part)
		style = strings.Trim(style, `"`)
		style = strings.TrimSpace(style)
		if style == "" {
			return nil, false
		}
		styles = append(styles, style)
	}

	return styles, true
}

func parseOptionalBool(w http.ResponseWriter, raw string, field string) (bool, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return false, true
	}

	parsed, err := strconv.ParseBool(raw)
	if err != nil {
		http.Error(w, "invalid "+field, http.StatusBadRequest)
		return false, false
	}

	return parsed, true
}

func isMultipartTooLargeError(err error) bool {
	if err == nil {
		return false
	}

	message := strings.ToLower(err.Error())
	return strings.Contains(message, "request body too large") ||
		strings.Contains(message, "multipart: message too large") ||
		strings.Contains(message, "http: request body too large")
}

func writePublicationError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, publications.ErrPublicationMasterOnly),
		errors.Is(err, publications.ErrPublicationForbidden):
		http.Error(w, "master role required", http.StatusForbidden)
	case errors.Is(err, publications.ErrPublicationPhotoRequired),
		errors.Is(err, publications.ErrPublicationTooManyPhotos),
		errors.Is(err, publications.ErrPublicationInvalidInput),
		errors.Is(err, publications.ErrPublicationUnsupportedContent),
		errors.Is(err, publications.ErrPublicationFileRequired),
		errors.Is(err, publications.ErrPublicationFileTooLarge):
		http.Error(w, err.Error(), http.StatusBadRequest)
	case errors.Is(err, publications.ErrPublicationStorageUnavailable):
		http.Error(w, "storage is unavailable", http.StatusServiceUnavailable)
	default:
		http.Error(w, "failed to create publication", http.StatusInternalServerError)
	}
}

func writePublicationReadError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, publications.ErrPublicationNotFound):
		http.Error(w, "publication not found", http.StatusNotFound)
	default:
		http.Error(w, "failed to load publications", http.StatusInternalServerError)
	}
}

func writePublicationDeleteError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, publications.ErrPublicationNotFound):
		http.Error(w, "publication not found", http.StatusNotFound)
	case errors.Is(err, publications.ErrPublicationMasterOnly),
		errors.Is(err, publications.ErrPublicationForbidden):
		http.Error(w, "master role required", http.StatusForbidden)
	default:
		http.Error(w, "failed to delete publication", http.StatusInternalServerError)
	}
}
