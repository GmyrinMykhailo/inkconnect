package users

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	platformcrypto "inkconnect/internal/platform/crypto"

	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrSessionNotFound    = errors.New("session not found")
)

type AuthenticationService struct {
	repository      authenticationRepository
	sessionDuration time.Duration
}

type authenticationRepository interface {
	FindUserByEmail(ctx context.Context, email string) (UserWithPassword, error)
	CreateSession(ctx context.Context, params CreateSessionParams) error
	FindUserBySessionHash(ctx context.Context, sessionHash string) (AuthenticatedUser, error)
	DeleteSessionByHash(ctx context.Context, sessionHash string) error
}

func NewAuthenticationService(repository authenticationRepository, sessionDuration time.Duration) *AuthenticationService {
	return &AuthenticationService{
		repository:      repository,
		sessionDuration: sessionDuration,
	}
}

func (s *AuthenticationService) Login(ctx context.Context, input LoginInput, userAgent, ipAddress string) (LoginResult, error) {
	email := strings.TrimSpace(strings.ToLower(input.Email))
	if email == "" || input.Password == "" {
		return LoginResult{}, ErrInvalidCredentials
	}

	userWithPassword, err := s.repository.FindUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, ErrUserNotFound) {
			return LoginResult{}, ErrInvalidCredentials
		}
		return LoginResult{}, err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(userWithPassword.PasswordHash), []byte(input.Password)); err != nil {
		return LoginResult{}, ErrInvalidCredentials
	}

	token, tokenHash, err := platformcrypto.GenerateSessionToken()
	if err != nil {
		return LoginResult{}, fmt.Errorf("generate session token: %w", err)
	}

	expiresAt := time.Now().Add(s.sessionDuration)
	if err := s.repository.CreateSession(ctx, CreateSessionParams{
		UserID:      userWithPassword.ID,
		SessionHash: tokenHash,
		ExpiresAt:   expiresAt,
		UserAgent:   userAgent,
		IPAddress:   ipAddress,
	}); err != nil {
		return LoginResult{}, err
	}

	return LoginResult{
		User: AuthenticatedUser{
			ID:         userWithPassword.ID,
			Username:   userWithPassword.Username,
			StudioName: userWithPassword.StudioName,
			Email:      userWithPassword.Email,
			Role:       userWithPassword.Role,
			PublicKey:  userWithPassword.PublicKey,
		},
		SessionToken: token,
		ExpiresAt:    expiresAt,
	}, nil
}

func (s *AuthenticationService) Authenticate(ctx context.Context, sessionToken string) (AuthenticatedUser, error) {
	if strings.TrimSpace(sessionToken) == "" {
		return AuthenticatedUser{}, ErrSessionNotFound
	}

	sessionUser, err := s.repository.FindUserBySessionHash(ctx, platformcrypto.GenerateTokenHash(sessionToken))
	if err != nil {
		return AuthenticatedUser{}, err
	}

	return sessionUser, nil
}

func (s *AuthenticationService) Logout(ctx context.Context, sessionToken string) error {
	if strings.TrimSpace(sessionToken) == "" {
		return nil
	}

	return s.repository.DeleteSessionByHash(ctx, platformcrypto.GenerateTokenHash(sessionToken))
}
