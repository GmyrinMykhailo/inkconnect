package recommendations

import (
	"errors"
	"time"

	"inkconnect/internal/appointments"
)

const (
	StatusDraft    = "draft"
	StatusSent     = "sent"
	StatusApproved = "approved"
)

var (
	ErrAppointmentNotFound  = errors.New("appointment not found")
	ErrForbidden            = errors.New("recommendation access forbidden")
	ErrInvalidInput         = errors.New("invalid recommendation input")
	ErrAppointmentNotReady  = errors.New("appointment is not ready for recommendations")
	ErrRecommendationsNone  = errors.New("recommendations not found")
	ErrRecommendationsSent  = errors.New("recommendations already sent")
	ErrRecommendationsDone  = errors.New("recommendations already approved")
	ErrRecommendationsDraft = errors.New("recommendations are not sent")
)

type AppointmentAccess struct {
	ID       string
	ClientID string
	MasterID string
	Status   string
}

type Step struct {
	ID            string     `json:"id,omitempty"`
	StepNumber    int        `json:"step_number"`
	Title         string     `json:"title"`
	Description   string     `json:"description"`
	DueOffsetDays *int       `json:"due_offset_days,omitempty"`
	DueAt         *time.Time `json:"due_at,omitempty"`
}

type Plan struct {
	AppointmentID string     `json:"appointment_id"`
	JournalID     string     `json:"journal_id,omitempty"`
	Status        string     `json:"status"`
	Steps         []Step     `json:"steps"`
	CreatedBy     string     `json:"created_by,omitempty"`
	CreatedAt     *time.Time `json:"created_at,omitempty"`
	SentAt        *time.Time `json:"sent_at,omitempty"`
	ApprovedAt    *time.Time `json:"approved_at,omitempty"`
}

type Response struct {
	Appointment     appointments.AppointmentView `json:"appointment"`
	Recommendations Plan                         `json:"recommendations"`
}
