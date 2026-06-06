package journal

import (
	"encoding/json"
	"errors"
	"time"

	"inkconnect/internal/appointments"
)

var (
	ErrJournalNotFound     = errors.New("journal not found")
	ErrAppointmentNotFound = errors.New("appointment not found")
	ErrForbidden           = errors.New("journal access forbidden")
	ErrInvalidCommit       = errors.New("invalid signed journal commit")
	ErrInvalidDeadline     = errors.New("invalid journal deadline extension")
	ErrInvalidProblem      = errors.New("invalid journal client problem report")
	ErrInvalidReplacement  = errors.New("invalid journal replacement request")
	ErrInvalidSignature    = errors.New("invalid journal event signature")
	ErrInvalidNotice       = errors.New("invalid journal unavailability notice")
	ErrInvalidStop         = errors.New("invalid journal stop request")
	ErrNotReady            = errors.New("journal is not ready")
	ErrStepNotFound        = errors.New("journal step not found")
	ErrSigningKeyNotFound  = errors.New("active signing key not found")
)

type Journal struct {
	ID                  string        `json:"id"`
	AppointmentID       string        `json:"appointment_id"`
	ClientID            string        `json:"client_id"`
	MasterID            string        `json:"master_id"`
	IntegrityStatus     bool          `json:"integrity_status"`
	LastVerifiedAt      *time.Time    `json:"last_verified_at,omitempty"`
	CreatedAt           time.Time     `json:"created_at"`
	Status              JournalStatus `json:"status"`
	RootJournalID       *string       `json:"root_journal_id,omitempty"`
	ParentJournalID     *string       `json:"parent_journal_id,omitempty"`
	ReplacedByJournalID *string       `json:"replaced_by_journal_id,omitempty"`
	VersionNumber       int           `json:"version_number"`
	ActivatedAt         *time.Time    `json:"activated_at,omitempty"`
	StoppedAt           *time.Time    `json:"stopped_at,omitempty"`
	CompletedAt         *time.Time    `json:"completed_at,omitempty"`
	StopReason          *string       `json:"stop_reason,omitempty"`
	ReplacementReason   *string       `json:"replacement_reason,omitempty"`
	FinalHash           *string       `json:"final_hash,omitempty"`
}

type Step struct {
	ID            string     `json:"id"`
	StepNumber    int        `json:"step_number"`
	DayNumber     int        `json:"day_number"`
	Title         string     `json:"title"`
	Description   string     `json:"description"`
	DueOffsetDays *int       `json:"due_offset_days,omitempty"`
	DueAt         *time.Time `json:"due_at,omitempty"`
	DeadlineAt    *time.Time `json:"deadline_at,omitempty"`
	Status        string     `json:"status,omitempty"`
	CompletedAt   *time.Time `json:"completed_at,omitempty"`
	ConfirmedAt   *time.Time `json:"confirmed_at,omitempty"`
}

type Progress struct {
	StepsDone  int `json:"steps_done"`
	StepsTotal int `json:"steps_total"`
	Percent    int `json:"percent"`
}

type Summary struct {
	Journal     Journal                      `json:"journal"`
	Appointment appointments.AppointmentView `json:"appointment"`
	Progress    Progress                     `json:"progress"`
}

type Detail struct {
	Journal     Journal                      `json:"journal"`
	Appointment appointments.AppointmentView `json:"appointment"`
	Steps       []Step                       `json:"steps"`
	Progress    Progress                     `json:"progress"`
}

type AppointmentJournalSummary struct {
	ID                   string          `json:"id"`
	AppointmentID        string          `json:"appointment_id"`
	Status               JournalStatus   `json:"status"`
	VersionNumber        int             `json:"version_number"`
	ParentJournalID      *string         `json:"parent_journal_id"`
	RootJournalID        string          `json:"root_journal_id"`
	ReplacedByJournalID  *string         `json:"replaced_by_journal_id"`
	CreatedAt            time.Time       `json:"created_at"`
	StoppedAt            *time.Time      `json:"stopped_at"`
	CompletedAt          *time.Time      `json:"completed_at"`
	StopReason           *string         `json:"stop_reason"`
	ReplacementReason    *string         `json:"replacement_reason"`
	FinalHash            *string         `json:"final_hash"`
	StepsCount           int             `json:"steps_count"`
	CompletedStepsCount  int             `json:"completed_steps_count"`
	PendingStepsCount    int             `json:"pending_steps_count"`
	CancelledStepsCount  int             `json:"cancelled_steps_count"`
	IsOpen               bool            `json:"is_open"`
	IntegrityCheckStatus IntegrityStatus `json:"integrity_check_status"`
	IntegrityValid       bool            `json:"integrity_valid"`
	IntegrityEventsCount int             `json:"integrity_events_count"`
}

type IntegrityStatus string

const (
	IntegrityStatusValid   IntegrityStatus = "valid"
	IntegrityStatusPartial IntegrityStatus = "partial"
	IntegrityStatusInvalid IntegrityStatus = "invalid"
)

type IntegrityReport struct {
	JournalID                  string          `json:"journal_id"`
	Valid                      bool            `json:"valid"`
	Status                     IntegrityStatus `json:"status"`
	EventsCount                int             `json:"events_count"`
	HashedEventsCount          int             `json:"hashed_events_count"`
	UnhashedEventsCount        int             `json:"unhashed_events_count"`
	HasLegacyUnhashedEvents    bool            `json:"has_legacy_unhashed_events"`
	LastHash                   *string         `json:"last_hash"`
	JournalFinalHash           *string         `json:"journal_final_hash"`
	FinalHashMatches           bool            `json:"final_hash_matches"`
	FirstInvalidEventID        *string         `json:"first_invalid_event_id"`
	Issues                     []string        `json:"issues"`
	SignatureVerificationScope string          `json:"signature_verification_scope,omitempty"`
	SignedEventsCount          int             `json:"signed_events_count"`
	ValidSignaturesCount       int             `json:"valid_signatures_count"`
	InvalidSignaturesCount     int             `json:"invalid_signatures_count"`
	UnsignedHashedEventsCount  int             `json:"unsigned_hashed_events_count"`
}

type JournalStatus string

const (
	JournalStatusDraft                      JournalStatus = "draft"
	JournalStatusAwaitingClientConfirmation JournalStatus = "awaiting_client_confirmation"
	JournalStatusActive                     JournalStatus = "active"
	JournalStatusCompleted                  JournalStatus = "completed"
	JournalStatusStopped                    JournalStatus = "stopped"
	JournalStatusReplaced                   JournalStatus = "replaced"
)

type JournalStepStatus string

const (
	JournalStepStatusPending                   JournalStepStatus = "pending"
	JournalStepStatusCompletedByClient         JournalStepStatus = "completed_by_client"
	JournalStepStatusCancelledDueToJournalStop JournalStepStatus = "cancelled_due_to_journal_stop"
)

type JournalEventType string

const (
	JournalEventTypeJournalCreated                  JournalEventType = "journal_created"
	JournalEventTypeJournalActivated                JournalEventType = "journal_activated"
	JournalEventTypeClientConfirmedRecommendations  JournalEventType = "client_confirmed_recommendations"
	JournalEventTypeClientRequestedClarification    JournalEventType = "client_requested_clarification"
	JournalEventTypeStepAdded                       JournalEventType = "step_added"
	JournalEventTypeStepCompletedByClient           JournalEventType = "step_completed_by_client"
	JournalEventTypeClientUnavailabilityNoticeAdded JournalEventType = "client_unavailability_notice_added"
	JournalEventTypeDeadlineExtended                JournalEventType = "deadline_extended"
	JournalEventTypeClientProblemReported           JournalEventType = "client_problem_reported"
	JournalEventTypeJournalStopped                  JournalEventType = "journal_stopped"
	JournalEventTypeReplacementJournalCreated       JournalEventType = "replacement_journal_created"
	JournalEventTypeJournalCompleted                JournalEventType = "journal_completed"
	JournalEventTypeIntegrityChecked                JournalEventType = "integrity_checked"
)

type JournalActorRole string

const (
	JournalActorRoleClient JournalActorRole = "client"
	JournalActorRoleMaster JournalActorRole = "master"
	JournalActorRoleAdmin  JournalActorRole = "admin"
	JournalActorRoleSystem JournalActorRole = "system"
)

type SigningKeyStatus string

const (
	SigningKeyStatusActive  SigningKeyStatus = "active"
	SigningKeyStatusRevoked SigningKeyStatus = "revoked"
)

const SigningKeyAlgorithmEd25519 = "ed25519"

type JournalStep struct {
	ID                  string            `json:"id"`
	JournalID           string            `json:"journal_id"`
	DayNumber           int               `json:"day_number"`
	Title               string            `json:"title"`
	Description         string            `json:"description"`
	DeadlineAt          *time.Time        `json:"deadline_at,omitempty"`
	Status              JournalStepStatus `json:"status"`
	CompletedAt         *time.Time        `json:"completed_at,omitempty"`
	CompletedByClientID *string           `json:"completed_by_client_id,omitempty"`
	CreatedAt           time.Time         `json:"created_at"`
	UpdatedAt           time.Time         `json:"updated_at"`
}

type JournalEvent struct {
	ID           string           `json:"id"`
	JournalID    string           `json:"journal_id"`
	StepID       *string          `json:"step_id,omitempty"`
	EventType    JournalEventType `json:"event_type"`
	ActorID      string           `json:"actor_id"`
	ActorRole    JournalActorRole `json:"actor_role"`
	SigningKeyID *string          `json:"signing_key_id,omitempty"`
	PayloadJSON  json.RawMessage  `json:"payload_json"`
	Reason       *string          `json:"reason,omitempty"`
	PreviousHash *string          `json:"previous_hash,omitempty"`
	EventHash    *string          `json:"event_hash,omitempty"`
	Signature    *string          `json:"signature,omitempty"`
	CreatedAt    time.Time        `json:"created_at"`
}

type JournalEventView struct {
	ID           string           `json:"id"`
	JournalID    string           `json:"journal_id"`
	StepID       *string          `json:"step_id,omitempty"`
	EventType    JournalEventType `json:"event_type"`
	ActorRole    JournalActorRole `json:"actor_role"`
	PayloadJSON  json.RawMessage  `json:"payload_json"`
	Reason       *string          `json:"reason,omitempty"`
	CreatedAt    time.Time        `json:"created_at"`
	HasHash      bool             `json:"has_hash"`
	HasSignature bool             `json:"has_signature"`
}

type SigningKey struct {
	ID             string           `json:"id"`
	UserID         string           `json:"user_id"`
	PublicKey      string           `json:"public_key"`
	Algorithm      string           `json:"algorithm"`
	KeyFingerprint string           `json:"key_fingerprint"`
	Status         SigningKeyStatus `json:"status"`
	CreatedAt      time.Time        `json:"created_at"`
	RevokedAt      *time.Time       `json:"revoked_at,omitempty"`
}

type StepConfirmationPrepare struct {
	JournalID              string           `json:"journal_id"`
	StepID                 string           `json:"step_id"`
	LegacyRecommendationID string           `json:"legacy_recommendation_id,omitempty"`
	EventType              JournalEventType `json:"event_type"`
	ActorID                string           `json:"actor_id"`
	ActorRole              JournalActorRole `json:"actor_role"`
	SigningKeyID           string           `json:"signing_key_id"`
	KeyFingerprint         string           `json:"key_fingerprint"`
	PreviousHash           *string          `json:"previous_hash"`
	EventHashToSign        string           `json:"event_hash_to_sign"`
	CompletedAt            time.Time        `json:"completed_at"`
	DeadlineAt             *time.Time       `json:"deadline_at,omitempty"`
	SignatureAlgorithm     string           `json:"signature_algorithm"`
	SignatureInput         string           `json:"signature_input"`
}

type StepConfirmationCommit struct {
	EventHashToSign string    `json:"event_hash_to_sign"`
	CompletedAt     time.Time `json:"completed_at"`
	PreviousHash    *string   `json:"previous_hash"`
	SigningKeyID    string    `json:"signing_key_id"`
	Signature       string    `json:"signature"`
}

type ClientUnavailabilityNoticeInput struct {
	UnavailableFrom  time.Time `json:"unavailable_from"`
	UnavailableUntil time.Time `json:"unavailable_until"`
	Reason           string    `json:"reason"`
	Comment          string    `json:"comment"`
}

type ClientProblemReportInput struct {
	Reason  string `json:"reason"`
	Comment string `json:"comment"`
}

type JournalEventResult struct {
	EventID   string           `json:"event_id"`
	JournalID string           `json:"journal_id"`
	EventType JournalEventType `json:"event_type"`
	CreatedAt time.Time        `json:"created_at"`
	Signed    bool             `json:"signed"`
}

type DeadlineExtensionInput struct {
	NewDeadlineAt             time.Time `json:"new_deadline_at"`
	Reason                    string    `json:"reason"`
	LinkedClientNoticeEventID *string   `json:"linked_client_notice_event_id,omitempty"`
}

type DeadlineExtensionResult struct {
	EventID                   string           `json:"event_id"`
	JournalID                 string           `json:"journal_id"`
	StepID                    string           `json:"step_id"`
	EventType                 JournalEventType `json:"event_type"`
	OldDeadlineAt             *time.Time       `json:"old_deadline_at"`
	NewDeadlineAt             time.Time        `json:"new_deadline_at"`
	LinkedClientNoticeEventID *string          `json:"linked_client_notice_event_id,omitempty"`
	CreatedAt                 time.Time        `json:"created_at"`
	Signed                    bool             `json:"signed"`
}

type JournalStopInput struct {
	Reason                    string  `json:"reason"`
	StopCategory              string  `json:"stop_category"`
	LinkedClientNoticeEventID *string `json:"linked_client_notice_event_id,omitempty"`
}

type JournalStopResult struct {
	JournalID           string        `json:"journal_id"`
	Status              JournalStatus `json:"status"`
	EventID             string        `json:"event_id"`
	StoppedAt           time.Time     `json:"stopped_at"`
	Signed              bool          `json:"signed"`
	CancelledStepsCount int64         `json:"cancelled_steps_count"`
}

type ReplacementJournalStepInput struct {
	DayNumber   int        `json:"day_number"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	DeadlineAt  *time.Time `json:"deadline_at,omitempty"`
}

type ReplacementJournalInput struct {
	Reason string                        `json:"reason"`
	Steps  []ReplacementJournalStepInput `json:"steps"`
}

type ReplacementJournalResult struct {
	ParentJournalID string    `json:"parent_journal_id"`
	NewJournalID    string    `json:"new_journal_id"`
	RootJournalID   string    `json:"root_journal_id"`
	AppointmentID   string    `json:"appointment_id"`
	VersionNumber   int       `json:"version_number"`
	StepsCreated    int       `json:"steps_created"`
	EventID         string    `json:"event_id"`
	ParentFinalHash string    `json:"parent_final_hash"`
	CreatedAt       time.Time `json:"created_at"`
	Signed          bool      `json:"signed"`
}
