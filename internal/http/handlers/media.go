package handlers

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"inkconnect/internal/config"
	"inkconnect/internal/media"
	"inkconnect/internal/users"
)

type MediaHandler struct {
	authService    *users.AuthenticationService
	profileService *users.ProfileService
	mediaService   *media.Service
	cookieName     string
}

func NewMediaHandler(cfg config.Config, authService *users.AuthenticationService, profileService *users.ProfileService, mediaService *media.Service) *MediaHandler {
	return &MediaHandler{
		authService:    authService,
		profileService: profileService,
		mediaService:   mediaService,
		cookieName:     cfg.SessionCookieName,
	}
}

func (h *MediaHandler) ServeCurrentAvatarHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		h.UploadCurrentAvatarJSON(w, r)
	case http.MethodDelete:
		h.DeleteCurrentAvatarJSON(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *MediaHandler) UploadCurrentAvatarJSON(w http.ResponseWriter, r *http.Request) {
	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	if h.mediaService == nil {
		http.Error(w, "storage is unavailable", http.StatusServiceUnavailable)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, media.MaxAvatarBytes+1024*1024)
	file, header, err := r.FormFile("file")
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "too large") {
			http.Error(w, "file is too large", http.StatusRequestEntityTooLarge)
			return
		}
		http.Error(w, "file is required", http.StatusBadRequest)
		return
	}
	defer file.Close()

	if header.Size <= 0 {
		http.Error(w, "file is required", http.StatusBadRequest)
		return
	}
	if header.Size > media.MaxAvatarBytes {
		http.Error(w, "file is too large", http.StatusRequestEntityTooLarge)
		return
	}

	head := make([]byte, 512)
	n, err := file.Read(head)
	if err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, "failed to read file", http.StatusBadRequest)
		return
	}
	if n == 0 {
		http.Error(w, "file is required", http.StatusBadRequest)
		return
	}

	contentType, extension, ok := detectAvatarImage(head[:n])
	if !ok {
		http.Error(w, "unsupported avatar image type", http.StatusUnsupportedMediaType)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	_, err = h.mediaService.UploadUserAvatar(ctx, user.ID, media.AvatarUpload{
		Reader:      io.MultiReader(bytes.NewReader(head[:n]), file),
		SizeBytes:   header.Size,
		ContentType: contentType,
		Extension:   extension,
	})
	if err != nil {
		writeAvatarMutationError(w, err)
		return
	}

	profile, err := h.profileService.GetProfile(ctx, user.ID)
	if err != nil {
		writeAvatarMutationError(w, err)
		return
	}

	writeProfileJSON(w, profile)
}

func (h *MediaHandler) DeleteCurrentAvatarJSON(w http.ResponseWriter, r *http.Request) {
	user, err := h.authenticateRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	if h.mediaService == nil {
		http.Error(w, "storage is unavailable", http.StatusServiceUnavailable)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	if err := h.mediaService.DeleteUserAvatar(ctx, user.ID); err != nil {
		writeAvatarMutationError(w, err)
		return
	}

	profile, err := h.profileService.GetProfile(ctx, user.ID)
	if err != nil {
		writeAvatarMutationError(w, err)
		return
	}

	writeProfileJSON(w, profile)
}

func (h *MediaHandler) ServeObjectHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if h.mediaService == nil {
		http.Error(w, "storage is unavailable", http.StatusServiceUnavailable)
		return
	}

	mediaID := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/media/"), "/")
	if mediaID == "" || strings.Contains(mediaID, "/") {
		http.NotFound(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	object, err := h.mediaService.OpenPublicObject(ctx, mediaID)
	if err != nil {
		switch {
		case errors.Is(err, media.ErrMediaNotFound):
			http.NotFound(w, r)
		case errors.Is(err, media.ErrStorageUnavailable):
			http.Error(w, "storage is unavailable", http.StatusServiceUnavailable)
		default:
			http.Error(w, "failed to load media object", http.StatusInternalServerError)
		}
		return
	}
	defer object.Body.Close()

	w.Header().Set("Content-Type", object.Media.ContentType)
	w.Header().Set("Cache-Control", "public, max-age=300")
	if object.Size > 0 {
		w.Header().Set("Content-Length", strconv.FormatInt(object.Size, 10))
	}
	_, _ = io.Copy(w, object.Body)
}

func (h *MediaHandler) authenticateRequest(r *http.Request) (users.AuthenticatedUser, error) {
	token := h.sessionTokenFromRequest(r)
	if strings.TrimSpace(token) == "" {
		return users.AuthenticatedUser{}, users.ErrSessionNotFound
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	return h.authService.Authenticate(ctx, token)
}

func (h *MediaHandler) sessionTokenFromRequest(r *http.Request) string {
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

func detectAvatarImage(head []byte) (string, string, bool) {
	if isWebP(head) {
		return "image/webp", "webp", true
	}

	switch http.DetectContentType(head) {
	case "image/jpeg":
		return "image/jpeg", "jpg", true
	case "image/png":
		return "image/png", "png", true
	default:
		return "", "", false
	}
}

func isWebP(head []byte) bool {
	return len(head) >= 12 &&
		string(head[0:4]) == "RIFF" &&
		string(head[8:12]) == "WEBP"
}

func writeAvatarMutationError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, media.ErrFileRequired):
		http.Error(w, "file is required", http.StatusBadRequest)
	case errors.Is(err, media.ErrFileTooLarge):
		http.Error(w, "file is too large", http.StatusRequestEntityTooLarge)
	case errors.Is(err, media.ErrUnsupportedContentType):
		http.Error(w, "unsupported avatar image type", http.StatusUnsupportedMediaType)
	case errors.Is(err, media.ErrStorageUnavailable):
		http.Error(w, "storage is unavailable", http.StatusServiceUnavailable)
	case errors.Is(err, users.ErrUserNotFound), errors.Is(err, media.ErrOwnerNotFound):
		http.Error(w, "profile not found", http.StatusNotFound)
	default:
		http.Error(w, "failed to update avatar", http.StatusInternalServerError)
	}
}
