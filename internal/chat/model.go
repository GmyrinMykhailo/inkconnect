package chat

import "time"

const (
	MessageStatusSent      = "sent"
	MessageStatusDelivered = "delivered"
)

type Participant struct {
	ID          string `json:"id"`
	Username    string `json:"username"`
	DisplayName string `json:"display_name"`
	Role        string `json:"role"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

type ThreadSummary struct {
	ID                 string      `json:"id"`
	Participant        Participant `json:"participant"`
	LastMessagePreview string      `json:"last_message_preview"`
	LastMessageAt      *time.Time  `json:"last_message_at,omitempty"`
	UpdatedAt          time.Time   `json:"updated_at"`
}

type Message struct {
	ID        string     `json:"id"`
	ThreadID  string     `json:"thread_id"`
	SenderID  string     `json:"sender_id"`
	Body      string     `json:"body"`
	Status    string     `json:"status"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
	EditedAt  *time.Time `json:"edited_at,omitempty"`
	IsDeleted bool       `json:"is_deleted"`
}

type StoredThreadSummary struct {
	ID                   string
	Participant          Participant
	LastMessageEncrypted string
	LastMessageNonce     string
	LastMessageDeleted   bool
	LastMessageAt        *time.Time
	UpdatedAt            time.Time
}

type StoredMessage struct {
	ID            string
	ThreadID      string
	SenderID      string
	EncryptedBody string
	Nonce         string
	Status        string
	CreatedAt     time.Time
	UpdatedAt     time.Time
	EditedAt      *time.Time
	IsDeleted     bool
}
