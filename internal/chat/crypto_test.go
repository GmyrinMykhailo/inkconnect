package chat

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestMessageCipherEncryptsAndDecrypts(t *testing.T) {
	key := base64.StdEncoding.EncodeToString([]byte("0123456789abcdef0123456789abcdef"))
	cipher, err := NewMessageCipher(key)
	if err != nil {
		t.Fatalf("create cipher: %v", err)
	}

	const plainText = "Привет, это личное сообщение"
	encrypted, nonce, err := cipher.Encrypt(plainText)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	if encrypted == "" {
		t.Fatal("encrypted body is empty")
	}
	if nonce == "" {
		t.Fatal("nonce is empty")
	}
	if strings.Contains(encrypted, plainText) {
		t.Fatal("encrypted body contains plaintext")
	}

	decrypted, err := cipher.Decrypt(encrypted, nonce)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if decrypted != plainText {
		t.Fatalf("decrypted body mismatch: got %q", decrypted)
	}
}

func TestMessageCipherRejectsInvalidKey(t *testing.T) {
	if _, err := NewMessageCipher("too-short"); err == nil {
		t.Fatal("expected invalid key error")
	}
}
