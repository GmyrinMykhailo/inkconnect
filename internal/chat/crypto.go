package chat

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"strings"
)

var ErrChatEncryptionKeyInvalid = errors.New("CHAT_ENCRYPTION_KEY must be a base64 encoded 32 byte key")

type MessageCipher struct {
	aead cipher.AEAD
}

func NewMessageCipher(rawKey string) (*MessageCipher, error) {
	key, err := chatEncryptionKey(rawKey)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create chat AES cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create chat AES-GCM cipher: %w", err)
	}
	return &MessageCipher{aead: aead}, nil
}

func (c *MessageCipher) Encrypt(plaintext string) (ciphertext string, nonce string, err error) {
	rawNonce := make([]byte, c.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, rawNonce); err != nil {
		return "", "", fmt.Errorf("generate chat nonce: %w", err)
	}
	sealed := c.aead.Seal(nil, rawNonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(sealed),
		base64.StdEncoding.EncodeToString(rawNonce),
		nil
}

func (c *MessageCipher) Decrypt(ciphertext string, nonce string) (string, error) {
	rawCiphertext, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", fmt.Errorf("decode chat message body: %w", err)
	}
	rawNonce, err := base64.StdEncoding.DecodeString(nonce)
	if err != nil {
		return "", fmt.Errorf("decode chat nonce: %w", err)
	}
	opened, err := c.aead.Open(nil, rawNonce, rawCiphertext, nil)
	if err != nil {
		return "", fmt.Errorf("decrypt chat message: %w", err)
	}
	return string(opened), nil
}

func chatEncryptionKey(rawKey string) ([]byte, error) {
	trimmed := strings.TrimSpace(rawKey)
	if trimmed == "" {
		sum := sha256.Sum256([]byte("inkconnect-local-dev-chat-encryption-key"))
		return sum[:], nil
	}
	decoded, err := base64.StdEncoding.DecodeString(trimmed)
	if err != nil || len(decoded) != 32 {
		return nil, ErrChatEncryptionKeyInvalid
	}
	return decoded, nil
}
