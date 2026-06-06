package users

import "time"

type Role string

const (
	RoleClient Role = "client"
	RoleMaster Role = "master"
	RoleAdmin  Role = "admin"
)

type User struct {
	ID                    string
	Username              string
	Email                 string
	PasswordHash          string
	Role                  Role
	FullName              string
	LastName              string
	FirstName             string
	MiddleName            string
	Phone                 string
	City                  string
	ShowFullNameInProfile bool
	ShowCityInProfile     bool
	Bio                   string
	PublicKey             string
	CreatedAt             time.Time
}

type RegistrationInput struct {
	Username          string
	Email             string
	Password          string
	PasswordConfirm   string
	Role              Role
	LastName          string
	FirstName         string
	MiddleName        string
	Phone             string
	City              string
	ShowCityInProfile bool
	Bio               string
	StudioName        string
	AgreementAccepted bool
}

type RegistrationResult struct {
	UserID    string `json:"user_id"`
	Username  string `json:"username"`
	Email     string `json:"email"`
	Role      Role   `json:"role"`
	PublicKey string `json:"public_key"`
}

type UserProfile struct {
	ID                    string `json:"id"`
	Username              string `json:"username"`
	Role                  Role   `json:"role"`
	LastName              string `json:"last_name"`
	FirstName             string `json:"first_name"`
	MiddleName            string `json:"middle_name"`
	StudioName            string `json:"studio_name,omitempty"`
	City                  string `json:"city"`
	Bio                   string `json:"bio"`
	AvatarURL             string `json:"avatar_url,omitempty"`
	ShowFullNameInProfile bool   `json:"show_full_name_in_profile"`
	ShowCityInProfile     bool   `json:"show_city_in_profile"`
}

type PublicUserProfile struct {
	ID          string `json:"id"`
	Username    string `json:"username"`
	Role        Role   `json:"role"`
	DisplayName string `json:"display_name"`
	FullName    string `json:"-"`
	City        string `json:"city,omitempty"`
	Bio         string `json:"bio,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

type SecurityContact struct {
	Email string `json:"email"`
	Phone string `json:"phone"`
}

type ProfileUpdateInput struct {
	LastName              *string
	FirstName             *string
	MiddleName            *string
	StudioName            *string
	City                  *string
	Bio                   *string
	ShowFullNameInProfile *bool
	ShowCityInProfile     *bool
}
