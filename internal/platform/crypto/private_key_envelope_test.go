package crypto

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"strings"
	"testing"
)

func TestPrivateKeyProtectorEncryptDecrypt(t *testing.T) {
	protector := mustPrivateKeyProtector(t, bytes.Repeat([]byte{0x11}, 32), "mvp-key-1")
	plainPrivateKey := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x22}, ed25519.PrivateKeySize))

	envelope, err := protector.EncryptPrivateKey(plainPrivateKey, "user-1", "fingerprint-1", "ed25519")
	if err != nil {
		t.Fatalf("EncryptPrivateKey() error = %v", err)
	}
	if !strings.Contains(envelope, `"key_id":"mvp-key-1"`) {
		t.Fatalf("encrypted envelope does not contain expected key id: %s", envelope)
	}

	decrypted, err := protector.DecryptPrivateKey(envelope, "user-1", "fingerprint-1", "ed25519")
	if err != nil {
		t.Fatalf("DecryptPrivateKey() error = %v", err)
	}
	if decrypted != plainPrivateKey {
		t.Fatalf("decrypted private key mismatch")
	}
}

func TestPrivateKeyProtectorDecryptRejectsWrongAAD(t *testing.T) {
	protector := mustPrivateKeyProtector(t, bytes.Repeat([]byte{0x11}, 32), "mvp-key-1")
	plainPrivateKey := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x22}, ed25519.PrivateKeySize))

	envelope, err := protector.EncryptPrivateKey(plainPrivateKey, "user-1", "fingerprint-1", "ed25519")
	if err != nil {
		t.Fatalf("EncryptPrivateKey() error = %v", err)
	}

	if _, err := protector.DecryptPrivateKey(envelope, "user-2", "fingerprint-1", "ed25519"); err == nil {
		t.Fatalf("DecryptPrivateKey() with wrong user id succeeded")
	}
	if _, err := protector.DecryptPrivateKey(envelope, "user-1", "fingerprint-2", "ed25519"); err == nil {
		t.Fatalf("DecryptPrivateKey() with wrong key fingerprint succeeded")
	}
}

func TestPrivateKeyProtectorDecryptRejectsWrongKey(t *testing.T) {
	protector := mustPrivateKeyProtector(t, bytes.Repeat([]byte{0x11}, 32), "mvp-key-1")
	wrongProtector := mustPrivateKeyProtector(t, bytes.Repeat([]byte{0x33}, 32), "mvp-key-1")
	plainPrivateKey := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x22}, ed25519.PrivateKeySize))

	envelope, err := protector.EncryptPrivateKey(plainPrivateKey, "user-1", "fingerprint-1", "ed25519")
	if err != nil {
		t.Fatalf("EncryptPrivateKey() error = %v", err)
	}

	if _, err := wrongProtector.DecryptPrivateKey(envelope, "user-1", "fingerprint-1", "ed25519"); err == nil {
		t.Fatalf("DecryptPrivateKey() with wrong encryption key succeeded")
	}
}

func TestNewPrivateKeyProtectorRequiresConfig(t *testing.T) {
	if _, err := NewPrivateKeyProtector("", "mvp-key-1"); err == nil {
		t.Fatalf("NewPrivateKeyProtector() without key succeeded")
	}
	if _, err := NewPrivateKeyProtector(base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x11}, 32)), ""); err == nil {
		t.Fatalf("NewPrivateKeyProtector() without key id succeeded")
	}
}

func mustPrivateKeyProtector(t *testing.T, key []byte, keyID string) *PrivateKeyProtector {
	t.Helper()

	protector, err := NewPrivateKeyProtector(base64.StdEncoding.EncodeToString(key), keyID)
	if err != nil {
		t.Fatalf("NewPrivateKeyProtector() error = %v", err)
	}

	return protector
}
