package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"inkconnect/internal/chat"
	"inkconnect/internal/config"
	"inkconnect/internal/users"
)

type ChatHandler struct {
	cookieName  string
	authService *users.AuthenticationService
	service     *chat.Service
}

func NewChatHandler(cfg config.Config, authService *users.AuthenticationService, service *chat.Service) *ChatHandler {
	return &ChatHandler{
		cookieName:  cfg.SessionCookieName,
		authService: authService,
		service:     service,
	}
}

func (h *ChatHandler) ServeCollectionHTTP(w http.ResponseWriter, r *http.Request) {
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

	threads, err := h.service.ListThreads(ctx, user.ID)
	if err != nil {
		http.Error(w, "Не удалось загрузить сообщения", http.StatusInternalServerError)
		return
	}
	writeChatJSON(w, http.StatusOK, map[string]any{"items": threads})
}

func (h *ChatHandler) ServeWithUserHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}

	participantID := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/chats/with/"), "/")
	if participantID == "" || strings.Contains(participantID, "/") {
		http.NotFound(w, r)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	thread, err := h.service.GetOrCreateThread(ctx, user.ID, participantID)
	if err != nil {
		h.writeChatError(w, err)
		return
	}
	writeChatJSON(w, http.StatusOK, map[string]any{"thread": thread})
}

func (h *ChatHandler) ServeThreadHTTP(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}

	path := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/chats/"), "/")
	parts := strings.Split(path, "/")
	if len(parts) == 2 && parts[1] == "messages" {
		switch r.Method {
		case http.MethodGet:
			h.listMessagesHTTP(w, r, user.ID, parts[0])
		case http.MethodPost:
			h.sendMessageHTTP(w, r, user.ID, parts[0])
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
		return
	}
	if len(parts) == 3 && parts[1] == "messages" {
		switch r.Method {
		case http.MethodPatch:
			h.editMessageHTTP(w, r, user.ID, parts[0], parts[2])
		case http.MethodDelete:
			h.deleteMessageHTTP(w, r, user.ID, parts[0], parts[2])
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
		return
	}
	http.NotFound(w, r)
}

func (h *ChatHandler) listMessagesHTTP(w http.ResponseWriter, r *http.Request, userID string, threadID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	messages, err := h.service.ListMessages(ctx, userID, threadID)
	if err != nil {
		h.writeChatError(w, err)
		return
	}
	writeChatJSON(w, http.StatusOK, map[string]any{"items": messages})
}

func (h *ChatHandler) sendMessageHTTP(w http.ResponseWriter, r *http.Request, userID string, threadID string) {
	body, ok := h.decodeMessageBody(w, r)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	message, err := h.service.SendMessage(ctx, userID, threadID, body)
	if err != nil {
		h.writeChatError(w, err)
		return
	}
	writeChatJSON(w, http.StatusCreated, map[string]any{"message": message})
}

func (h *ChatHandler) editMessageHTTP(w http.ResponseWriter, r *http.Request, userID string, threadID string, messageID string) {
	body, ok := h.decodeMessageBody(w, r)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	message, err := h.service.EditMessage(ctx, userID, threadID, messageID, body)
	if err != nil {
		h.writeChatError(w, err)
		return
	}
	writeChatJSON(w, http.StatusOK, map[string]any{"message": message})
}

func (h *ChatHandler) deleteMessageHTTP(w http.ResponseWriter, r *http.Request, userID string, threadID string, messageID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	message, err := h.service.DeleteMessage(ctx, userID, threadID, messageID)
	if err != nil {
		h.writeChatError(w, err)
		return
	}
	writeChatJSON(w, http.StatusOK, map[string]any{"message": message})
}

func (h *ChatHandler) decodeMessageBody(w http.ResponseWriter, r *http.Request) (string, bool) {
	var payload struct {
		Body string `json:"body"`
		Text string `json:"text"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		http.Error(w, "Некорректный текст сообщения", http.StatusBadRequest)
		return "", false
	}
	body := payload.Body
	if strings.TrimSpace(body) == "" {
		body = payload.Text
	}
	return body, true
}

func (h *ChatHandler) writeChatError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, chat.ErrCannotMessageSelf):
		http.Error(w, "Нельзя открыть чат с самим собой", http.StatusForbidden)
	case errors.Is(err, chat.ErrInvalidMessage):
		http.Error(w, "Введите сообщение от 1 до 2000 символов", http.StatusBadRequest)
	case errors.Is(err, chat.ErrUserNotFound), errors.Is(err, chat.ErrThreadNotFound), errors.Is(err, chat.ErrMessageNotFound):
		http.Error(w, "Диалог или сообщение не найдено", http.StatusNotFound)
	case errors.Is(err, chat.ErrForbidden):
		http.Error(w, "Нет доступа к этому диалогу", http.StatusForbidden)
	default:
		http.Error(w, "Не удалось выполнить действие с сообщением", http.StatusInternalServerError)
	}
}

func (h *ChatHandler) authenticate(w http.ResponseWriter, r *http.Request) (users.AuthenticatedUser, bool) {
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

func (h *ChatHandler) sessionTokenFromRequest(r *http.Request) string {
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

func writeChatJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
