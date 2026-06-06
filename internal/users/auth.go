package users

import "time"

type AuthenticatedUser struct {
	ID         string `json:"id"`
	Username   string `json:"username"`
	StudioName string `json:"studio_name"`
	Email      string `json:"email"`
	Role       Role   `json:"role"`
	PublicKey  string `json:"public_key"`
}

type LoginInput struct {
	Email    string
	Password string
}

type LoginResult struct {
	User         AuthenticatedUser `json:"user"`
	SessionToken string            `json:"session_token"`
	ExpiresAt    time.Time         `json:"expires_at"`
}
