package appointments

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"
)

func TestServiceCreateCreatesAppointmentWhenSlotAvailable(t *testing.T) {
	repository := newFakeAppointmentRepository()
	service := NewService(repository)
	start := testMSKTime(10, 0)
	repository.appointmentByID = testAppointmentView("appointment-1", start, repository.service)

	appointment, err := service.Create(context.Background(), CreateAppointmentInput{
		ClientID:       "client-1",
		MasterUsername: " master ",
		ServiceID:      " service-1 ",
		ScheduledAt:    start,
		ClientNote:     "first visit",
	})
	if err != nil {
		t.Fatalf("Create returned error: %v", err)
	}

	if !repository.createCalled {
		t.Fatal("expected CreateAppointment to be called")
	}
	if repository.createdMasterID != "master-1" {
		t.Fatalf("created master id = %q, want %q", repository.createdMasterID, "master-1")
	}
	if repository.createdInput.DurationMinutes != 90 {
		t.Fatalf("created duration = %d, want 90", repository.createdInput.DurationMinutes)
	}
	assertScheduledEnd(t, appointment, testMSKTime(11, 30))
}

func TestServiceCreateRejectsClientBookingSelf(t *testing.T) {
	repository := newFakeAppointmentRepository()
	repository.masterID = "client-1"
	service := NewService(repository)

	_, err := service.Create(context.Background(), CreateAppointmentInput{
		ClientID:       "client-1",
		MasterUsername: "master",
		ServiceID:      "service-1",
		ScheduledAt:    testMSKTime(10, 0),
	})
	if !errors.Is(err, ErrSlotUnavailable) {
		t.Fatalf("Create error = %v, want %v", err, ErrSlotUnavailable)
	}
	if repository.createCalled {
		t.Fatal("CreateAppointment should not be called")
	}
}

func TestServiceCreateRejectsDisabledWorkday(t *testing.T) {
	repository := newFakeAppointmentRepository()
	repository.workEnabled = false
	service := NewService(repository)

	_, err := service.Create(context.Background(), CreateAppointmentInput{
		ClientID:       "client-1",
		MasterUsername: "master",
		ServiceID:      "service-1",
		ScheduledAt:    testMSKTime(10, 0),
	})
	if !errors.Is(err, ErrSlotUnavailable) {
		t.Fatalf("Create error = %v, want %v", err, ErrSlotUnavailable)
	}
	if repository.createCalled {
		t.Fatal("CreateAppointment should not be called")
	}
}

func TestServiceCreateRejectsNonHalfHourStart(t *testing.T) {
	repository := newFakeAppointmentRepository()
	service := NewService(repository)

	_, err := service.Create(context.Background(), CreateAppointmentInput{
		ClientID:       "client-1",
		MasterUsername: "master",
		ServiceID:      "service-1",
		ScheduledAt:    testMSKTime(10, 15),
	})
	if !errors.Is(err, ErrSlotUnavailable) {
		t.Fatalf("Create error = %v, want %v", err, ErrSlotUnavailable)
	}
	if repository.createCalled {
		t.Fatal("CreateAppointment should not be called")
	}
}

func TestServiceCreateRejectsBusySlot(t *testing.T) {
	repository := newFakeAppointmentRepository()
	repository.busyWindows = []busyWindow{{StartMinute: 10 * 60, DurationMinutes: 60}}
	service := NewService(repository)

	_, err := service.Create(context.Background(), CreateAppointmentInput{
		ClientID:       "client-1",
		MasterUsername: "master",
		ServiceID:      "service-1",
		ScheduledAt:    testMSKTime(10, 0),
	})
	if !errors.Is(err, ErrSlotUnavailable) {
		t.Fatalf("Create error = %v, want %v", err, ErrSlotUnavailable)
	}
	if repository.createCalled {
		t.Fatal("CreateAppointment should not be called")
	}
}

func TestServiceAvailabilityUsesServiceDurationAndBusyWindows(t *testing.T) {
	repository := newFakeAppointmentRepository()
	repository.busyWindows = []busyWindow{{StartMinute: 10 * 60, DurationMinutes: 60}}
	service := NewService(repository)

	result, err := service.Availability(context.Background(), "master", testMSKTime(0, 0), "service-1")
	if err != nil {
		t.Fatalf("Availability returned error: %v", err)
	}

	reasons := availabilityReasonsByTime(result.Slots)
	expected := map[string]string{
		"10:00": AvailabilityReasonBusy,
		"13:00": AvailabilityReasonBreak,
		"14:00": AvailabilityReasonAvailable,
		"17:00": AvailabilityReasonTooShort,
		"18:00": AvailabilityReasonOutsideSchedule,
	}
	for slotTime, reason := range expected {
		if reasons[slotTime] != reason {
			t.Fatalf("slot %s reason = %q, want %q", slotTime, reasons[slotTime], reason)
		}
	}
}

func TestServiceAvailabilityReturnsEmptySlotsForDisabledDay(t *testing.T) {
	repository := newFakeAppointmentRepository()
	repository.workEnabled = false
	service := NewService(repository)

	result, err := service.Availability(context.Background(), "master", testMSKTime(0, 0), "")
	if err != nil {
		t.Fatalf("Availability returned error: %v", err)
	}
	if len(result.Slots) != 0 {
		t.Fatalf("slots length = %d, want 0", len(result.Slots))
	}
}

func TestServiceListClientAddsScheduledEndAt(t *testing.T) {
	repository := newFakeAppointmentRepository()
	start := testMSKTime(10, 0)
	repository.clientAppointments = []AppointmentView{
		testAppointmentView("appointment-1", start, repository.service),
	}
	service := NewService(repository)

	appointments, err := service.ListClient(context.Background(), "client-1")
	if err != nil {
		t.Fatalf("ListClient returned error: %v", err)
	}
	if len(appointments) != 1 {
		t.Fatalf("appointments length = %d, want 1", len(appointments))
	}
	assertScheduledEnd(t, appointments[0], testMSKTime(11, 30))
}

func TestServiceListMasterAddsScheduledEndAt(t *testing.T) {
	repository := newFakeAppointmentRepository()
	start := testMSKTime(14, 0)
	repository.masterAppointments = []AppointmentView{
		testAppointmentView("appointment-1", start, repository.service),
	}
	service := NewService(repository)

	appointments, err := service.ListMaster(context.Background(), "master-1")
	if err != nil {
		t.Fatalf("ListMaster returned error: %v", err)
	}
	if len(appointments) != 1 {
		t.Fatalf("appointments length = %d, want 1", len(appointments))
	}
	assertScheduledEnd(t, appointments[0], testMSKTime(15, 30))
}

func TestServiceUpdateMasterStatusRejectsInvalidStatus(t *testing.T) {
	repository := newFakeAppointmentRepository()
	service := NewService(repository)

	_, err := service.UpdateMasterStatus(context.Background(), "master-1", "appointment-1", "declined")
	if !errors.Is(err, ErrInvalidStatus) {
		t.Fatalf("UpdateMasterStatus error = %v, want %v", err, ErrInvalidStatus)
	}
	if repository.updateStatusCalled {
		t.Fatal("UpdateMasterAppointmentStatus should not be called")
	}
}

func TestServiceUpdateMasterStatusAllowsKnownStatuses(t *testing.T) {
	statuses := []string{StatusConfirmed, StatusRejected, StatusCompleted, StatusCancelled}

	for _, status := range statuses {
		t.Run(status, func(t *testing.T) {
			repository := newFakeAppointmentRepository()
			start := testMSKTime(10, 0)
			repository.updateStatusAppointment = testAppointmentView("appointment-1", start, repository.service)
			service := NewService(repository)

			appointment, err := service.UpdateMasterStatus(context.Background(), "master-1", "appointment-1", " "+status+" ")
			if err != nil {
				t.Fatalf("UpdateMasterStatus returned error: %v", err)
			}
			if !repository.updateStatusCalled {
				t.Fatal("UpdateMasterAppointmentStatus should be called")
			}
			if repository.updatedStatus != status {
				t.Fatalf("updated status = %q, want %q", repository.updatedStatus, status)
			}
			assertScheduledEnd(t, appointment, testMSKTime(11, 30))
		})
	}
}

func TestServiceUpdateMasterDurationRejectsInvalidDuration(t *testing.T) {
	repository := newFakeAppointmentRepository()
	service := NewService(repository)

	_, err := service.UpdateMasterDuration(context.Background(), "master-1", "appointment-1", 0)
	if !errors.Is(err, ErrInvalidDuration) {
		t.Fatalf("UpdateMasterDuration error = %v, want %v", err, ErrInvalidDuration)
	}
	if repository.updateDurationCalled {
		t.Fatal("UpdateMasterAppointmentDuration should not be called")
	}
}

func TestServiceUpdateMasterDurationReturnsWarnings(t *testing.T) {
	repository := newFakeAppointmentRepository()
	repository.hasOverlap = true
	repository.updateDurationAppointment = testAppointmentView(
		"appointment-1",
		testMSKTime(17, 0),
		serviceWithDuration("service-1", 2),
	)
	service := NewService(repository)

	result, err := service.UpdateMasterDuration(context.Background(), "master-1", "appointment-1", 120)
	if err != nil {
		t.Fatalf("UpdateMasterDuration returned error: %v", err)
	}
	if repository.updatedDuration != 120 {
		t.Fatalf("updated duration = %d, want 120", repository.updatedDuration)
	}
	expectedWarnings := []string{DurationWarningOutsideSchedule, DurationWarningOverlap}
	if !reflect.DeepEqual(result.Warnings, expectedWarnings) {
		t.Fatalf("warnings = %#v, want %#v", result.Warnings, expectedWarnings)
	}
}

func TestCountsFromAppointments(t *testing.T) {
	counts := CountsFromAppointments([]AppointmentView{
		{Status: StatusPending},
		{Status: StatusConfirmed},
		{Status: StatusRejected},
		{Status: StatusCompleted},
		{Status: StatusCancelled},
		{Status: StatusConfirmed},
	})

	expected := AppointmentCounts{
		All:       6,
		Pending:   1,
		Confirmed: 2,
		Rejected:  1,
		Completed: 1,
		Cancelled: 1,
	}
	if counts != expected {
		t.Fatalf("counts = %#v, want %#v", counts, expected)
	}
}

type fakeAppointmentRepository struct {
	masterID string
	service  ServiceSummary

	workIntervals []scheduleInterval
	workEnabled   bool
	busyWindows   []busyWindow
	hasOverlap    bool

	createAppointmentID string
	createCalled        bool
	createdInput        CreateAppointmentInput
	createdMasterID     string
	appointmentByID     AppointmentView

	clientAppointments []AppointmentView
	masterAppointments []AppointmentView

	updateStatusCalled      bool
	updatedStatus           string
	updateStatusAppointment AppointmentView

	updateDurationCalled      bool
	updatedDuration           int
	updateDurationAppointment AppointmentView
}

func newFakeAppointmentRepository() *fakeAppointmentRepository {
	service := serviceWithDuration("service-1", 1.5)
	return &fakeAppointmentRepository{
		masterID:            "master-1",
		service:             service,
		workIntervals:       defaultTestWorkIntervals(),
		workEnabled:         true,
		createAppointmentID: "appointment-1",
		appointmentByID:     testAppointmentView("appointment-1", testMSKTime(10, 0), service),
	}
}

func (r *fakeAppointmentRepository) FindMasterIDByUsername(ctx context.Context, username string) (string, error) {
	return r.masterID, nil
}

func (r *fakeAppointmentRepository) FindServiceForMaster(ctx context.Context, masterID string, serviceID string) (ServiceSummary, error) {
	return r.service, nil
}

func (r *fakeAppointmentRepository) CreateAppointment(ctx context.Context, input CreateAppointmentInput, masterID string) (string, error) {
	r.createCalled = true
	r.createdInput = input
	r.createdMasterID = masterID
	return r.createAppointmentID, nil
}

func (r *fakeAppointmentRepository) FindAppointmentByID(ctx context.Context, appointmentID string) (AppointmentView, error) {
	return r.appointmentByID, nil
}

func (r *fakeAppointmentRepository) ListClientAppointments(ctx context.Context, clientID string) ([]AppointmentView, error) {
	return r.clientAppointments, nil
}

func (r *fakeAppointmentRepository) ListMasterAppointments(ctx context.Context, masterID string) ([]AppointmentView, error) {
	return r.masterAppointments, nil
}

func (r *fakeAppointmentRepository) UpdateMasterAppointmentStatus(ctx context.Context, masterID string, appointmentID string, status string) (AppointmentView, error) {
	r.updateStatusCalled = true
	r.updatedStatus = status
	return r.updateStatusAppointment, nil
}

func (r *fakeAppointmentRepository) UpdateMasterAppointmentDuration(ctx context.Context, masterID string, appointmentID string, durationMinutes int) (AppointmentView, error) {
	r.updateDurationCalled = true
	r.updatedDuration = durationMinutes
	return r.updateDurationAppointment, nil
}

func (r *fakeAppointmentRepository) WorkIntervalsForDay(ctx context.Context, masterID string, dayIndex int) ([]scheduleInterval, bool, error) {
	return r.workIntervals, r.workEnabled, nil
}

func (r *fakeAppointmentRepository) BusyWindowsForDate(ctx context.Context, masterID string, date time.Time) ([]busyWindow, error) {
	return r.busyWindows, nil
}

func (r *fakeAppointmentRepository) HasOverlapExcluding(ctx context.Context, masterID string, start time.Time, end time.Time, appointmentID string) (bool, error) {
	return r.hasOverlap, nil
}

func serviceWithDuration(id string, durationHours float64) ServiceSummary {
	return ServiceSummary{
		ID:            id,
		Name:          "Tattoo session",
		DurationHours: &durationHours,
		Price:         5000,
	}
}

func testAppointmentView(id string, scheduledAt time.Time, service ServiceSummary) AppointmentView {
	return AppointmentView{
		ID:          id,
		Status:      StatusPending,
		ScheduledAt: scheduledAt,
		CreatedAt:   scheduledAt.Add(-time.Hour),
		Client:      PersonSummary{ID: "client-1", Username: "client"},
		Master:      PersonSummary{ID: "master-1", Username: "master", IsMaster: true},
		Service:     service,
	}
}

func defaultTestWorkIntervals() []scheduleInterval {
	return []scheduleInterval{
		{Type: "work", StartMinute: 9 * 60, EndMinute: 13 * 60},
		{Type: "break", StartMinute: 13 * 60, EndMinute: 14 * 60},
		{Type: "work", StartMinute: 14 * 60, EndMinute: 18 * 60},
	}
}

func testMSKTime(hour int, minute int) time.Time {
	return time.Date(2026, 6, 1, hour, minute, 0, 0, bookingLocation())
}

func availabilityReasonsByTime(slots []AvailabilitySlot) map[string]string {
	reasons := make(map[string]string, len(slots))
	for _, slot := range slots {
		reasons[slot.Time] = slot.Reason
	}
	return reasons
}

func assertScheduledEnd(t *testing.T, appointment AppointmentView, expected time.Time) {
	t.Helper()
	if appointment.ScheduledEndAt == nil {
		t.Fatal("ScheduledEndAt is nil")
	}
	if !appointment.ScheduledEndAt.Equal(expected) {
		t.Fatalf("ScheduledEndAt = %s, want %s", appointment.ScheduledEndAt, expected)
	}
}
