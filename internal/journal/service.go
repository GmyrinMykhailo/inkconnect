package journal

import (
	"context"
	"errors"
	"strings"

	"inkconnect/internal/appointments"
)

type Service struct {
	repository   Repository
	appointments appointments.Repository
}

func NewService(repository Repository, appointmentsRepository appointments.Repository) *Service {
	return &Service{
		repository:   repository,
		appointments: appointmentsRepository,
	}
}

func (s *Service) EnsureForApprovedAppointment(ctx context.Context, clientID string, appointmentID string) (string, error) {
	return s.repository.EnsureForApprovedAppointment(ctx, strings.TrimSpace(appointmentID), clientID)
}

func (s *Service) CreateForAppointment(ctx context.Context, clientID string, appointmentID string) (Detail, error) {
	journalID, err := s.EnsureForApprovedAppointment(ctx, clientID, appointmentID)
	if err != nil {
		return Detail{}, err
	}
	return s.Detail(ctx, clientID, journalID)
}

func (s *Service) ListClient(ctx context.Context, clientID string) ([]Summary, error) {
	journals, err := s.repository.ListClientJournals(ctx, clientID)
	if err != nil {
		return nil, err
	}
	return s.summaries(ctx, journals)
}

func (s *Service) ListMaster(ctx context.Context, masterID string) ([]Summary, error) {
	journals, err := s.repository.ListMasterJournals(ctx, masterID)
	if err != nil {
		return nil, err
	}
	return s.summaries(ctx, journals)
}

func (s *Service) ListForAppointment(ctx context.Context, userID string, appointmentID string) ([]AppointmentJournalSummary, error) {
	appointment, err := s.appointments.FindAppointmentByID(ctx, strings.TrimSpace(appointmentID))
	if err != nil {
		if errors.Is(err, appointments.ErrAppointmentNotFound) {
			return nil, ErrAppointmentNotFound
		}
		return nil, err
	}
	if appointment.Client.ID != userID && appointment.Master.ID != userID {
		return nil, ErrForbidden
	}
	items, err := s.repository.ListAppointmentJournals(ctx, appointment.ID)
	if err != nil {
		return nil, err
	}
	for index := range items {
		report, err := s.repository.VerifyIntegrity(ctx, items[index].ID)
		if err != nil {
			return nil, err
		}
		items[index].IntegrityCheckStatus = report.Status
		items[index].IntegrityValid = report.Valid
		items[index].IntegrityEventsCount = report.EventsCount
	}
	return items, nil
}

func (s *Service) Detail(ctx context.Context, userID string, journalID string) (Detail, error) {
	journal, err := s.repository.FindJournal(ctx, strings.TrimSpace(journalID))
	if err != nil {
		return Detail{}, err
	}
	if journal.ClientID != userID && journal.MasterID != userID {
		return Detail{}, ErrForbidden
	}

	appointment, err := s.appointments.FindAppointmentByID(ctx, journal.AppointmentID)
	if err != nil {
		if errors.Is(err, appointments.ErrAppointmentNotFound) {
			return Detail{}, ErrAppointmentNotFound
		}
		return Detail{}, err
	}

	steps, err := s.repository.ListSteps(ctx, journal.ID)
	if err != nil {
		return Detail{}, err
	}
	return Detail{
		Journal:     journal,
		Appointment: appointment,
		Steps:       steps,
		Progress:    progressFromSteps(steps),
	}, nil
}

func (s *Service) Integrity(ctx context.Context, userID string, journalID string) (IntegrityReport, error) {
	journal, err := s.repository.FindJournal(ctx, strings.TrimSpace(journalID))
	if err != nil {
		return IntegrityReport{}, err
	}
	if journal.ClientID != userID && journal.MasterID != userID {
		return IntegrityReport{}, ErrForbidden
	}
	return s.repository.VerifyIntegrity(ctx, journal.ID)
}

func (s *Service) Events(ctx context.Context, userID string, journalID string) ([]JournalEventView, error) {
	journal, err := s.repository.FindJournal(ctx, strings.TrimSpace(journalID))
	if err != nil {
		return nil, err
	}
	if journal.ClientID != userID && journal.MasterID != userID {
		return nil, ErrForbidden
	}
	return s.repository.ListEvents(ctx, journal.ID)
}

func (s *Service) ConfirmStep(ctx context.Context, clientID string, journalID string, stepID string) (Detail, error) {
	if err := s.repository.ConfirmStep(ctx, strings.TrimSpace(journalID), strings.TrimSpace(stepID), clientID); err != nil {
		return Detail{}, err
	}
	return s.Detail(ctx, clientID, journalID)
}

func (s *Service) PrepareStepConfirmation(ctx context.Context, clientID string, journalID string, stepID string) (StepConfirmationPrepare, error) {
	return s.repository.PrepareStepConfirmation(ctx, strings.TrimSpace(journalID), strings.TrimSpace(stepID), clientID)
}

func (s *Service) CommitStepConfirmation(ctx context.Context, clientID string, journalID string, stepID string, request StepConfirmationCommit) (Detail, error) {
	if err := s.repository.CommitStepConfirmation(ctx, strings.TrimSpace(journalID), strings.TrimSpace(stepID), clientID, request); err != nil {
		return Detail{}, err
	}
	return s.Detail(ctx, clientID, journalID)
}

func (s *Service) CreateClientUnavailabilityNotice(ctx context.Context, clientID string, journalID string, input ClientUnavailabilityNoticeInput) (JournalEventResult, error) {
	return s.repository.CreateClientUnavailabilityNotice(ctx, strings.TrimSpace(journalID), clientID, input)
}

func (s *Service) CreateClientProblemReport(ctx context.Context, clientID string, journalID string, input ClientProblemReportInput) (JournalEventResult, error) {
	return s.repository.CreateClientProblemReport(ctx, strings.TrimSpace(journalID), clientID, input)
}

func (s *Service) CreateDeadlineExtension(ctx context.Context, masterID string, journalID string, stepID string, input DeadlineExtensionInput) (DeadlineExtensionResult, error) {
	return s.repository.CreateDeadlineExtension(ctx, strings.TrimSpace(journalID), strings.TrimSpace(stepID), masterID, input)
}

func (s *Service) StopJournal(ctx context.Context, masterID string, journalID string, input JournalStopInput) (JournalStopResult, error) {
	return s.repository.StopJournal(ctx, strings.TrimSpace(journalID), masterID, input)
}

func (s *Service) CreateReplacementJournal(ctx context.Context, masterID string, journalID string, input ReplacementJournalInput) (ReplacementJournalResult, error) {
	return s.repository.CreateReplacementJournal(ctx, strings.TrimSpace(journalID), masterID, input)
}

func (s *Service) summaries(ctx context.Context, journals []Journal) ([]Summary, error) {
	items := make([]Summary, 0, len(journals))
	for _, journal := range journals {
		appointment, err := s.appointments.FindAppointmentByID(ctx, journal.AppointmentID)
		if err != nil {
			if errors.Is(err, appointments.ErrAppointmentNotFound) {
				return nil, ErrAppointmentNotFound
			}
			return nil, err
		}
		steps, err := s.repository.ListSteps(ctx, journal.ID)
		if err != nil {
			return nil, err
		}
		items = append(items, Summary{
			Journal:     journal,
			Appointment: appointment,
			Progress:    progressFromSteps(steps),
		})
	}
	return items, nil
}

func progressFromSteps(steps []Step) Progress {
	total := len(steps)
	done := 0
	for _, step := range steps {
		if step.ConfirmedAt != nil {
			done++
		}
	}
	percent := 0
	if total > 0 {
		percent = int(float64(done)/float64(total)*100 + 0.5)
	}
	return Progress{
		StepsDone:  done,
		StepsTotal: total,
		Percent:    percent,
	}
}
