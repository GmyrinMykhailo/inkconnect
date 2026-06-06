package users

import (
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	platformcrypto "inkconnect/internal/platform/crypto"

	"golang.org/x/crypto/bcrypt"
)

var (
	ErrAgreementRequired   = errors.New("agreement must be accepted")
	ErrInvalidRole         = errors.New("role must be client or master")
	ErrWeakPassword        = errors.New("password does not meet requirements")
	ErrPasswordConfirmWeak = errors.New("password confirmation does not meet requirements")
	ErrPasswordMismatch    = errors.New("password confirmation does not match")
	ErrUsernameRequired    = errors.New("username is required")
	ErrInvalidUsername     = errors.New("username has invalid format")
	ErrEmailRequired       = errors.New("email is required")
	ErrInvalidEmail        = errors.New("email has invalid format")
	ErrLastNameRequired    = errors.New("last name is required")
	ErrFirstNameRequired   = errors.New("first name is required")
	ErrInvalidName         = errors.New("name must contain only letters")
	ErrNameScriptMismatch  = errors.New("name fields must use one alphabet")
	ErrPhoneRequired       = errors.New("phone is required")
	ErrInvalidPhone        = errors.New("phone must contain exactly 10 digits after +7")
	ErrCityRequired        = errors.New("city is required")
	ErrInvalidCity         = errors.New("city contains invalid characters")
	ErrBioTooLong          = errors.New("bio must not exceed 150 characters")
	ErrFieldTooLong        = errors.New("field exceeds max length")
)

var emailPattern = regexp.MustCompile(`^[a-z0-9._%+\-]+@[a-z0-9\-]+(\.[a-z0-9\-]+)+$`)
var usernamePattern = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

type RegistrationService struct {
	repository    registrationRepository
	signingConfig RegistrationSigningConfig
}

type registrationRepository interface {
	CreateUser(ctx context.Context, params CreateUserParams) (string, error)
	UpsertSigningKey(ctx context.Context, params UpsertSigningKeyParams) error
}

type RegistrationSigningConfig struct {
	EncryptionKey   string
	EncryptionKeyID string
}

func NewRegistrationService(repository registrationRepository, signingConfig ...RegistrationSigningConfig) *RegistrationService {
	cfg := RegistrationSigningConfig{}
	if len(signingConfig) > 0 {
		cfg = signingConfig[0]
	}

	return &RegistrationService{
		repository:    repository,
		signingConfig: cfg,
	}
}

func (s *RegistrationService) Register(ctx context.Context, input RegistrationInput) (RegistrationResult, error) {
	input.Username = strings.TrimSpace(input.Username)
	input.Email = strings.TrimSpace(strings.ToLower(input.Email))
	input.LastName = strings.TrimSpace(input.LastName)
	input.FirstName = strings.TrimSpace(input.FirstName)
	input.MiddleName = strings.TrimSpace(input.MiddleName)
	input.Phone = normalizePhone(input.Phone)
	input.City = strings.TrimSpace(input.City)
	input.Bio = strings.TrimSpace(input.Bio)
	input.StudioName = strings.TrimSpace(input.StudioName)

	if input.Username == "" {
		return RegistrationResult{}, ErrUsernameRequired
	}
	if !isValidUsername(input.Username) {
		return RegistrationResult{}, ErrInvalidUsername
	}
	if input.Email == "" {
		return RegistrationResult{}, ErrEmailRequired
	}
	if !isValidEmail(input.Email) {
		return RegistrationResult{}, ErrInvalidEmail
	}
	if exceedsMaxLength(input.Username, 128) || exceedsMaxLength(input.LastName, 128) || exceedsMaxLength(input.FirstName, 128) || exceedsMaxLength(input.MiddleName, 128) || exceedsMaxLength(input.City, 128) || exceedsMaxLength(input.Password, 128) || exceedsMaxLength(input.PasswordConfirm, 128) {
		return RegistrationResult{}, ErrFieldTooLong
	}
	if input.LastName == "" {
		return RegistrationResult{}, ErrLastNameRequired
	}
	if input.FirstName == "" {
		return RegistrationResult{}, ErrFirstNameRequired
	}
	if !isValidHumanName(input.LastName) || !isValidHumanName(input.FirstName) || (input.MiddleName != "" && !isValidHumanName(input.MiddleName)) {
		return RegistrationResult{}, ErrInvalidName
	}
	if !hasConsistentNameScript(input.LastName, input.FirstName, input.MiddleName) {
		return RegistrationResult{}, ErrNameScriptMismatch
	}
	if !isValidPassword(input.Password, 10) {
		return RegistrationResult{}, ErrWeakPassword
	}
	if !isValidPassword(input.PasswordConfirm, 10) {
		return RegistrationResult{}, ErrPasswordConfirmWeak
	}
	if input.Password != input.PasswordConfirm {
		return RegistrationResult{}, ErrPasswordMismatch
	}
	if input.Phone == "" {
		return RegistrationResult{}, ErrPhoneRequired
	}
	if len(input.Phone) != 10 {
		return RegistrationResult{}, ErrInvalidPhone
	}
	if input.City == "" {
		return RegistrationResult{}, ErrCityRequired
	}
	if !isValidCityName(input.City) {
		return RegistrationResult{}, ErrInvalidCity
	}
	if utf8.RuneCountInString(input.Bio) > 150 {
		return RegistrationResult{}, ErrBioTooLong
	}
	if !input.AgreementAccepted {
		return RegistrationResult{}, ErrAgreementRequired
	}
	if input.Role != RoleClient && input.Role != RoleMaster {
		return RegistrationResult{}, ErrInvalidRole
	}

	keyPair, err := platformcrypto.GenerateKeyPair()
	if err != nil {
		return RegistrationResult{}, fmt.Errorf("generate key pair: %w", err)
	}
	privateKeyProtector, err := s.privateKeyProtector()
	if err != nil {
		return RegistrationResult{}, err
	}

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		return RegistrationResult{}, fmt.Errorf("hash password: %w", err)
	}

	userID, err := s.repository.CreateUser(ctx, CreateUserParams{
		Username:          input.Username,
		Email:             input.Email,
		PasswordHash:      string(passwordHash),
		Role:              input.Role,
		FullName:          joinNonEmpty(input.LastName, input.FirstName, input.MiddleName),
		LastName:          input.LastName,
		FirstName:         input.FirstName,
		MiddleName:        input.MiddleName,
		Phone:             "+7" + input.Phone,
		City:              input.City,
		ShowCityInProfile: input.ShowCityInProfile,
		Bio:               input.Bio,
		PublicKey:         keyPair.PublicKey,
		StudioName:        input.StudioName,
	})
	if err != nil {
		return RegistrationResult{}, err
	}

	if err = s.upsertRegistrationSigningKey(ctx, userID, keyPair, privateKeyProtector); err != nil {
		return RegistrationResult{}, err
	}

	return RegistrationResult{
		UserID:    userID,
		Username:  input.Username,
		Email:     input.Email,
		Role:      input.Role,
		PublicKey: keyPair.PublicKey,
	}, nil
}

func (s *RegistrationService) privateKeyProtector() (*platformcrypto.PrivateKeyProtector, error) {
	if strings.TrimSpace(s.signingConfig.EncryptionKey) == "" || strings.TrimSpace(s.signingConfig.EncryptionKeyID) == "" {
		return nil, nil
	}

	protector, err := platformcrypto.NewPrivateKeyProtector(s.signingConfig.EncryptionKey, s.signingConfig.EncryptionKeyID)
	if err != nil {
		return nil, fmt.Errorf("create registration private key protector: %w", err)
	}

	return protector, nil
}

func (s *RegistrationService) upsertRegistrationSigningKey(ctx context.Context, userID string, keyPair platformcrypto.KeyPair, privateKeyProtector *platformcrypto.PrivateKeyProtector) error {
	rawPublicKey, err := decodeRegistrationPublicKey(keyPair.PublicKey)
	if err != nil {
		return fmt.Errorf("prepare registration signing key: %w", err)
	}
	fingerprint := registrationPublicKeyFingerprint(rawPublicKey)

	params := UpsertSigningKeyParams{
		UserID:         userID,
		PublicKey:      strings.TrimSpace(keyPair.PublicKey),
		Algorithm:      "ed25519",
		KeyFingerprint: fingerprint,
		Status:         "active",
	}

	if privateKeyProtector == nil {
		log.Printf("registration signing key: backend-managed signing key was not stored for user %s because encryption config is missing", userID)
		return s.repository.UpsertSigningKey(ctx, params)
	}

	encryptedPrivateKey, err := privateKeyProtector.EncryptPrivateKey(keyPair.PrivateKey, userID, fingerprint, "ed25519")
	if err != nil {
		return fmt.Errorf("encrypt registration private key: %w", err)
	}

	now := time.Now().UTC()
	params.EncryptedPrivateKey = &encryptedPrivateKey
	params.PrivateKeyEncryptionKeyID = &s.signingConfig.EncryptionKeyID
	params.PrivateKeyEncryptedAt = &now

	return s.repository.UpsertSigningKey(ctx, params)
}

func decodeRegistrationPublicKey(publicKey string) ([]byte, error) {
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(publicKey))
	if err != nil {
		return nil, fmt.Errorf("decode base64 public key: %w", err)
	}
	if len(decoded) != ed25519.PublicKeySize {
		return nil, fmt.Errorf("invalid ed25519 public key length: got %d, want %d", len(decoded), ed25519.PublicKeySize)
	}
	return decoded, nil
}

func registrationPublicKeyFingerprint(publicKey []byte) string {
	sum := sha256.Sum256(publicKey)
	return hex.EncodeToString(sum[:])
}

func normalizePhone(phone string) string {
	var digits []rune
	for _, r := range phone {
		if r >= '0' && r <= '9' {
			digits = append(digits, r)
		}
	}

	normalized := string(digits)
	if strings.HasPrefix(normalized, "7") && len(normalized) == 11 {
		return normalized[1:]
	}

	return normalized
}

func isValidPassword(password string, minLength int) bool {
	if utf8.RuneCountInString(password) < minLength {
		return false
	}

	if strings.TrimSpace(password) != password {
		return false
	}

	var hasLetter bool
	var hasDigit bool
	var hasSpecial bool

	for _, r := range password {
		switch {
		case unicode.IsLetter(r):
			hasLetter = true
		case unicode.IsDigit(r):
			hasDigit = true
		case unicode.IsSpace(r):
			continue
		default:
			hasSpecial = true
		}
	}

	return hasLetter && hasDigit && hasSpecial
}

func isValidHumanName(value string) bool {
	for _, r := range value {
		if !(isLatinLetter(r) || isCyrillicLetter(r) || unicode.IsSpace(r) || r == '-') {
			return false
		}
	}

	return value != ""
}

func isValidCyrillicHumanName(value string) bool {
	for _, r := range value {
		if !(isCyrillicLetter(r) || unicode.IsSpace(r) || r == '-') {
			return false
		}
	}

	return value != ""
}

func isValidCityName(value string) bool {
	for _, r := range value {
		if !(isCyrillicLetter(r) || unicode.IsSpace(r) || r == '-' || r == ',') {
			return false
		}
	}

	return value != ""
}

func isValidEmail(value string) bool {
	if strings.ContainsAny(value, " \t\n\r") {
		return false
	}

	if strings.Count(value, "@") != 1 {
		return false
	}

	parts := strings.Split(value, "@")
	localPart := parts[0]
	domainPart := parts[1]
	if localPart == "" || domainPart == "" {
		return false
	}

	dotIndex := strings.LastIndex(domainPart, ".")
	if dotIndex <= 0 {
		return false
	}

	namePart := domainPart[:dotIndex]
	tldPart := domainPart[dotIndex+1:]
	if len(namePart) < 1 || len(tldPart) < 2 {
		return false
	}

	return emailPattern.MatchString(value)
}

func exceedsMaxLength(value string, max int) bool {
	return utf8.RuneCountInString(value) > max
}

func isValidUsername(value string) bool {
	return usernamePattern.MatchString(value)
}

func hasConsistentNameScript(values ...string) bool {
	expectedScript := ""

	for _, value := range values {
		for _, r := range value {
			if unicode.IsSpace(r) || r == '-' {
				continue
			}

			currentScript := ""
			switch {
			case isLatinLetter(r):
				currentScript = "latin"
			case isCyrillicLetter(r):
				currentScript = "cyrillic"
			default:
				return false
			}

			if expectedScript == "" {
				expectedScript = currentScript
				continue
			}

			if currentScript != expectedScript {
				return false
			}
		}
	}

	return expectedScript != ""
}

func isLatinLetter(r rune) bool {
	return unicode.Is(unicode.Latin, r) && unicode.IsLetter(r)
}

func isCyrillicLetter(r rune) bool {
	return unicode.Is(unicode.Cyrillic, r) && unicode.IsLetter(r)
}

func joinNonEmpty(values ...string) string {
	parts := make([]string, 0, len(values))
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			parts = append(parts, trimmed)
		}
	}

	return strings.Join(parts, " ")
}
