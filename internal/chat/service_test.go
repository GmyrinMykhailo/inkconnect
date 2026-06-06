package chat

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

type fakeChatRepository struct {
	getOrCreateResult StoredThreadSummary
	getOrCreateErr    error
	getOrCreateCalled int
	getOrCreateUserID string
	getOrCreatePeerID string

	listThreadsResult []StoredThreadSummary
	listThreadsErr    error
	listThreadsCalled int
	listThreadsUserID string

	listMessagesResult []StoredMessage
	listMessagesErr    error
	listMessagesCalled int
	listMessagesUserID string
	listMessagesThread string

	createMessageErr       error
	createMessageCalled    int
	createMessageUserID    string
	createMessageThreadID  string
	createMessageEncrypted string
	createMessageNonce     string
	createMessageBodyHash  string

	updateMessageErr       error
	updateMessageCalled    int
	updateMessageUserID    string
	updateMessageThreadID  string
	updateMessageID        string
	updateMessageEncrypted string
	updateMessageNonce     string
	updateMessageBodyHash  string

	deleteMessageResult   StoredMessage
	deleteMessageErr      error
	deleteMessageCalled   int
	deleteMessageUserID   string
	deleteMessageThreadID string
	deleteMessageID       string
}

func (r *fakeChatRepository) GetOrCreateThread(ctx context.Context, userID string, participantID string) (StoredThreadSummary, error) {
	r.getOrCreateCalled++
	r.getOrCreateUserID = userID
	r.getOrCreatePeerID = participantID
	if r.getOrCreateErr != nil {
		return StoredThreadSummary{}, r.getOrCreateErr
	}
	return r.getOrCreateResult, nil
}

func (r *fakeChatRepository) ListThreads(ctx context.Context, userID string) ([]StoredThreadSummary, error) {
	r.listThreadsCalled++
	r.listThreadsUserID = userID
	if r.listThreadsErr != nil {
		return nil, r.listThreadsErr
	}
	return r.listThreadsResult, nil
}

func (r *fakeChatRepository) ListMessages(ctx context.Context, userID string, threadID string) ([]StoredMessage, error) {
	r.listMessagesCalled++
	r.listMessagesUserID = userID
	r.listMessagesThread = threadID
	if r.listMessagesErr != nil {
		return nil, r.listMessagesErr
	}
	return r.listMessagesResult, nil
}

func (r *fakeChatRepository) CreateMessage(ctx context.Context, userID string, threadID string, encryptedBody string, nonce string, bodyHash string) (StoredMessage, error) {
	r.createMessageCalled++
	r.createMessageUserID = userID
	r.createMessageThreadID = threadID
	r.createMessageEncrypted = encryptedBody
	r.createMessageNonce = nonce
	r.createMessageBodyHash = bodyHash
	if r.createMessageErr != nil {
		return StoredMessage{}, r.createMessageErr
	}
	return StoredMessage{
		ID:            "message-1",
		ThreadID:      threadID,
		SenderID:      userID,
		EncryptedBody: encryptedBody,
		Nonce:         nonce,
		Status:        MessageStatusSent,
		CreatedAt:     fixedChatTime(),
		UpdatedAt:     fixedChatTime(),
	}, nil
}

func (r *fakeChatRepository) UpdateMessage(ctx context.Context, userID string, threadID string, messageID string, encryptedBody string, nonce string, bodyHash string) (StoredMessage, error) {
	r.updateMessageCalled++
	r.updateMessageUserID = userID
	r.updateMessageThreadID = threadID
	r.updateMessageID = messageID
	r.updateMessageEncrypted = encryptedBody
	r.updateMessageNonce = nonce
	r.updateMessageBodyHash = bodyHash
	if r.updateMessageErr != nil {
		return StoredMessage{}, r.updateMessageErr
	}
	editedAt := fixedChatTime().Add(2 * time.Minute)
	return StoredMessage{
		ID:            messageID,
		ThreadID:      threadID,
		SenderID:      userID,
		EncryptedBody: encryptedBody,
		Nonce:         nonce,
		Status:        MessageStatusSent,
		CreatedAt:     fixedChatTime(),
		UpdatedAt:     editedAt,
		EditedAt:      &editedAt,
	}, nil
}

func (r *fakeChatRepository) DeleteMessage(ctx context.Context, userID string, threadID string, messageID string) (StoredMessage, error) {
	r.deleteMessageCalled++
	r.deleteMessageUserID = userID
	r.deleteMessageThreadID = threadID
	r.deleteMessageID = messageID
	if r.deleteMessageErr != nil {
		return StoredMessage{}, r.deleteMessageErr
	}
	if r.deleteMessageResult.ID != "" {
		return r.deleteMessageResult, nil
	}
	return StoredMessage{
		ID:        messageID,
		ThreadID:  threadID,
		SenderID:  userID,
		Status:    MessageStatusSent,
		CreatedAt: fixedChatTime(),
		UpdatedAt: fixedChatTime(),
		IsDeleted: true,
	}, nil
}

func TestServiceGetOrCreateThreadTrimsIDsAndDelegates(t *testing.T) {
	repo := &fakeChatRepository{
		getOrCreateResult: StoredThreadSummary{
			ID:        "thread-1",
			UpdatedAt: fixedChatTime(),
			Participant: Participant{
				ID:          "user-2",
				Username:    "artist",
				DisplayName: "Artist",
				Role:        "master",
			},
		},
	}
	service, _ := newTestChatService(t, repo)

	thread, err := service.GetOrCreateThread(context.Background(), " user-1 ", " user-2 ")
	if err != nil {
		t.Fatalf("get or create thread: %v", err)
	}
	if repo.getOrCreateCalled != 1 {
		t.Fatalf("expected repository call, got %d", repo.getOrCreateCalled)
	}
	if repo.getOrCreateUserID != "user-1" || repo.getOrCreatePeerID != "user-2" {
		t.Fatalf("ids were not trimmed: user=%q peer=%q", repo.getOrCreateUserID, repo.getOrCreatePeerID)
	}
	if thread.ID != "thread-1" || thread.Participant.ID != "user-2" {
		t.Fatalf("unexpected thread: %+v", thread)
	}
}

func TestServiceGetOrCreateThreadRejectsInvalidParticipants(t *testing.T) {
	tests := []struct {
		name          string
		userID        string
		participantID string
		wantErr       error
	}{
		{name: "empty user", userID: " ", participantID: "user-2", wantErr: ErrUserNotFound},
		{name: "empty participant", userID: "user-1", participantID: " ", wantErr: ErrUserNotFound},
		{name: "self", userID: "user-1", participantID: " user-1 ", wantErr: ErrCannotMessageSelf},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &fakeChatRepository{}
			service, _ := newTestChatService(t, repo)

			_, err := service.GetOrCreateThread(context.Background(), tt.userID, tt.participantID)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("expected %v, got %v", tt.wantErr, err)
			}
			if repo.getOrCreateCalled != 0 {
				t.Fatalf("repository should not be called")
			}
		})
	}
}

func TestServiceListThreadsDecryptsLastMessagePreview(t *testing.T) {
	repo := &fakeChatRepository{}
	service, cipher := newTestChatService(t, repo)
	encrypted, nonce := encryptedChatBody(t, cipher, "Привет, запись подтверждена")
	lastMessageAt := fixedChatTime()
	repo.listThreadsResult = []StoredThreadSummary{{
		ID:                   "thread-1",
		Participant:          Participant{ID: "user-2", Username: "master"},
		LastMessageEncrypted: encrypted,
		LastMessageNonce:     nonce,
		LastMessageAt:        &lastMessageAt,
		UpdatedAt:            fixedChatTime(),
	}}

	threads, err := service.ListThreads(context.Background(), " user-1 ")
	if err != nil {
		t.Fatalf("list threads: %v", err)
	}
	if repo.listThreadsUserID != "user-1" {
		t.Fatalf("expected trimmed user id, got %q", repo.listThreadsUserID)
	}
	if len(threads) != 1 || threads[0].LastMessagePreview != "Привет, запись подтверждена" {
		t.Fatalf("unexpected preview: %+v", threads)
	}
}

func TestServiceListThreadsUsesDeletedPreviewWithoutDecrypt(t *testing.T) {
	repo := &fakeChatRepository{}
	service, _ := newTestChatService(t, repo)
	lastMessageAt := fixedChatTime()
	repo.listThreadsResult = []StoredThreadSummary{{
		ID:                   "thread-1",
		LastMessageEncrypted: "not-base64",
		LastMessageNonce:     "not-base64",
		LastMessageDeleted:   true,
		LastMessageAt:        &lastMessageAt,
		UpdatedAt:            fixedChatTime(),
	}}

	threads, err := service.ListThreads(context.Background(), "user-1")
	if err != nil {
		t.Fatalf("list threads: %v", err)
	}
	if len(threads) != 1 || strings.TrimSpace(threads[0].LastMessagePreview) == "" {
		t.Fatalf("expected deleted message preview, got %+v", threads)
	}
}

func TestServiceListThreadsTruncatesLongPreview(t *testing.T) {
	repo := &fakeChatRepository{}
	service, cipher := newTestChatService(t, repo)
	body := strings.Repeat("я", 130)
	encrypted, nonce := encryptedChatBody(t, cipher, body)
	lastMessageAt := fixedChatTime()
	repo.listThreadsResult = []StoredThreadSummary{{
		ID:                   "thread-1",
		LastMessageEncrypted: encrypted,
		LastMessageNonce:     nonce,
		LastMessageAt:        &lastMessageAt,
		UpdatedAt:            fixedChatTime(),
	}}

	threads, err := service.ListThreads(context.Background(), "user-1")
	if err != nil {
		t.Fatalf("list threads: %v", err)
	}
	preview := threads[0].LastMessagePreview
	if len([]rune(preview)) != 123 || !strings.HasSuffix(preview, "...") {
		t.Fatalf("expected truncated preview, got %q (%d runes)", preview, len([]rune(preview)))
	}
}

func TestServiceListMessagesDecryptsMessages(t *testing.T) {
	repo := &fakeChatRepository{}
	service, cipher := newTestChatService(t, repo)
	firstEncrypted, firstNonce := encryptedChatBody(t, cipher, "Первое сообщение")
	secondEncrypted, secondNonce := encryptedChatBody(t, cipher, "Ответ мастера")
	repo.listMessagesResult = []StoredMessage{
		storedChatMessage("message-1", "thread-1", "user-1", firstEncrypted, firstNonce),
		storedChatMessage("message-2", "thread-1", "user-2", secondEncrypted, secondNonce),
	}

	messages, err := service.ListMessages(context.Background(), " user-1 ", " thread-1 ")
	if err != nil {
		t.Fatalf("list messages: %v", err)
	}
	if repo.listMessagesUserID != "user-1" || repo.listMessagesThread != "thread-1" {
		t.Fatalf("expected trimmed params, got user=%q thread=%q", repo.listMessagesUserID, repo.listMessagesThread)
	}
	if len(messages) != 2 || messages[0].Body != "Первое сообщение" || messages[1].Body != "Ответ мастера" {
		t.Fatalf("unexpected messages: %+v", messages)
	}
}

func TestServiceListMessagesReturnsDecryptError(t *testing.T) {
	repo := &fakeChatRepository{
		listMessagesResult: []StoredMessage{{
			ID:            "message-1",
			ThreadID:      "thread-1",
			SenderID:      "user-1",
			EncryptedBody: "not-base64",
			Nonce:         "not-base64",
			Status:        MessageStatusSent,
			CreatedAt:     fixedChatTime(),
			UpdatedAt:     fixedChatTime(),
		}},
	}
	service, _ := newTestChatService(t, repo)

	_, err := service.ListMessages(context.Background(), "user-1", "thread-1")
	if err == nil {
		t.Fatal("expected decrypt error")
	}
}

func TestServiceSendMessageEncryptsAndStoresChecksum(t *testing.T) {
	repo := &fakeChatRepository{}
	service, cipher := newTestChatService(t, repo)

	message, err := service.SendMessage(context.Background(), " user-1 ", " thread-1 ", "  Привет  ")
	if err != nil {
		t.Fatalf("send message: %v", err)
	}
	if repo.createMessageCalled != 1 {
		t.Fatalf("expected create call, got %d", repo.createMessageCalled)
	}
	if repo.createMessageUserID != "user-1" || repo.createMessageThreadID != "thread-1" {
		t.Fatalf("expected trimmed params, got user=%q thread=%q", repo.createMessageUserID, repo.createMessageThreadID)
	}
	if repo.createMessageEncrypted == "" || repo.createMessageNonce == "" {
		t.Fatal("expected encrypted body and nonce")
	}
	if strings.Contains(repo.createMessageEncrypted, "Привет") {
		t.Fatalf("encrypted body should not contain plaintext: %q", repo.createMessageEncrypted)
	}
	decrypted, err := cipher.Decrypt(repo.createMessageEncrypted, repo.createMessageNonce)
	if err != nil {
		t.Fatalf("decrypt stored body: %v", err)
	}
	if decrypted != "Привет" {
		t.Fatalf("expected normalized plaintext, got %q", decrypted)
	}
	if repo.createMessageBodyHash != bodyChecksum("Привет") {
		t.Fatalf("unexpected body checksum: %q", repo.createMessageBodyHash)
	}
	if message.Body != "Привет" {
		t.Fatalf("expected decrypted response body, got %q", message.Body)
	}
}

func TestServiceSendMessageRejectsInvalidBody(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{name: "empty", body: "   "},
		{name: "too long", body: strings.Repeat("я", maxMessageLength+1)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &fakeChatRepository{}
			service, _ := newTestChatService(t, repo)

			_, err := service.SendMessage(context.Background(), "user-1", "thread-1", tt.body)
			if !errors.Is(err, ErrInvalidMessage) {
				t.Fatalf("expected ErrInvalidMessage, got %v", err)
			}
			if repo.createMessageCalled != 0 {
				t.Fatal("repository should not be called")
			}
		})
	}
}

func TestServiceEditMessageEncryptsUpdatedBody(t *testing.T) {
	repo := &fakeChatRepository{}
	service, cipher := newTestChatService(t, repo)

	message, err := service.EditMessage(context.Background(), " user-1 ", " thread-1 ", " message-1 ", "  Обновлено  ")
	if err != nil {
		t.Fatalf("edit message: %v", err)
	}
	if repo.updateMessageCalled != 1 {
		t.Fatalf("expected update call, got %d", repo.updateMessageCalled)
	}
	if repo.updateMessageUserID != "user-1" || repo.updateMessageThreadID != "thread-1" || repo.updateMessageID != "message-1" {
		t.Fatalf("expected trimmed params, got user=%q thread=%q message=%q", repo.updateMessageUserID, repo.updateMessageThreadID, repo.updateMessageID)
	}
	decrypted, err := cipher.Decrypt(repo.updateMessageEncrypted, repo.updateMessageNonce)
	if err != nil {
		t.Fatalf("decrypt updated body: %v", err)
	}
	if decrypted != "Обновлено" {
		t.Fatalf("expected normalized body, got %q", decrypted)
	}
	if repo.updateMessageBodyHash != bodyChecksum("Обновлено") {
		t.Fatalf("unexpected update checksum: %q", repo.updateMessageBodyHash)
	}
	if message.Body != "Обновлено" || message.EditedAt == nil {
		t.Fatalf("unexpected edited message: %+v", message)
	}
}

func TestServiceEditMessageRejectsInvalidBody(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{name: "empty", body: "\n\t"},
		{name: "too long", body: strings.Repeat("x", maxMessageLength+1)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &fakeChatRepository{}
			service, _ := newTestChatService(t, repo)

			_, err := service.EditMessage(context.Background(), "user-1", "thread-1", "message-1", tt.body)
			if !errors.Is(err, ErrInvalidMessage) {
				t.Fatalf("expected ErrInvalidMessage, got %v", err)
			}
			if repo.updateMessageCalled != 0 {
				t.Fatal("repository should not be called")
			}
		})
	}
}

func TestServiceDeleteMessageDelegatesAndReturnsDeletedMessage(t *testing.T) {
	repo := &fakeChatRepository{}
	service, _ := newTestChatService(t, repo)

	message, err := service.DeleteMessage(context.Background(), " user-1 ", " thread-1 ", " message-1 ")
	if err != nil {
		t.Fatalf("delete message: %v", err)
	}
	if repo.deleteMessageCalled != 1 {
		t.Fatalf("expected delete call, got %d", repo.deleteMessageCalled)
	}
	if repo.deleteMessageUserID != "user-1" || repo.deleteMessageThreadID != "thread-1" || repo.deleteMessageID != "message-1" {
		t.Fatalf("expected trimmed params, got user=%q thread=%q message=%q", repo.deleteMessageUserID, repo.deleteMessageThreadID, repo.deleteMessageID)
	}
	if !message.IsDeleted || strings.TrimSpace(message.Body) == "" {
		t.Fatalf("expected deleted message placeholder, got %+v", message)
	}
}

func TestServicePropagatesRepositoryErrors(t *testing.T) {
	tests := []struct {
		name string
		run  func(*Service) error
		err  error
		repo *fakeChatRepository
	}{
		{
			name: "list threads",
			repo: &fakeChatRepository{listThreadsErr: ErrForbidden},
			err:  ErrForbidden,
			run: func(service *Service) error {
				_, err := service.ListThreads(context.Background(), "user-1")
				return err
			},
		},
		{
			name: "list messages",
			repo: &fakeChatRepository{listMessagesErr: ErrThreadNotFound},
			err:  ErrThreadNotFound,
			run: func(service *Service) error {
				_, err := service.ListMessages(context.Background(), "user-1", "thread-1")
				return err
			},
		},
		{
			name: "send",
			repo: &fakeChatRepository{createMessageErr: ErrForbidden},
			err:  ErrForbidden,
			run: func(service *Service) error {
				_, err := service.SendMessage(context.Background(), "user-1", "thread-1", "hello")
				return err
			},
		},
		{
			name: "edit",
			repo: &fakeChatRepository{updateMessageErr: ErrMessageNotFound},
			err:  ErrMessageNotFound,
			run: func(service *Service) error {
				_, err := service.EditMessage(context.Background(), "user-1", "thread-1", "message-1", "hello")
				return err
			},
		},
		{
			name: "delete",
			repo: &fakeChatRepository{deleteMessageErr: ErrMessageNotFound},
			err:  ErrMessageNotFound,
			run: func(service *Service) error {
				_, err := service.DeleteMessage(context.Background(), "user-1", "thread-1", "message-1")
				return err
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service, _ := newTestChatService(t, tt.repo)

			err := tt.run(service)
			if !errors.Is(err, tt.err) {
				t.Fatalf("expected %v, got %v", tt.err, err)
			}
		})
	}
}

func TestNormalizeBodyAndBodyChecksum(t *testing.T) {
	normalized, err := normalizeBody("  текст сообщения  ")
	if err != nil {
		t.Fatalf("normalize body: %v", err)
	}
	if normalized != "текст сообщения" {
		t.Fatalf("unexpected normalized body: %q", normalized)
	}

	if _, err := normalizeBody(" "); !errors.Is(err, ErrInvalidMessage) {
		t.Fatalf("expected empty body error, got %v", err)
	}
	if _, err := normalizeBody(strings.Repeat("я", maxMessageLength+1)); !errors.Is(err, ErrInvalidMessage) {
		t.Fatalf("expected long body error, got %v", err)
	}

	first := bodyChecksum("same")
	second := bodyChecksum("same")
	third := bodyChecksum("different")
	if first == "" || first != second {
		t.Fatalf("checksum should be deterministic: first=%q second=%q", first, second)
	}
	if first == third {
		t.Fatal("checksum should change when body changes")
	}
}

func newTestChatService(t *testing.T, repo *fakeChatRepository) (*Service, *MessageCipher) {
	t.Helper()
	cipher, err := NewMessageCipher("")
	if err != nil {
		t.Fatalf("create cipher: %v", err)
	}
	return NewService(repo, cipher), cipher
}

func encryptedChatBody(t *testing.T, cipher *MessageCipher, body string) (string, string) {
	t.Helper()
	encrypted, nonce, err := cipher.Encrypt(body)
	if err != nil {
		t.Fatalf("encrypt body: %v", err)
	}
	return encrypted, nonce
}

func storedChatMessage(id string, threadID string, senderID string, encrypted string, nonce string) StoredMessage {
	return StoredMessage{
		ID:            id,
		ThreadID:      threadID,
		SenderID:      senderID,
		EncryptedBody: encrypted,
		Nonce:         nonce,
		Status:        MessageStatusSent,
		CreatedAt:     fixedChatTime(),
		UpdatedAt:     fixedChatTime(),
	}
}

func fixedChatTime() time.Time {
	return time.Date(2026, 6, 1, 12, 0, 0, 0, time.UTC)
}
