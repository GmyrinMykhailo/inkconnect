package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
)

const (
	privateKeyEnvelopeVersion = 1
	privateKeyEnvelopeCipher  = "aes-256-gcm"
)

var (
	ErrSigningKeyEncryptionKeyRequired   = errors.New("SIGNING_KEY_ENCRYPTION_KEY is required for backend-managed signing")
	ErrSigningKeyEncryptionKeyIDRequired = errors.New("SIGNING_KEY_ENCRYPTION_KEY_ID is required for backend-managed signing")
)

type PrivateKeyProtector struct {
	keyID string
	aead  cipher.AEAD
}

type privateKeyEnvelope struct {
	Version    int    `json:"version"`
	KeyID      string `json:"key_id"`
	Cipher     string `json:"cipher"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
}

func NewPrivateKeyProtector(encryptionKeyBase64 string, keyID string) (*PrivateKeyProtector, error) {
	if strings.TrimSpace(encryptionKeyBase64) == "" {
		return nil, ErrSigningKeyEncryptionKeyRequired
	}
	if strings.TrimSpace(keyID) == "" {
		return nil, ErrSigningKeyEncryptionKeyIDRequired
	}

	key, err := base64.StdEncoding.DecodeString(encryptionKeyBase64)
	if err != nil {
		return nil, fmt.Errorf("decode SIGNING_KEY_ENCRYPTION_KEY: %w", err)
	}
	if len(key) != 32 {
		return nil, fmt.Errorf("SIGNING_KEY_ENCRYPTION_KEY must decode to 32 bytes, got %d", len(key))
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create AES cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create AES-GCM cipher: %w", err)
	}

	return &PrivateKeyProtector{
		keyID: strings.TrimSpace(keyID),
		aead:  aead,
	}, nil
}

func (p *PrivateKeyProtector) EncryptPrivateKey(plainPrivateKeyBase64 string, userID string, keyFingerprint string, algorithm string) (string, error) {
	if p == nil {
		return "", ErrSigningKeyEncryptionKeyRequired
	}
	if strings.TrimSpace(plainPrivateKeyBase64) == "" {
		return "", errors.New("private key is required")
	}

	nonce := make([]byte, p.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("generate private key encryption nonce: %w", err)
	}

	ciphertext := p.aead.Seal(nil, nonce, []byte(plainPrivateKeyBase64), privateKeyAAD(userID, keyFingerprint, algorithm))
	envelope := privateKeyEnvelope{
		Version:    privateKeyEnvelopeVersion,
		KeyID:      p.keyID,
		Cipher:     privateKeyEnvelopeCipher,
		Nonce:      base64.StdEncoding.EncodeToString(nonce),
		Ciphertext: base64.StdEncoding.EncodeToString(ciphertext),
	}

	encoded, err := json.Marshal(envelope)
	if err != nil {
		return "", fmt.Errorf("encode private key envelope: %w", err)
	}

	return string(encoded), nil
}

func (p *PrivateKeyProtector) DecryptPrivateKey(envelopeJSON string, userID string, keyFingerprint string, algorithm string) (string, error) {
	if p == nil {
		return "", ErrSigningKeyEncryptionKeyRequired
	}
	if strings.TrimSpace(envelopeJSON) == "" {
		return "", errors.New("private key envelope is required")
	}

	var envelope privateKeyEnvelope
	if err := json.Unmarshal([]byte(envelopeJSON), &envelope); err != nil {
		return "", fmt.Errorf("decode private key envelope: %w", err)
	}
	if envelope.Version != privateKeyEnvelopeVersion {
		return "", fmt.Errorf("unsupported private key envelope version: %d", envelope.Version)
	}
	if envelope.KeyID != p.keyID {
		return "", fmt.Errorf("private key envelope key_id mismatch")
	}
	if envelope.Cipher != privateKeyEnvelopeCipher {
		return "", fmt.Errorf("unsupported private key envelope cipher: %s", envelope.Cipher)
	}

	nonce, err := base64.StdEncoding.DecodeString(envelope.Nonce)
	if err != nil {
		return "", fmt.Errorf("decode private key envelope nonce: %w", err)
	}
	if len(nonce) != p.aead.NonceSize() {
		return "", fmt.Errorf("private key envelope nonce must decode to %d bytes, got %d", p.aead.NonceSize(), len(nonce))
	}

	ciphertext, err := base64.StdEncoding.DecodeString(envelope.Ciphertext)
	if err != nil {
		return "", fmt.Errorf("decode private key envelope ciphertext: %w", err)
	}

	plain, err := p.aead.Open(nil, nonce, ciphertext, privateKeyAAD(userID, keyFingerprint, algorithm))
	if err != nil {
		return "", fmt.Errorf("decrypt private key envelope: %w", err)
	}

	return string(plain), nil
}

func privateKeyAAD(userID string, keyFingerprint string, algorithm string) []byte {
	return []byte(strings.Join([]string{
		"user_id=" + userID,
		"key_fingerprint=" + keyFingerprint,
		"algorithm=" + strings.ToLower(algorithm),
	}, "\n"))
}
