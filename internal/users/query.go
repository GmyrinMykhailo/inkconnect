package users

import "time"

type UserWithPassword struct {
	ID           string
	Username     string
	StudioName   string
	Email        string
	PasswordHash string
	Role         Role
	PublicKey    string
}

type PublicMasterProfile struct {
	ID              string                    `json:"id"`
	Username        string                    `json:"username"`
	DisplayName     string                    `json:"display_name"`
	FullName        string                    `json:"-"`
	StudioName      string                    `json:"studio_name,omitempty"`
	Role            Role                      `json:"role"`
	City            string                    `json:"city,omitempty"`
	Bio             string                    `json:"bio,omitempty"`
	AvatarURL       string                    `json:"avatar_url,omitempty"`
	Category        string                    `json:"category"`
	Styles          []string                  `json:"styles"`
	MinSessionPrice int                       `json:"min_session_price"`
	HourlyRate      int                       `json:"hourly_rate"`
	Rating          float64                   `json:"rating"`
	ReviewCount     int                       `json:"review_count"`
	IsVerified      bool                      `json:"is_verified"`
	IsFavorite      bool                      `json:"is_favorite"`
	Services        []PublicMasterService     `json:"services,omitempty"`
	Schedule        []PublicMasterScheduleDay `json:"schedule,omitempty"`
}

type PublicMasterService struct {
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	Description   string   `json:"description"`
	Type          string   `json:"type"`
	DurationHours *float64 `json:"duration_hours"`
	Price         int      `json:"price"`
	UseAutoPrice  bool     `json:"use_auto_price"`
	FromPrice     bool     `json:"from_price"`
}

type PublicMasterScheduleDay struct {
	DayIndex  int                            `json:"day_index"`
	Enabled   bool                           `json:"enabled"`
	Intervals []PublicMasterScheduleInterval `json:"intervals"`
}

type PublicMasterScheduleInterval struct {
	Type        string `json:"type"`
	StartMinute int    `json:"start_minute"`
	EndMinute   int    `json:"end_minute"`
}

type CreateSessionParams struct {
	UserID      string
	SessionHash string
	ExpiresAt   time.Time
	UserAgent   string
	IPAddress   string
}
