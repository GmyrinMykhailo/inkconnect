package users

import (
	"context"
	"errors"
	"testing"
	"time"

	platformcrypto "inkconnect/internal/platform/crypto"

	"golang.org/x/crypto/bcrypt"
)

func TestAuthenticationLoginCreatesSessionWithTokenHash(t *testing.T) {
	repository := newFakeAuthenticationRepository(t, "Strong123!")
	service := NewAuthenticationService(repository, 2*time.Hour)

	before := time.Now()
	result, err := service.Login(context.Background(), LoginInput{
		Email:    "  USER@EXAMPLE.COM  ",
		Password: "Strong123!",
	}, "test-agent", "127.0.0.1")
	after := time.Now()
	if err != nil {
		t.Fatalf("Login returned error: %v", err)
	}

	if repository.findEmail != "user@example.com" {
		t.Fatalf("FindUserByEmail email = %q, want user@example.com", repository.findEmail)
	}
	if !repository.createSessionCalled {
		t.Fatal("CreateSession should be called")
	}
	if repository.createdSession.UserID != "user-1" {
		t.Fatalf("session user id = %q, want user-1", repository.createdSession.UserID)
	}
	if repository.createdSession.UserAgent != "test-agent" {
		t.Fatalf("session user agent = %q, want test-agent", repository.createdSession.UserAgent)
	}
	if repository.createdSession.IPAddress != "127.0.0.1" {
		t.Fatalf("session ip address = %q, want 127.0.0.1", repository.createdSession.IPAddress)
	}
	if result.SessionToken == "" {
		t.Fatal("session token should not be empty")
	}
	if repository.createdSession.SessionHash == "" {
		t.Fatal("session hash should not be empty")
	}
	if repository.createdSession.SessionHash == result.SessionToken {
		t.Fatal("stored session value should be hash, not raw token")
	}
	if got := platformcrypto.GenerateTokenHash(result.SessionToken); got != repository.createdSession.SessionHash {
		t.Fatalf("stored session hash = %q, want %q", repository.createdSession.SessionHash, got)
	}

	minExpiresAt := before.Add(2 * time.Hour)
	maxExpiresAt := after.Add(2 * time.Hour)
	if result.ExpiresAt.Before(minExpiresAt) || result.ExpiresAt.After(maxExpiresAt) {
		t.Fatalf("expires at = %s, want between %s and %s", result.ExpiresAt, minExpiresAt, maxExpiresAt)
	}
	if !repository.createdSession.ExpiresAt.Equal(result.ExpiresAt) {
		t.Fatalf("created session expires at = %s, want result expires at %s", repository.createdSession.ExpiresAt, result.ExpiresAt)
	}
}

func TestAuthenticationLoginReturnsAuthenticatedUser(t *testing.T) {
	repository := newFakeAuthenticationRepository(t, "Strong123!")
	service := NewAuthenticationService(repository, time.Hour)

	result, err := service.Login(context.Background(), LoginInput{
		Email:    "user@example.com",
		Password: "Strong123!",
	}, "", "")
	if err != nil {
		t.Fatalf("Login returned error: %v", err)
	}

	expected := AuthenticatedUser{
		ID:         "user-1",
		Username:   "artist",
		StudioName: "Ink Studio",
		Email:      "user@example.com",
		Role:       RoleMaster,
		PublicKey:  "public-key",
	}
	if result.User != expected {
		t.Fatalf("user = %#v, want %#v", result.User, expected)
	}
}

func TestAuthenticationLoginRejectsEmptyEmailOrPassword(t *testing.T) {
	tests := []struct {
		name  string
		input LoginInput
	}{
		{name: "empty email", input: LoginInput{Password: "Strong123!"}},
		{name: "empty password", input: LoginInput{Email: "user@example.com"}},
		{name: "blank email", input: LoginInput{Email: "   ", Password: "Strong123!"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := newFakeAuthenticationRepository(t, "Strong123!")
			service := NewAuthenticationService(repository, time.Hour)

			_, err := service.Login(context.Background(), tt.input, "", "")
			if !errors.Is(err, ErrInvalidCredentials) {
				t.Fatalf("Login error = %v, want %v", err, ErrInvalidCredentials)
			}
			if repository.findCalled {
				t.Fatal("FindUserByEmail should not be called")
			}
			if repository.createSessionCalled {
				t.Fatal("CreateSession should not be called")
			}
		})
	}
}

func TestAuthenticationLoginRejectsUnknownUserAsInvalidCredentials(t *testing.T) {
	repository := newFakeAuthenticationRepository(t, "Strong123!")
	repository.findErr = ErrUserNotFound
	service := NewAuthenticationService(repository, time.Hour)

	_, err := service.Login(context.Background(), LoginInput{
		Email:    "missing@example.com",
		Password: "Strong123!",
	}, "", "")
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("Login error = %v, want %v", err, ErrInvalidCredentials)
	}
	if repository.createSessionCalled {
		t.Fatal("CreateSession should not be called")
	}
}

func TestAuthenticationLoginRejectsWrongPassword(t *testing.T) {
	repository := newFakeAuthenticationRepository(t, "Strong123!")
	service := NewAuthenticationService(repository, time.Hour)

	_, err := service.Login(context.Background(), LoginInput{
		Email:    "user@example.com",
		Password: "Wrong123!",
	}, "", "")
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("Login error = %v, want %v", err, ErrInvalidCredentials)
	}
	if repository.createSessionCalled {
		t.Fatal("CreateSession should not be called")
	}
}

func TestAuthenticationLoginPropagatesRepositoryErrors(t *testing.T) {
	findErr := errors.New("find user failed")
	createErr := errors.New("create session failed")

	t.Run("find user", func(t *testing.T) {
		repository := newFakeAuthenticationRepository(t, "Strong123!")
		repository.findErr = findErr
		service := NewAuthenticationService(repository, time.Hour)

		_, err := service.Login(context.Background(), LoginInput{
			Email:    "user@example.com",
			Password: "Strong123!",
		}, "", "")
		if !errors.Is(err, findErr) {
			t.Fatalf("Login error = %v, want %v", err, findErr)
		}
	})

	t.Run("create session", func(t *testing.T) {
		repository := newFakeAuthenticationRepository(t, "Strong123!")
		repository.createSessionErr = createErr
		service := NewAuthenticationService(repository, time.Hour)

		_, err := service.Login(context.Background(), LoginInput{
			Email:    "user@example.com",
			Password: "Strong123!",
		}, "", "")
		if !errors.Is(err, createErr) {
			t.Fatalf("Login error = %v, want %v", err, createErr)
		}
	})
}

func TestAuthenticationAuthenticateUsesTokenHash(t *testing.T) {
	repository := newFakeAuthenticationRepository(t, "Strong123!")
	repository.sessionUser = AuthenticatedUser{ID: "user-1", Username: "artist", Role: RoleMaster}
	service := NewAuthenticationService(repository, time.Hour)

	user, err := service.Authenticate(context.Background(), "session-token")
	if err != nil {
		t.Fatalf("Authenticate returned error: %v", err)
	}
	if repository.findSessionHash != platformcrypto.GenerateTokenHash("session-token") {
		t.Fatalf("session hash = %q, want token hash", repository.findSessionHash)
	}
	if repository.findSessionHash == "session-token" {
		t.Fatal("repository should receive token hash, not raw token")
	}
	if user != repository.sessionUser {
		t.Fatalf("user = %#v, want %#v", user, repository.sessionUser)
	}
}

func TestAuthenticationAuthenticateRejectsEmptyToken(t *testing.T) {
	for _, token := range []string{"", "   "} {
		t.Run("token="+token, func(t *testing.T) {
			repository := newFakeAuthenticationRepository(t, "Strong123!")
			service := NewAuthenticationService(repository, time.Hour)

			_, err := service.Authenticate(context.Background(), token)
			if !errors.Is(err, ErrSessionNotFound) {
				t.Fatalf("Authenticate error = %v, want %v", err, ErrSessionNotFound)
			}
			if repository.findSessionCalled {
				t.Fatal("FindUserBySessionHash should not be called")
			}
		})
	}
}

func TestAuthenticationAuthenticatePropagatesSessionLookupError(t *testing.T) {
	for _, wantErr := range []error{ErrSessionNotFound, errors.New("session lookup failed")} {
		t.Run(wantErr.Error(), func(t *testing.T) {
			repository := newFakeAuthenticationRepository(t, "Strong123!")
			repository.findSessionErr = wantErr
			service := NewAuthenticationService(repository, time.Hour)

			_, err := service.Authenticate(context.Background(), "session-token")
			if !errors.Is(err, wantErr) {
				t.Fatalf("Authenticate error = %v, want %v", err, wantErr)
			}
		})
	}
}

func TestAuthenticationLogoutDeletesSessionByHash(t *testing.T) {
	repository := newFakeAuthenticationRepository(t, "Strong123!")
	service := NewAuthenticationService(repository, time.Hour)

	if err := service.Logout(context.Background(), "session-token"); err != nil {
		t.Fatalf("Logout returned error: %v", err)
	}
	if !repository.deleteSessionCalled {
		t.Fatal("DeleteSessionByHash should be called")
	}
	if repository.deletedSessionHash != platformcrypto.GenerateTokenHash("session-token") {
		t.Fatalf("deleted session hash = %q, want token hash", repository.deletedSessionHash)
	}
	if repository.deletedSessionHash == "session-token" {
		t.Fatal("repository should receive token hash, not raw token")
	}
}

func TestAuthenticationLogoutIgnoresEmptyToken(t *testing.T) {
	for _, token := range []string{"", "   "} {
		t.Run("token="+token, func(t *testing.T) {
			repository := newFakeAuthenticationRepository(t, "Strong123!")
			service := NewAuthenticationService(repository, time.Hour)

			if err := service.Logout(context.Background(), token); err != nil {
				t.Fatalf("Logout returned error: %v", err)
			}
			if repository.deleteSessionCalled {
				t.Fatal("DeleteSessionByHash should not be called")
			}
		})
	}
}

type fakeAuthenticationRepository struct {
	user UserWithPassword

	findCalled bool
	findEmail  string
	findErr    error

	createSessionCalled bool
	createdSession      CreateSessionParams
	createSessionErr    error

	findSessionCalled bool
	findSessionHash   string
	sessionUser       AuthenticatedUser
	findSessionErr    error

	deleteSessionCalled bool
	deletedSessionHash  string
	deleteSessionErr    error
}

func newFakeAuthenticationRepository(t *testing.T, password string) *fakeAuthenticationRepository {
	t.Helper()
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	return &fakeAuthenticationRepository{
		user: UserWithPassword{
			ID:           "user-1",
			Username:     "artist",
			StudioName:   "Ink Studio",
			Email:        "user@example.com",
			PasswordHash: string(passwordHash),
			Role:         RoleMaster,
			PublicKey:    "public-key",
		},
	}
}

func (r *fakeAuthenticationRepository) FindUserByEmail(ctx context.Context, email string) (UserWithPassword, error) {
	r.findCalled = true
	r.findEmail = email
	if r.findErr != nil {
		return UserWithPassword{}, r.findErr
	}
	return r.user, nil
}

func (r *fakeAuthenticationRepository) CreateSession(ctx context.Context, params CreateSessionParams) error {
	r.createSessionCalled = true
	r.createdSession = params
	if r.createSessionErr != nil {
		return r.createSessionErr
	}
	return nil
}

func (r *fakeAuthenticationRepository) FindUserBySessionHash(ctx context.Context, sessionHash string) (AuthenticatedUser, error) {
	r.findSessionCalled = true
	r.findSessionHash = sessionHash
	if r.findSessionErr != nil {
		return AuthenticatedUser{}, r.findSessionErr
	}
	return r.sessionUser, nil
}

func (r *fakeAuthenticationRepository) DeleteSessionByHash(ctx context.Context, sessionHash string) error {
	r.deleteSessionCalled = true
	r.deletedSessionHash = sessionHash
	if r.deleteSessionErr != nil {
		return r.deleteSessionErr
	}
	return nil
}
