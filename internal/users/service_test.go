package users

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"testing"

	platformcrypto "inkconnect/internal/platform/crypto"
)

type fakeRegistrationRepository struct {
	userID      string
	signingKeys map[string]UpsertSigningKeyParams
}

func (r *fakeRegistrationRepository) CreateUser(ctx context.Context, params CreateUserParams) (string, error) {
	return r.userID, nil
}

func (r *fakeRegistrationRepository) UpsertSigningKey(ctx context.Context, params UpsertSigningKeyParams) error {
	if r.signingKeys == nil {
		r.signingKeys = map[string]UpsertSigningKeyParams{}
	}
	r.signingKeys[params.UserID+"|"+params.KeyFingerprint] = params
	return nil
}

func TestRegistrationCreatesEncryptedSigningKey(t *testing.T) {
	repo := &fakeRegistrationRepository{userID: "user-1"}
	encryptionKey := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x44}, 32))
	service := NewRegistrationService(repo, RegistrationSigningConfig{
		EncryptionKey:   encryptionKey,
		EncryptionKeyID: "test-key-1",
	})

	result, err := service.Register(context.Background(), validRegistrationInput())
	if err != nil {
		t.Fatalf("Register() error = %v", err)
	}

	key := singleSigningKey(t, repo)
	if key.EncryptedPrivateKey == nil || *key.EncryptedPrivateKey == "" {
		t.Fatalf("encrypted private key was not stored")
	}
	if key.PrivateKeyEncryptionKeyID == nil || *key.PrivateKeyEncryptionKeyID != "test-key-1" {
		t.Fatalf("private key encryption key id mismatch: %#v", key.PrivateKeyEncryptionKeyID)
	}
	if key.PrivateKeyEncryptedAt == nil {
		t.Fatalf("private key encrypted timestamp was not stored")
	}

	protector, err := platformcrypto.NewPrivateKeyProtector(encryptionKey, "test-key-1")
	if err != nil {
		t.Fatalf("NewPrivateKeyProtector() error = %v", err)
	}
	decrypted, err := protector.DecryptPrivateKey(*key.EncryptedPrivateKey, result.UserID, key.KeyFingerprint, key.Algorithm)
	if err != nil {
		t.Fatalf("DecryptPrivateKey() error = %v", err)
	}
	decryptedRaw, err := base64.StdEncoding.DecodeString(decrypted)
	if err != nil {
		t.Fatalf("decode decrypted private key: %v", err)
	}
	publicRaw, err := base64.StdEncoding.DecodeString(result.PublicKey)
	if err != nil {
		t.Fatalf("decode registration public key: %v", err)
	}
	if len(decryptedRaw) != ed25519.PrivateKeySize {
		t.Fatalf("decrypted private key length = %d, want %d", len(decryptedRaw), ed25519.PrivateKeySize)
	}
	if !bytes.Equal(decryptedRaw[ed25519.PrivateKeySize-ed25519.PublicKeySize:], publicRaw) {
		t.Fatalf("decrypted private key does not contain registration public key")
	}
}

func TestRegistrationCreatesPublicOnlySigningKeyWhenEncryptionConfigMissing(t *testing.T) {
	repo := &fakeRegistrationRepository{userID: "user-1"}
	service := NewRegistrationService(repo)

	if _, err := service.Register(context.Background(), validRegistrationInput()); err != nil {
		t.Fatalf("Register() error = %v", err)
	}

	key := singleSigningKey(t, repo)
	if key.EncryptedPrivateKey != nil {
		t.Fatalf("encrypted private key was stored without encryption config")
	}
	if key.PrivateKeyEncryptionKeyID != nil {
		t.Fatalf("private key encryption key id was stored without encryption config")
	}
	if key.PrivateKeyEncryptedAt != nil {
		t.Fatalf("private key encrypted timestamp was stored without encryption config")
	}
}

func TestRegistrationSigningKeyUpsertIsIdempotent(t *testing.T) {
	repo := &fakeRegistrationRepository{userID: "user-1"}
	encryptionKey := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x44}, 32))
	service := NewRegistrationService(repo, RegistrationSigningConfig{
		EncryptionKey:   encryptionKey,
		EncryptionKeyID: "test-key-1",
	})
	keyPair, err := platformcrypto.GenerateKeyPair()
	if err != nil {
		t.Fatalf("GenerateKeyPair() error = %v", err)
	}
	protector, err := service.privateKeyProtector()
	if err != nil {
		t.Fatalf("privateKeyProtector() error = %v", err)
	}

	if err = service.upsertRegistrationSigningKey(context.Background(), "user-1", keyPair, protector); err != nil {
		t.Fatalf("first upsertRegistrationSigningKey() error = %v", err)
	}
	if err = service.upsertRegistrationSigningKey(context.Background(), "user-1", keyPair, protector); err != nil {
		t.Fatalf("second upsertRegistrationSigningKey() error = %v", err)
	}
	if len(repo.signingKeys) != 1 {
		t.Fatalf("signing keys count = %d, want 1", len(repo.signingKeys))
	}
}

func validRegistrationInput() RegistrationInput {
	return RegistrationInput{
		Username:          "newclient",
		Email:             "newclient@test.test",
		Password:          "Strong123!",
		PasswordConfirm:   "Strong123!",
		Role:              RoleClient,
		LastName:          "Иванов",
		FirstName:         "Иван",
		MiddleName:        "Иванович",
		Phone:             "9000000001",
		City:              "Москва",
		ShowCityInProfile: true,
		Bio:               "Тестовый клиент",
		AgreementAccepted: true,
	}
}

func singleSigningKey(t *testing.T, repo *fakeRegistrationRepository) UpsertSigningKeyParams {
	t.Helper()
	if len(repo.signingKeys) != 1 {
		t.Fatalf("signing keys count = %d, want 1", len(repo.signingKeys))
	}
	for _, key := range repo.signingKeys {
		return key
	}
	t.Fatalf("signing key not found")
	return UpsertSigningKeyParams{}
}
