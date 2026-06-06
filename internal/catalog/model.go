package catalog

import "errors"

type ServiceType string
type ScheduleIntervalType string

const (
	ServiceTypeSession      ServiceType = "session"
	ServiceTypeConsultation ServiceType = "consultation"
	ServiceTypeSketch       ServiceType = "sketch"

	ScheduleIntervalTypeWork  ScheduleIntervalType = "work"
	ScheduleIntervalTypeBreak ScheduleIntervalType = "break"
)

var (
	ErrServiceNotFound      = errors.New("service not found")
	ErrServiceTitleRequired = errors.New("service title is required")
	ErrServiceInvalidType   = errors.New("service type is invalid")
	ErrServiceInvalidPrice  = errors.New("service price is invalid")
	ErrServiceInvalidTime   = errors.New("service duration is invalid")
	ErrServiceFieldTooLong  = errors.New("service field exceeds max length")
	ErrScheduleInvalidDay   = errors.New("schedule day is invalid")
	ErrScheduleInvalidTime  = errors.New("schedule interval time is invalid")
	ErrScheduleInvalidType  = errors.New("schedule interval type is invalid")
	ErrScheduleOverlap      = errors.New("schedule intervals must not overlap")
)

type MasterService struct {
	ID            string      `json:"id"`
	Name          string      `json:"name"`
	Description   string      `json:"description"`
	Type          ServiceType `json:"type"`
	DurationHours *float64    `json:"duration_hours"`
	Price         int         `json:"price"`
	UseAutoPrice  bool        `json:"use_auto_price"`
	FromPrice     bool        `json:"from_price"`
}

type MasterSettings struct {
	Category            string   `json:"category"`
	Styles              []string `json:"styles"`
	MinSessionPrice     int      `json:"min_session_price"`
	HourlyRate          int      `json:"hourly_rate"`
	BreakBetweenClients string   `json:"break_between_clients"`
}

type ServiceInput struct {
	Name          string
	Description   string
	Type          ServiceType
	DurationHours *float64
	Price         int
	UseAutoPrice  bool
	FromPrice     bool
}

type MasterSettingsInput struct {
	Category            string
	Styles              []string
	MinSessionPrice     int
	HourlyRate          int
	BreakBetweenClients string
}

type MasterWorkSchedule struct {
	Days []WorkScheduleDay `json:"days"`
}

type WorkScheduleDay struct {
	DayIndex  int                    `json:"day_index"`
	Enabled   bool                   `json:"enabled"`
	Intervals []WorkScheduleInterval `json:"intervals"`
}

type WorkScheduleInterval struct {
	Type        ScheduleIntervalType `json:"type"`
	StartMinute int                  `json:"start_minute"`
	EndMinute   int                  `json:"end_minute"`
}
