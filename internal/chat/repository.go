package chat

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

type PostgresRepository struct {
	db *sql.DB
}

func NewPostgresRepository(db *sql.DB) *PostgresRepository {
	return &PostgresRepository{db: db}
}

func EnsureChatSchema(ctx context.Context, db *sql.DB) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS chat_threads (
		    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		    participant_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		    participant_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		    last_message_at TIMESTAMPTZ,
		    CONSTRAINT chat_threads_participants_chk CHECK (participant_a_id <> participant_b_id)
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_threads_unique_pair
		    ON chat_threads (LEAST(participant_a_id, participant_b_id), GREATEST(participant_a_id, participant_b_id))`,
		`CREATE INDEX IF NOT EXISTS idx_chat_threads_participant_a ON chat_threads(participant_a_id, updated_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_chat_threads_participant_b ON chat_threads(participant_b_id, updated_at DESC)`,
		`CREATE TABLE IF NOT EXISTS chat_messages (
		    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		    thread_id UUID NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
		    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		    encrypted_body TEXT NOT NULL,
		    encryption_nonce TEXT NOT NULL,
		    body_hash TEXT NOT NULL,
		    status TEXT NOT NULL DEFAULT 'delivered',
		    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		    edited_at TIMESTAMPTZ,
		    deleted_at TIMESTAMPTZ,
		    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
		    CONSTRAINT chat_messages_status_chk CHECK (status IN ('sent', 'delivered'))
		)`,
		`CREATE INDEX IF NOT EXISTS idx_chat_messages_thread_created ON chat_messages(thread_id, created_at)`,
		`CREATE INDEX IF NOT EXISTS idx_chat_messages_sender ON chat_messages(sender_id)`,
	}
	for _, statement := range statements {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("ensure chat schema: %w", err)
		}
	}
	return nil
}

func (r *PostgresRepository) GetOrCreateThread(ctx context.Context, userID string, participantID string) (StoredThreadSummary, error) {
	if strings.TrimSpace(userID) == strings.TrimSpace(participantID) {
		return StoredThreadSummary{}, ErrCannotMessageSelf
	}
	participant, err := r.findParticipant(ctx, participantID)
	if err != nil {
		return StoredThreadSummary{}, err
	}

	var threadID string
	var updatedAt time.Time
	var lastMessageAt sql.NullTime
	err = r.db.QueryRowContext(
		ctx,
		`SELECT id, updated_at, last_message_at
		 FROM chat_threads
		 WHERE (participant_a_id = $1 AND participant_b_id = $2)
		    OR (participant_a_id = $2 AND participant_b_id = $1)`,
		userID,
		participantID,
	).Scan(&threadID, &updatedAt, &lastMessageAt)
	if errors.Is(err, sql.ErrNoRows) {
		err = r.db.QueryRowContext(
			ctx,
			`INSERT INTO chat_threads (participant_a_id, participant_b_id)
			 VALUES ($1, $2)
			 RETURNING id, updated_at, last_message_at`,
			userID,
			participantID,
		).Scan(&threadID, &updatedAt, &lastMessageAt)
	}
	if err != nil {
		return StoredThreadSummary{}, fmt.Errorf("get or create chat thread: %w", err)
	}

	return StoredThreadSummary{
		ID:            threadID,
		Participant:   participant,
		LastMessageAt: nullTimePtr(lastMessageAt),
		UpdatedAt:     updatedAt,
	}, nil
}

func (r *PostgresRepository) ListThreads(ctx context.Context, userID string) ([]StoredThreadSummary, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT t.id,
		        t.updated_at,
		        t.last_message_at,
		        other.id,
		        other.username,
		        other.username,
		        other.role,
		        COALESCE('/api/v1/media/' || am.id::text, COALESCE(other.avatar_url, '')),
		        COALESCE(last_message.encrypted_body, ''),
		        COALESCE(last_message.encryption_nonce, ''),
		        COALESCE(last_message.is_deleted, FALSE)
		 FROM chat_threads t
		 JOIN users other
		   ON other.id = CASE WHEN t.participant_a_id = $1 THEN t.participant_b_id ELSE t.participant_a_id END
		 LEFT JOIN media_objects am
		   ON am.id = other.avatar_media_id
		  AND am.kind = 'user_avatar'
		  AND am.deleted_at IS NULL
		 LEFT JOIN LATERAL (
		    SELECT encrypted_body, encryption_nonce, is_deleted
		    FROM chat_messages
		    WHERE thread_id = t.id
		    ORDER BY created_at DESC
		    LIMIT 1
		 ) last_message ON TRUE
		 WHERE (t.participant_a_id = $1 OR t.participant_b_id = $1)
		   AND other.is_active = TRUE
		 ORDER BY COALESCE(t.last_message_at, t.updated_at) DESC, t.updated_at DESC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("list chat threads: %w", err)
	}
	defer rows.Close()

	items := []StoredThreadSummary{}
	for rows.Next() {
		var item StoredThreadSummary
		var lastMessageAt sql.NullTime
		if err := rows.Scan(
			&item.ID,
			&item.UpdatedAt,
			&lastMessageAt,
			&item.Participant.ID,
			&item.Participant.Username,
			&item.Participant.DisplayName,
			&item.Participant.Role,
			&item.Participant.AvatarURL,
			&item.LastMessageEncrypted,
			&item.LastMessageNonce,
			&item.LastMessageDeleted,
		); err != nil {
			return nil, fmt.Errorf("scan chat thread: %w", err)
		}
		item.LastMessageAt = nullTimePtr(lastMessageAt)
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate chat threads: %w", err)
	}
	return items, nil
}

func (r *PostgresRepository) ListMessages(ctx context.Context, userID string, threadID string) ([]StoredMessage, error) {
	if err := r.requireThreadParticipant(ctx, userID, threadID); err != nil {
		return nil, err
	}
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id, thread_id, sender_id, encrypted_body, encryption_nonce, status,
		        created_at, updated_at, edited_at, is_deleted
		 FROM chat_messages
		 WHERE thread_id = $1
		 ORDER BY created_at ASC`,
		threadID,
	)
	if err != nil {
		return nil, fmt.Errorf("list chat messages: %w", err)
	}
	defer rows.Close()

	items := []StoredMessage{}
	for rows.Next() {
		message, err := scanStoredMessage(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, message)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate chat messages: %w", err)
	}
	return items, nil
}

func (r *PostgresRepository) CreateMessage(ctx context.Context, userID string, threadID string, encryptedBody string, nonce string, bodyHash string) (StoredMessage, error) {
	if err := r.requireThreadParticipant(ctx, userID, threadID); err != nil {
		return StoredMessage{}, err
	}
	var message StoredMessage
	var editedAt sql.NullTime
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return StoredMessage{}, fmt.Errorf("begin chat message transaction: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO chat_messages (thread_id, sender_id, encrypted_body, encryption_nonce, body_hash, status)
		 VALUES ($1, $2, $3, $4, $5, 'delivered')
		 RETURNING id, thread_id, sender_id, encrypted_body, encryption_nonce, status,
		           created_at, updated_at, edited_at, is_deleted`,
		threadID,
		userID,
		encryptedBody,
		nonce,
		bodyHash,
	).Scan(
		&message.ID,
		&message.ThreadID,
		&message.SenderID,
		&message.EncryptedBody,
		&message.Nonce,
		&message.Status,
		&message.CreatedAt,
		&message.UpdatedAt,
		&editedAt,
		&message.IsDeleted,
	)
	if err != nil {
		return StoredMessage{}, fmt.Errorf("insert chat message: %w", err)
	}
	message.EditedAt = nullTimePtr(editedAt)

	if _, err := tx.ExecContext(
		ctx,
		`UPDATE chat_threads
		 SET updated_at = NOW(), last_message_at = $2
		 WHERE id = $1`,
		threadID,
		message.CreatedAt,
	); err != nil {
		return StoredMessage{}, fmt.Errorf("update chat thread timestamp: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return StoredMessage{}, fmt.Errorf("commit chat message transaction: %w", err)
	}
	return message, nil
}

func (r *PostgresRepository) UpdateMessage(ctx context.Context, userID string, threadID string, messageID string, encryptedBody string, nonce string, bodyHash string) (StoredMessage, error) {
	if err := r.requireThreadParticipant(ctx, userID, threadID); err != nil {
		return StoredMessage{}, err
	}
	row := r.db.QueryRowContext(
		ctx,
		`UPDATE chat_messages
		 SET encrypted_body = $4,
		     encryption_nonce = $5,
		     body_hash = $6,
		     updated_at = NOW(),
		     edited_at = NOW()
		 WHERE id = $3
		   AND thread_id = $2
		   AND sender_id = $1
		   AND is_deleted = FALSE
		 RETURNING id, thread_id, sender_id, encrypted_body, encryption_nonce, status,
		           created_at, updated_at, edited_at, is_deleted`,
		userID,
		threadID,
		messageID,
		encryptedBody,
		nonce,
		bodyHash,
	)
	message, err := scanStoredMessage(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return StoredMessage{}, ErrMessageNotFound
		}
		return StoredMessage{}, err
	}
	return message, nil
}

func (r *PostgresRepository) DeleteMessage(ctx context.Context, userID string, threadID string, messageID string) (StoredMessage, error) {
	if err := r.requireThreadParticipant(ctx, userID, threadID); err != nil {
		return StoredMessage{}, err
	}
	row := r.db.QueryRowContext(
		ctx,
		`UPDATE chat_messages
		 SET is_deleted = TRUE,
		     deleted_at = NOW(),
		     updated_at = NOW()
		 WHERE id = $3
		   AND thread_id = $2
		   AND sender_id = $1
		   AND is_deleted = FALSE
		 RETURNING id, thread_id, sender_id, encrypted_body, encryption_nonce, status,
		           created_at, updated_at, edited_at, is_deleted`,
		userID,
		threadID,
		messageID,
	)
	message, err := scanStoredMessage(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return StoredMessage{}, ErrMessageNotFound
		}
		return StoredMessage{}, err
	}
	return message, nil
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanStoredMessage(row rowScanner) (StoredMessage, error) {
	var message StoredMessage
	var editedAt sql.NullTime
	if err := row.Scan(
		&message.ID,
		&message.ThreadID,
		&message.SenderID,
		&message.EncryptedBody,
		&message.Nonce,
		&message.Status,
		&message.CreatedAt,
		&message.UpdatedAt,
		&editedAt,
		&message.IsDeleted,
	); err != nil {
		return StoredMessage{}, fmt.Errorf("scan chat message: %w", err)
	}
	message.EditedAt = nullTimePtr(editedAt)
	return message, nil
}

func (r *PostgresRepository) findParticipant(ctx context.Context, userID string) (Participant, error) {
	var participant Participant
	err := r.db.QueryRowContext(
		ctx,
		`SELECT u.id,
		        u.username,
		        u.username,
		        u.role,
		        COALESCE('/api/v1/media/' || am.id::text, COALESCE(u.avatar_url, ''))
		 FROM users u
		 LEFT JOIN media_objects am
		   ON am.id = u.avatar_media_id
		  AND am.kind = 'user_avatar'
		  AND am.deleted_at IS NULL
		 WHERE u.id = $1
		   AND u.is_active = TRUE`,
		userID,
	).Scan(
		&participant.ID,
		&participant.Username,
		&participant.DisplayName,
		&participant.Role,
		&participant.AvatarURL,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Participant{}, ErrUserNotFound
		}
		return Participant{}, fmt.Errorf("find chat participant: %w", err)
	}
	return participant, nil
}

func (r *PostgresRepository) requireThreadParticipant(ctx context.Context, userID string, threadID string) error {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS (
		    SELECT 1
		    FROM chat_threads
		    WHERE id = $2
		      AND (participant_a_id = $1 OR participant_b_id = $1)
		)`,
		userID,
		threadID,
	).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check chat thread participant: %w", err)
	}
	if !exists {
		return ErrThreadNotFound
	}
	return nil
}

func nullTimePtr(value sql.NullTime) *time.Time {
	if !value.Valid {
		return nil
	}
	return &value.Time
}
