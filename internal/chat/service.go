package chat

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
)

const maxMessageLength = 2000

var (
	ErrThreadNotFound    = errors.New("chat thread not found")
	ErrMessageNotFound   = errors.New("chat message not found")
	ErrUserNotFound      = errors.New("chat user not found")
	ErrForbidden         = errors.New("chat action forbidden")
	ErrCannotMessageSelf = errors.New("cannot message self")
	ErrInvalidMessage    = errors.New("invalid chat message")
)

type Repository interface {
	GetOrCreateThread(ctx context.Context, userID string, participantID string) (StoredThreadSummary, error)
	ListThreads(ctx context.Context, userID string) ([]StoredThreadSummary, error)
	ListMessages(ctx context.Context, userID string, threadID string) ([]StoredMessage, error)
	CreateMessage(ctx context.Context, userID string, threadID string, encryptedBody string, nonce string, bodyHash string) (StoredMessage, error)
	UpdateMessage(ctx context.Context, userID string, threadID string, messageID string, encryptedBody string, nonce string, bodyHash string) (StoredMessage, error)
	DeleteMessage(ctx context.Context, userID string, threadID string, messageID string) (StoredMessage, error)
}

type Service struct {
	repository Repository
	cipher     *MessageCipher
}

func NewService(repository Repository, cipher *MessageCipher) *Service {
	return &Service{repository: repository, cipher: cipher}
}

func (s *Service) GetOrCreateThread(ctx context.Context, userID string, participantID string) (ThreadSummary, error) {
	userID = strings.TrimSpace(userID)
	participantID = strings.TrimSpace(participantID)
	if userID == "" || participantID == "" {
		return ThreadSummary{}, ErrUserNotFound
	}
	if userID == participantID {
		return ThreadSummary{}, ErrCannotMessageSelf
	}
	stored, err := s.repository.GetOrCreateThread(ctx, userID, participantID)
	if err != nil {
		return ThreadSummary{}, err
	}
	return s.threadSummary(stored), nil
}

func (s *Service) ListThreads(ctx context.Context, userID string) ([]ThreadSummary, error) {
	stored, err := s.repository.ListThreads(ctx, strings.TrimSpace(userID))
	if err != nil {
		return nil, err
	}
	items := make([]ThreadSummary, 0, len(stored))
	for _, item := range stored {
		items = append(items, s.threadSummary(item))
	}
	return items, nil
}

func (s *Service) ListMessages(ctx context.Context, userID string, threadID string) ([]Message, error) {
	stored, err := s.repository.ListMessages(ctx, strings.TrimSpace(userID), strings.TrimSpace(threadID))
	if err != nil {
		return nil, err
	}
	items := make([]Message, 0, len(stored))
	for _, item := range stored {
		message, err := s.message(item)
		if err != nil {
			return nil, err
		}
		items = append(items, message)
	}
	return items, nil
}

func (s *Service) SendMessage(ctx context.Context, userID string, threadID string, body string) (Message, error) {
	body, err := normalizeBody(body)
	if err != nil {
		return Message{}, err
	}
	encrypted, nonce, err := s.cipher.Encrypt(body)
	if err != nil {
		return Message{}, err
	}
	stored, err := s.repository.CreateMessage(ctx, strings.TrimSpace(userID), strings.TrimSpace(threadID), encrypted, nonce, bodyChecksum(body))
	if err != nil {
		return Message{}, err
	}
	return s.message(stored)
}

func (s *Service) EditMessage(ctx context.Context, userID string, threadID string, messageID string, body string) (Message, error) {
	body, err := normalizeBody(body)
	if err != nil {
		return Message{}, err
	}
	encrypted, nonce, err := s.cipher.Encrypt(body)
	if err != nil {
		return Message{}, err
	}
	stored, err := s.repository.UpdateMessage(ctx, strings.TrimSpace(userID), strings.TrimSpace(threadID), strings.TrimSpace(messageID), encrypted, nonce, bodyChecksum(body))
	if err != nil {
		return Message{}, err
	}
	return s.message(stored)
}

func (s *Service) DeleteMessage(ctx context.Context, userID string, threadID string, messageID string) (Message, error) {
	stored, err := s.repository.DeleteMessage(ctx, strings.TrimSpace(userID), strings.TrimSpace(threadID), strings.TrimSpace(messageID))
	if err != nil {
		return Message{}, err
	}
	return s.message(stored)
}

func (s *Service) threadSummary(stored StoredThreadSummary) ThreadSummary {
	preview := ""
	if stored.LastMessageAt != nil {
		if stored.LastMessageDeleted {
			preview = "Сообщение удалено"
		} else if stored.LastMessageEncrypted != "" && stored.LastMessageNonce != "" {
			if body, err := s.cipher.Decrypt(stored.LastMessageEncrypted, stored.LastMessageNonce); err == nil {
				preview = previewText(body)
			}
		}
	}
	return ThreadSummary{
		ID:                 stored.ID,
		Participant:        stored.Participant,
		LastMessagePreview: preview,
		LastMessageAt:      stored.LastMessageAt,
		UpdatedAt:          stored.UpdatedAt,
	}
}

func (s *Service) message(stored StoredMessage) (Message, error) {
	body := ""
	if stored.IsDeleted {
		body = "Сообщение удалено"
	} else {
		decrypted, err := s.cipher.Decrypt(stored.EncryptedBody, stored.Nonce)
		if err != nil {
			return Message{}, err
		}
		body = decrypted
	}
	return Message{
		ID:        stored.ID,
		ThreadID:  stored.ThreadID,
		SenderID:  stored.SenderID,
		Body:      body,
		Status:    stored.Status,
		CreatedAt: stored.CreatedAt,
		UpdatedAt: stored.UpdatedAt,
		EditedAt:  stored.EditedAt,
		IsDeleted: stored.IsDeleted,
	}, nil
}

func normalizeBody(body string) (string, error) {
	trimmed := strings.TrimSpace(body)
	if trimmed == "" || len([]rune(trimmed)) > maxMessageLength {
		return "", ErrInvalidMessage
	}
	return trimmed, nil
}

func bodyChecksum(body string) string {
	sum := sha256.Sum256([]byte(body))
	return hex.EncodeToString(sum[:])
}

func previewText(body string) string {
	runes := []rune(strings.TrimSpace(body))
	if len(runes) <= 120 {
		return string(runes)
	}
	return string(runes[:120]) + "..."
}
