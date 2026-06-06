package users

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

var (
	ErrCurrentPasswordRequired = errors.New("current password is required")
	ErrCurrentPasswordInvalid  = errors.New("current password is invalid")
)

type SecurityService struct {
	repository Repository
}

type PasswordChangeInput struct {
	CurrentPassword string
	NewPassword     string
	PasswordConfirm string
}

type EmailUpdateInput struct {
	CurrentPassword string
	Email           string
}

type PhoneUpdateInput struct {
	CurrentPassword string
	Phone           string
}

type AccountDeleteInput struct {
	CurrentPassword string
}

func NewSecurityService(repository Repository) *SecurityService {
	return &SecurityService{repository: repository}
}

func (s *SecurityService) GetContact(ctx context.Context, userID string) (SecurityContact, error) {
	return s.repository.FindSecurityContactByUserID(ctx, userID)
}

func (s *SecurityService) ChangePassword(ctx context.Context, userID string, input PasswordChangeInput) error {
	currentPassword := input.CurrentPassword
	newPassword := input.NewPassword
	passwordConfirm := input.PasswordConfirm

	if strings.TrimSpace(currentPassword) == "" {
		return ErrCurrentPasswordRequired
	}
	if exceedsMaxLength(currentPassword, 128) || exceedsMaxLength(newPassword, 128) || exceedsMaxLength(passwordConfirm, 128) {
		return ErrFieldTooLong
	}
	if !isValidPassword(newPassword, 10) {
		return ErrWeakPassword
	}
	if !isValidPassword(passwordConfirm, 10) {
		return ErrPasswordConfirmWeak
	}
	if newPassword != passwordConfirm {
		return ErrPasswordMismatch
	}

	if err := s.verifyCurrentPassword(ctx, userID, currentPassword); err != nil {
		return err
	}

	nextHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash new password: %w", err)
	}

	return s.repository.UpdatePasswordHash(ctx, userID, string(nextHash))
}

func (s *SecurityService) UpdateEmail(ctx context.Context, userID string, input EmailUpdateInput) (SecurityContact, error) {
	currentPassword := input.CurrentPassword
	email := strings.TrimSpace(strings.ToLower(input.Email))

	if err := s.verifyCurrentPassword(ctx, userID, currentPassword); err != nil {
		return SecurityContact{}, err
	}
	if email == "" {
		return SecurityContact{}, ErrEmailRequired
	}
	if exceedsMaxLength(email, 128) {
		return SecurityContact{}, ErrFieldTooLong
	}
	if !isValidEmail(email) {
		return SecurityContact{}, ErrInvalidEmail
	}

	exists, err := s.repository.EmailExistsForOtherUser(ctx, email, userID)
	if err != nil {
		return SecurityContact{}, err
	}
	if exists {
		return SecurityContact{}, ErrEmailAlreadyExists
	}

	return s.repository.UpdateEmail(ctx, userID, email)
}

func (s *SecurityService) UpdatePhone(ctx context.Context, userID string, input PhoneUpdateInput) (SecurityContact, error) {
	currentPassword := input.CurrentPassword
	phoneDigits := normalizePhone(input.Phone)

	if err := s.verifyCurrentPassword(ctx, userID, currentPassword); err != nil {
		return SecurityContact{}, err
	}
	if phoneDigits == "" {
		return SecurityContact{}, ErrPhoneRequired
	}
	if len(phoneDigits) != 10 {
		return SecurityContact{}, ErrInvalidPhone
	}

	phone := "+7" + phoneDigits
	exists, err := s.repository.PhoneExistsForOtherUser(ctx, phone, userID)
	if err != nil {
		return SecurityContact{}, err
	}
	if exists {
		return SecurityContact{}, ErrPhoneAlreadyExists
	}

	return s.repository.UpdatePhone(ctx, userID, phone)
}

func (s *SecurityService) DeleteAccount(ctx context.Context, userID string, input AccountDeleteInput) error {
	if err := s.verifyCurrentPassword(ctx, userID, input.CurrentPassword); err != nil {
		return err
	}

	return s.repository.DeactivateUserAndDeleteSessions(ctx, userID)
}

func (s *SecurityService) verifyCurrentPassword(ctx context.Context, userID string, currentPassword string) error {
	if strings.TrimSpace(currentPassword) == "" {
		return ErrCurrentPasswordRequired
	}
	if exceedsMaxLength(currentPassword, 128) {
		return ErrFieldTooLong
	}

	passwordHash, err := s.repository.FindPasswordHashByUserID(ctx, userID)
	if err != nil {
		return err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(currentPassword)); err != nil {
		return ErrCurrentPasswordInvalid
	}

	return nil
}
