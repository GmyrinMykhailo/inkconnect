package recommendations

import (
	"context"
	"errors"
	"testing"

	"inkconnect/internal/appointments"
)

func TestServiceSaveDraftNormalizesStepsAndReplacesDraft(t *testing.T) {
	service, repository, appointmentFinder, _ := newTestRecommendationService()

	response, err := service.SaveDraft(context.Background(), "master-1", " appointment-1 ", []Step{
		{Title: "  Wash gently  ", Description: "  Use clean water  "},
		{StepNumber: 5, Title: "Moisturize", Description: "Apply cream", DueOffsetDays: intPointer(2)},
	})
	if err != nil {
		t.Fatalf("SaveDraft returned error: %v", err)
	}

	if !repository.replaceDraftCalled {
		t.Fatal("ReplaceDraft should be called")
	}
	if repository.replaceDraftAppointmentID != "appointment-1" {
		t.Fatalf("replace draft appointment id = %q, want appointment-1", repository.replaceDraftAppointmentID)
	}
	if repository.replaceDraftMasterID != "master-1" {
		t.Fatalf("replace draft master id = %q, want master-1", repository.replaceDraftMasterID)
	}
	firstStep := repository.replacedSteps[0]
	if firstStep.StepNumber != 1 || firstStep.Title != "Wash gently" || firstStep.Description != "Use clean water" {
		t.Fatalf("first normalized step = %#v", firstStep)
	}
	if repository.replacedSteps[1].StepNumber != 5 {
		t.Fatalf("second normalized step number = %d, want 5", repository.replacedSteps[1].StepNumber)
	}
	if response.Appointment.ID != appointmentFinder.appointment.ID {
		t.Fatalf("response appointment id = %q, want %q", response.Appointment.ID, appointmentFinder.appointment.ID)
	}
	if response.Recommendations.Status != StatusDraft {
		t.Fatalf("response status = %q, want %q", response.Recommendations.Status, StatusDraft)
	}
}

func TestServiceSaveDraftRejectsForbiddenMaster(t *testing.T) {
	service, repository, _, _ := newTestRecommendationService()

	_, err := service.SaveDraft(context.Background(), "other-master", "appointment-1", validRecommendationSteps())
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("SaveDraft error = %v, want %v", err, ErrForbidden)
	}
	if repository.replaceDraftCalled {
		t.Fatal("ReplaceDraft should not be called")
	}
}

func TestServiceSaveDraftRejectsAppointmentNotReady(t *testing.T) {
	for _, status := range []string{appointments.StatusPending, appointments.StatusCancelled} {
		t.Run(status, func(t *testing.T) {
			service, repository, _, _ := newTestRecommendationService()
			repository.access.Status = status

			_, err := service.SaveDraft(context.Background(), "master-1", "appointment-1", validRecommendationSteps())
			if !errors.Is(err, ErrAppointmentNotReady) {
				t.Fatalf("SaveDraft error = %v, want %v", err, ErrAppointmentNotReady)
			}
			if repository.replaceDraftCalled {
				t.Fatal("ReplaceDraft should not be called")
			}
		})
	}
}

func TestServiceSaveDraftRejectsApprovedPlan(t *testing.T) {
	service, repository, _, _ := newTestRecommendationService()
	repository.plans = []Plan{approvedPlan("appointment-1", "")}

	_, err := service.SaveDraft(context.Background(), "master-1", "appointment-1", validRecommendationSteps())
	if !errors.Is(err, ErrRecommendationsDone) {
		t.Fatalf("SaveDraft error = %v, want %v", err, ErrRecommendationsDone)
	}
	if repository.replaceDraftCalled {
		t.Fatal("ReplaceDraft should not be called")
	}
}

func TestServiceSaveDraftRejectsInvalidSteps(t *testing.T) {
	tests := []struct {
		name  string
		steps []Step
	}{
		{name: "empty", steps: nil},
		{name: "empty title", steps: []Step{{Title: " ", Description: "Use clean water"}}},
		{name: "empty description", steps: []Step{{Title: "Wash", Description: " "}}},
		{name: "zero due offset", steps: []Step{{Title: "Wash", Description: "Use clean water", DueOffsetDays: intPointer(0)}}},
		{name: "too large due offset", steps: []Step{{Title: "Wash", Description: "Use clean water", DueOffsetDays: intPointer(100)}}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service, repository, _, _ := newTestRecommendationService()

			_, err := service.SaveDraft(context.Background(), "master-1", "appointment-1", tt.steps)
			if !errors.Is(err, ErrInvalidInput) {
				t.Fatalf("SaveDraft error = %v, want %v", err, ErrInvalidInput)
			}
			if repository.replaceDraftCalled {
				t.Fatal("ReplaceDraft should not be called")
			}
		})
	}
}

func TestServiceSendMarksDraftAsSent(t *testing.T) {
	service, repository, _, _ := newTestRecommendationService()
	repository.plans = []Plan{draftPlan("appointment-1", validRecommendationSteps())}

	response, err := service.Send(context.Background(), "master-1", "appointment-1")
	if err != nil {
		t.Fatalf("Send returned error: %v", err)
	}
	if !repository.markSentCalled {
		t.Fatal("MarkSent should be called")
	}
	if response.Recommendations.Status != StatusSent {
		t.Fatalf("response status = %q, want %q", response.Recommendations.Status, StatusSent)
	}
}

func TestServiceSendRejectsEmptyPlan(t *testing.T) {
	service, repository, _, _ := newTestRecommendationService()
	repository.plans = []Plan{draftPlan("appointment-1", nil)}

	_, err := service.Send(context.Background(), "master-1", "appointment-1")
	if !errors.Is(err, ErrRecommendationsNone) {
		t.Fatalf("Send error = %v, want %v", err, ErrRecommendationsNone)
	}
	if repository.markSentCalled {
		t.Fatal("MarkSent should not be called")
	}
}

func TestServiceSendReturnsApprovedPlanWithoutMarkSent(t *testing.T) {
	service, repository, _, _ := newTestRecommendationService()
	repository.plans = []Plan{approvedPlan("appointment-1", "journal-1")}

	response, err := service.Send(context.Background(), "master-1", "appointment-1")
	if err != nil {
		t.Fatalf("Send returned error: %v", err)
	}
	if repository.markSentCalled {
		t.Fatal("MarkSent should not be called")
	}
	if response.Recommendations.Status != StatusApproved {
		t.Fatalf("response status = %q, want %q", response.Recommendations.Status, StatusApproved)
	}
}

func TestServiceGetForClientRejectsForbiddenClient(t *testing.T) {
	service, _, _, _ := newTestRecommendationService()

	_, err := service.GetForClient(context.Background(), "other-client", "appointment-1")
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("GetForClient error = %v, want %v", err, ErrForbidden)
	}
}

func TestServiceGetForClientRejectsDraftOrEmptyRecommendations(t *testing.T) {
	tests := []struct {
		name      string
		plan      Plan
		wantError error
	}{
		{name: "empty", plan: draftPlan("appointment-1", nil), wantError: ErrRecommendationsNone},
		{name: "draft", plan: draftPlan("appointment-1", validRecommendationSteps()), wantError: ErrRecommendationsDraft},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service, repository, _, _ := newTestRecommendationService()
			repository.plans = []Plan{tt.plan}

			_, err := service.GetForClient(context.Background(), "client-1", "appointment-1")
			if !errors.Is(err, tt.wantError) {
				t.Fatalf("GetForClient error = %v, want %v", err, tt.wantError)
			}
		})
	}
}

func TestServiceGetForClientReturnsSentRecommendations(t *testing.T) {
	service, repository, _, _ := newTestRecommendationService()
	repository.plans = []Plan{sentPlan("appointment-1")}

	response, err := service.GetForClient(context.Background(), "client-1", "appointment-1")
	if err != nil {
		t.Fatalf("GetForClient returned error: %v", err)
	}
	if response.Recommendations.Status != StatusSent {
		t.Fatalf("response status = %q, want %q", response.Recommendations.Status, StatusSent)
	}
}

func TestServiceApproveMarksSentPlanApprovedAndCreatesJournal(t *testing.T) {
	service, repository, _, journalCreator := newTestRecommendationService()
	repository.plans = []Plan{
		sentPlan("appointment-1"),
		approvedPlan("appointment-1", "journal-1"),
	}

	response, err := service.Approve(context.Background(), "client-1", "appointment-1")
	if err != nil {
		t.Fatalf("Approve returned error: %v", err)
	}
	if !repository.markApprovedCalled {
		t.Fatal("MarkApproved should be called")
	}
	if !journalCreator.called {
		t.Fatal("EnsureForApprovedAppointment should be called")
	}
	if journalCreator.clientID != "client-1" || journalCreator.appointmentID != "appointment-1" {
		t.Fatalf("journal creator args = (%q, %q)", journalCreator.clientID, journalCreator.appointmentID)
	}
	if response.Recommendations.JournalID != "journal-1" {
		t.Fatalf("response journal id = %q, want journal-1", response.Recommendations.JournalID)
	}
	if repository.findPlanCalls != 2 {
		t.Fatalf("FindPlan calls = %d, want 2", repository.findPlanCalls)
	}
}

func TestServiceApproveApprovedPlanEnsuresJournalIdempotently(t *testing.T) {
	service, repository, _, journalCreator := newTestRecommendationService()
	repository.plans = []Plan{
		approvedPlan("appointment-1", ""),
		approvedPlan("appointment-1", "journal-1"),
	}

	response, err := service.Approve(context.Background(), "client-1", "appointment-1")
	if err != nil {
		t.Fatalf("Approve returned error: %v", err)
	}
	if repository.markApprovedCalled {
		t.Fatal("MarkApproved should not be called")
	}
	if !journalCreator.called {
		t.Fatal("EnsureForApprovedAppointment should be called")
	}
	if response.Recommendations.JournalID != "journal-1" {
		t.Fatalf("response journal id = %q, want journal-1", response.Recommendations.JournalID)
	}
}

func TestServiceApproveRejectsDraftOrEmptyRecommendations(t *testing.T) {
	tests := []struct {
		name      string
		plan      Plan
		wantError error
	}{
		{name: "empty", plan: draftPlan("appointment-1", nil), wantError: ErrRecommendationsNone},
		{name: "draft", plan: draftPlan("appointment-1", validRecommendationSteps()), wantError: ErrRecommendationsDraft},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service, repository, _, journalCreator := newTestRecommendationService()
			repository.plans = []Plan{tt.plan}

			_, err := service.Approve(context.Background(), "client-1", "appointment-1")
			if !errors.Is(err, tt.wantError) {
				t.Fatalf("Approve error = %v, want %v", err, tt.wantError)
			}
			if repository.markApprovedCalled {
				t.Fatal("MarkApproved should not be called")
			}
			if journalCreator.called {
				t.Fatal("EnsureForApprovedAppointment should not be called")
			}
		})
	}
}

func TestServiceResponseMapsMissingAppointment(t *testing.T) {
	service, repository, appointmentFinder, _ := newTestRecommendationService()
	repository.plans = []Plan{sentPlan("appointment-1")}
	appointmentFinder.err = appointments.ErrAppointmentNotFound

	_, err := service.GetForMaster(context.Background(), "master-1", "appointment-1")
	if !errors.Is(err, ErrAppointmentNotFound) {
		t.Fatalf("GetForMaster error = %v, want %v", err, ErrAppointmentNotFound)
	}
}

type fakeRecommendationRepository struct {
	access    AppointmentAccess
	accessErr error

	plans         []Plan
	findPlanErr   error
	findPlanCalls int

	replaceDraftCalled        bool
	replaceDraftAppointmentID string
	replaceDraftMasterID      string
	replacedSteps             []Step
	replaceDraftPlan          Plan
	replaceDraftErr           error

	markSentCalled        bool
	markSentAppointmentID string
	markSentPlan          Plan
	markSentErr           error

	markApprovedCalled        bool
	markApprovedAppointmentID string
	markApprovedPlan          Plan
	markApprovedErr           error
}

func (r *fakeRecommendationRepository) FindAppointmentAccess(ctx context.Context, appointmentID string) (AppointmentAccess, error) {
	if r.accessErr != nil {
		return AppointmentAccess{}, r.accessErr
	}
	return r.access, nil
}

func (r *fakeRecommendationRepository) FindPlan(ctx context.Context, appointmentID string) (Plan, error) {
	r.findPlanCalls++
	if r.findPlanErr != nil {
		return Plan{}, r.findPlanErr
	}
	if len(r.plans) == 0 {
		return draftPlan(appointmentID, nil), nil
	}
	plan := r.plans[0]
	if len(r.plans) > 1 {
		r.plans = r.plans[1:]
	}
	return plan, nil
}

func (r *fakeRecommendationRepository) ReplaceDraft(ctx context.Context, appointmentID string, masterID string, steps []Step) (Plan, error) {
	r.replaceDraftCalled = true
	r.replaceDraftAppointmentID = appointmentID
	r.replaceDraftMasterID = masterID
	r.replacedSteps = append([]Step(nil), steps...)
	if r.replaceDraftErr != nil {
		return Plan{}, r.replaceDraftErr
	}
	if r.replaceDraftPlan.AppointmentID != "" {
		return r.replaceDraftPlan, nil
	}
	return draftPlan(appointmentID, steps), nil
}

func (r *fakeRecommendationRepository) MarkSent(ctx context.Context, appointmentID string) (Plan, error) {
	r.markSentCalled = true
	r.markSentAppointmentID = appointmentID
	if r.markSentErr != nil {
		return Plan{}, r.markSentErr
	}
	if r.markSentPlan.AppointmentID != "" {
		return r.markSentPlan, nil
	}
	return sentPlan(appointmentID), nil
}

func (r *fakeRecommendationRepository) MarkApproved(ctx context.Context, appointmentID string) (Plan, error) {
	r.markApprovedCalled = true
	r.markApprovedAppointmentID = appointmentID
	if r.markApprovedErr != nil {
		return Plan{}, r.markApprovedErr
	}
	if r.markApprovedPlan.AppointmentID != "" {
		return r.markApprovedPlan, nil
	}
	return approvedPlan(appointmentID, ""), nil
}

type fakeAppointmentFinder struct {
	appointment appointments.AppointmentView
	err         error
	calls       int
}

func (f *fakeAppointmentFinder) FindAppointmentByID(ctx context.Context, appointmentID string) (appointments.AppointmentView, error) {
	f.calls++
	if f.err != nil {
		return appointments.AppointmentView{}, f.err
	}
	return f.appointment, nil
}

type fakeJournalCreator struct {
	journalID     string
	err           error
	called        bool
	clientID      string
	appointmentID string
}

func (j *fakeJournalCreator) EnsureForApprovedAppointment(ctx context.Context, clientID string, appointmentID string) (string, error) {
	j.called = true
	j.clientID = clientID
	j.appointmentID = appointmentID
	if j.err != nil {
		return "", j.err
	}
	return j.journalID, nil
}

func newTestRecommendationService() (*Service, *fakeRecommendationRepository, *fakeAppointmentFinder, *fakeJournalCreator) {
	repository := &fakeRecommendationRepository{
		access: AppointmentAccess{
			ID:       "appointment-1",
			ClientID: "client-1",
			MasterID: "master-1",
			Status:   appointments.StatusConfirmed,
		},
	}
	appointmentFinder := &fakeAppointmentFinder{
		appointment: appointments.AppointmentView{
			ID:     "appointment-1",
			Status: appointments.StatusConfirmed,
			Client: appointments.PersonSummary{ID: "client-1", Username: "client"},
			Master: appointments.PersonSummary{ID: "master-1", Username: "master", IsMaster: true},
		},
	}
	journalCreator := &fakeJournalCreator{journalID: "journal-1"}
	service := NewService(repository, appointmentFinder, journalCreator)
	return service, repository, appointmentFinder, journalCreator
}

func validRecommendationSteps() []Step {
	return []Step{{StepNumber: 1, Title: "Wash", Description: "Use clean water"}}
}

func draftPlan(appointmentID string, steps []Step) Plan {
	return Plan{AppointmentID: appointmentID, Status: StatusDraft, Steps: steps}
}

func sentPlan(appointmentID string) Plan {
	return Plan{AppointmentID: appointmentID, Status: StatusSent, Steps: validRecommendationSteps()}
}

func approvedPlan(appointmentID string, journalID string) Plan {
	return Plan{
		AppointmentID: appointmentID,
		JournalID:     journalID,
		Status:        StatusApproved,
		Steps:         validRecommendationSteps(),
	}
}

func intPointer(value int) *int {
	return &value
}
