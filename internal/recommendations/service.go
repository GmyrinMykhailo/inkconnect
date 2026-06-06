package recommendations

import (
	"context"
	"errors"
	"strings"

	"inkconnect/internal/appointments"
)

type Service struct {
	repository            Repository
	appointmentRepository AppointmentFinder
	journalCreator        JournalCreator
}

type AppointmentFinder interface {
	FindAppointmentByID(ctx context.Context, appointmentID string) (appointments.AppointmentView, error)
}

type JournalCreator interface {
	EnsureForApprovedAppointment(ctx context.Context, clientID string, appointmentID string) (string, error)
}

func NewService(repository Repository, appointmentRepository AppointmentFinder, journalCreator JournalCreator) *Service {
	return &Service{
		repository:            repository,
		appointmentRepository: appointmentRepository,
		journalCreator:        journalCreator,
	}
}

func (s *Service) GetForMaster(ctx context.Context, masterID string, appointmentID string) (Response, error) {
	access, err := s.repository.FindAppointmentAccess(ctx, strings.TrimSpace(appointmentID))
	if err != nil {
		return Response{}, err
	}
	if access.MasterID != masterID {
		return Response{}, ErrForbidden
	}
	plan, err := s.repository.FindPlan(ctx, access.ID)
	if err != nil {
		return Response{}, err
	}
	return s.response(ctx, access.ID, plan)
}

func (s *Service) SaveDraft(ctx context.Context, masterID string, appointmentID string, steps []Step) (Response, error) {
	access, err := s.repository.FindAppointmentAccess(ctx, strings.TrimSpace(appointmentID))
	if err != nil {
		return Response{}, err
	}
	if access.MasterID != masterID {
		return Response{}, ErrForbidden
	}
	if !appointmentAllowsRecommendations(access.Status) {
		return Response{}, ErrAppointmentNotReady
	}

	current, err := s.repository.FindPlan(ctx, access.ID)
	if err != nil {
		return Response{}, err
	}
	if current.Status == StatusApproved {
		return Response{}, ErrRecommendationsDone
	}

	normalized, err := normalizeSteps(steps)
	if err != nil {
		return Response{}, err
	}
	plan, err := s.repository.ReplaceDraft(ctx, access.ID, masterID, normalized)
	if err != nil {
		return Response{}, err
	}
	return s.response(ctx, access.ID, plan)
}

func (s *Service) Send(ctx context.Context, masterID string, appointmentID string) (Response, error) {
	access, err := s.repository.FindAppointmentAccess(ctx, strings.TrimSpace(appointmentID))
	if err != nil {
		return Response{}, err
	}
	if access.MasterID != masterID {
		return Response{}, ErrForbidden
	}
	if !appointmentAllowsRecommendations(access.Status) {
		return Response{}, ErrAppointmentNotReady
	}

	current, err := s.repository.FindPlan(ctx, access.ID)
	if err != nil {
		return Response{}, err
	}
	if len(current.Steps) == 0 {
		return Response{}, ErrRecommendationsNone
	}
	if current.Status == StatusApproved {
		return s.response(ctx, access.ID, current)
	}
	plan, err := s.repository.MarkSent(ctx, access.ID)
	if err != nil {
		return Response{}, err
	}
	return s.response(ctx, access.ID, plan)
}

func (s *Service) GetForClient(ctx context.Context, clientID string, appointmentID string) (Response, error) {
	access, err := s.repository.FindAppointmentAccess(ctx, strings.TrimSpace(appointmentID))
	if err != nil {
		return Response{}, err
	}
	if access.ClientID != clientID {
		return Response{}, ErrForbidden
	}
	if !appointmentAllowsRecommendations(access.Status) {
		return Response{}, ErrAppointmentNotReady
	}

	plan, err := s.repository.FindPlan(ctx, access.ID)
	if err != nil {
		return Response{}, err
	}
	if len(plan.Steps) == 0 {
		return Response{}, ErrRecommendationsNone
	}
	if plan.Status == StatusDraft {
		return Response{}, ErrRecommendationsDraft
	}
	return s.response(ctx, access.ID, plan)
}

func (s *Service) Approve(ctx context.Context, clientID string, appointmentID string) (Response, error) {
	access, err := s.repository.FindAppointmentAccess(ctx, strings.TrimSpace(appointmentID))
	if err != nil {
		return Response{}, err
	}
	if access.ClientID != clientID {
		return Response{}, ErrForbidden
	}
	if !appointmentAllowsRecommendations(access.Status) {
		return Response{}, ErrAppointmentNotReady
	}

	plan, err := s.repository.FindPlan(ctx, access.ID)
	if err != nil {
		return Response{}, err
	}
	if len(plan.Steps) == 0 {
		return Response{}, ErrRecommendationsNone
	}
	if plan.Status == StatusDraft {
		return Response{}, ErrRecommendationsDraft
	}
	if plan.Status == StatusApproved {
		if s.journalCreator != nil {
			journalID, err := s.journalCreator.EnsureForApprovedAppointment(ctx, clientID, access.ID)
			if err != nil {
				return Response{}, err
			}
			plan, err = s.repository.FindPlan(ctx, access.ID)
			if err != nil {
				return Response{}, err
			}
			plan.JournalID = journalID
		}
		return s.response(ctx, access.ID, plan)
	}
	plan, err = s.repository.MarkApproved(ctx, access.ID)
	if err != nil {
		return Response{}, err
	}
	if s.journalCreator != nil {
		journalID, err := s.journalCreator.EnsureForApprovedAppointment(ctx, clientID, access.ID)
		if err != nil {
			return Response{}, err
		}
		plan, err = s.repository.FindPlan(ctx, access.ID)
		if err != nil {
			return Response{}, err
		}
		plan.JournalID = journalID
	}
	return s.response(ctx, access.ID, plan)
}

func (s *Service) response(ctx context.Context, appointmentID string, plan Plan) (Response, error) {
	appointment, err := s.appointmentRepository.FindAppointmentByID(ctx, appointmentID)
	if err != nil {
		if errors.Is(err, appointments.ErrAppointmentNotFound) {
			return Response{}, ErrAppointmentNotFound
		}
		return Response{}, err
	}
	return Response{
		Appointment:     appointment,
		Recommendations: plan,
	}, nil
}

func appointmentAllowsRecommendations(status string) bool {
	return status == "confirmed" || status == "completed"
}

func normalizeSteps(steps []Step) ([]Step, error) {
	if len(steps) == 0 {
		return nil, ErrInvalidInput
	}

	normalized := make([]Step, 0, len(steps))
	for index, step := range steps {
		title := strings.TrimSpace(step.Title)
		description := strings.TrimSpace(step.Description)
		if title == "" || description == "" {
			return nil, ErrInvalidInput
		}

		stepNumber := step.StepNumber
		if stepNumber <= 0 {
			stepNumber = index + 1
		}
		if step.DueOffsetDays != nil {
			dueOffsetDays := *step.DueOffsetDays
			if dueOffsetDays <= 0 || dueOffsetDays > 99 {
				return nil, ErrInvalidInput
			}
		}
		normalized = append(normalized, Step{
			StepNumber:    stepNumber,
			Title:         title,
			Description:   description,
			DueOffsetDays: step.DueOffsetDays,
			DueAt:         step.DueAt,
		})
	}
	return normalized, nil
}
