package appointments

import "time"

const (
	StatusPending   = "pending"
	StatusConfirmed = "confirmed"
	StatusRejected  = "rejected"
	StatusCompleted = "completed"
	StatusCancelled = "cancelled"
)

const (
	AvailabilityReasonAvailable       = "available"
	AvailabilityReasonBreak           = "break"
	AvailabilityReasonBusy            = "busy"
	AvailabilityReasonTooShort        = "too_short"
	AvailabilityReasonOutsideSchedule = "outside_schedule"
)

const (
	DurationWarningOutsideSchedule = "outside_schedule"
	DurationWarningOverlap         = "overlaps_other_appointment"
)

type ServiceSummary struct {
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	Description   string   `json:"description"`
	Type          string   `json:"type"`
	Category      string   `json:"category,omitempty"`
	Style         string   `json:"style,omitempty"`
	DurationHours *float64 `json:"duration_hours"`
	Price         int      `json:"price"`
	UseAutoPrice  bool     `json:"use_auto_price"`
	FromPrice     bool     `json:"from_price"`
}

type PersonSummary struct {
	ID          string `json:"id"`
	Username    string `json:"username"`
	AccountRole string `json:"account_role"`
	IsMaster    bool   `json:"is_master"`
	DisplayName string `json:"display_name"`
	City        string `json:"city,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

type AppointmentView struct {
	ID                       string         `json:"id"`
	Status                   string         `json:"status"`
	ScheduledAt              time.Time      `json:"scheduled_at"`
	ScheduledEndAt           *time.Time     `json:"scheduled_end_at,omitempty"`
	DurationMinutes          int            `json:"duration_minutes,omitempty"`
	ClientNote               string         `json:"client_note,omitempty"`
	MasterNote               string         `json:"master_note,omitempty"`
	CreatedAt                time.Time      `json:"created_at"`
	Client                   PersonSummary  `json:"client"`
	Master                   PersonSummary  `json:"master"`
	Service                  ServiceSummary `json:"service"`
	RecommendationStatus     string         `json:"recommendation_status,omitempty"`
	RecommendationStepsCount int            `json:"recommendation_steps_count"`
	JournalID                string         `json:"journal_id,omitempty"`
	JournalStepsDone         int            `json:"journal_steps_done"`
	JournalStepsTotal        int            `json:"journal_steps_total"`
}

type AppointmentCounts struct {
	All       int `json:"all"`
	Pending   int `json:"pending"`
	Confirmed int `json:"confirmed"`
	Cancelled int `json:"cancelled"`
	Rejected  int `json:"rejected"`
	Completed int `json:"completed"`
}

type CreateAppointmentInput struct {
	ClientID        string
	MasterUsername  string
	ServiceID       string
	ScheduledAt     time.Time
	DurationMinutes int
	ClientNote      string
}

type UpdateDurationResult struct {
	Appointment AppointmentView `json:"appointment"`
	Warnings    []string        `json:"warnings"`
}

type AvailabilitySlot struct {
	Time      string `json:"time"`
	Available bool   `json:"available"`
	Reason    string `json:"reason"`
}

type AvailabilityResult struct {
	Date  string             `json:"date"`
	Slots []AvailabilitySlot `json:"slots"`
}

type scheduleInterval struct {
	Type        string `json:"type"`
	StartMinute int    `json:"start_minute"`
	EndMinute   int    `json:"end_minute"`
}

type busyWindow struct {
	StartMinute     int
	DurationMinutes int
}
