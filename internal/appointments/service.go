package appointments

import (
	"context"
	"sort"
	"strings"
	"time"
)

type Service struct {
	repository Repository
}

func NewService(repository Repository) *Service {
	return &Service{repository: repository}
}

func (s *Service) Availability(ctx context.Context, masterUsername string, date time.Time, serviceID string) (AvailabilityResult, error) {
	masterID, err := s.repository.FindMasterIDByUsername(ctx, strings.TrimSpace(masterUsername))
	if err != nil {
		return AvailabilityResult{}, err
	}

	durationMinutes := 60
	if strings.TrimSpace(serviceID) != "" {
		service, err := s.repository.FindServiceForMaster(ctx, masterID, serviceID)
		if err != nil {
			return AvailabilityResult{}, err
		}
		durationMinutes = durationMinutesFromService(service)
	}

	dayIndex := mondayBasedDayIndex(date)
	intervals, enabled, err := s.repository.WorkIntervalsForDay(ctx, masterID, dayIndex)
	if err != nil {
		return AvailabilityResult{}, err
	}
	if !enabled {
		return AvailabilityResult{Date: formatDate(date), Slots: []AvailabilitySlot{}}, nil
	}

	intervals = sortedScheduleIntervals(intervals)
	busy, err := s.repository.BusyWindowsForDate(ctx, masterID, date)
	if err != nil {
		return AvailabilityResult{}, err
	}

	return AvailabilityResult{
		Date:  formatDate(date),
		Slots: availabilitySlots(intervals, busy, durationMinutes),
	}, nil
}

func (s *Service) Create(ctx context.Context, input CreateAppointmentInput) (AppointmentView, error) {
	masterID, err := s.repository.FindMasterIDByUsername(ctx, strings.TrimSpace(input.MasterUsername))
	if err != nil {
		return AppointmentView{}, err
	}
	if masterID == input.ClientID {
		return AppointmentView{}, ErrSlotUnavailable
	}

	service, err := s.repository.FindServiceForMaster(ctx, masterID, strings.TrimSpace(input.ServiceID))
	if err != nil {
		return AppointmentView{}, err
	}

	durationMinutes := durationMinutesFromService(service)
	localStart := input.ScheduledAt.In(bookingLocation())
	dayIndex := mondayBasedDayIndex(localStart)
	intervals, enabled, err := s.repository.WorkIntervalsForDay(ctx, masterID, dayIndex)
	if err != nil {
		return AppointmentView{}, err
	}
	if !enabled {
		return AppointmentView{}, ErrSlotUnavailable
	}

	intervals = sortedScheduleIntervals(intervals)
	localStartMinute := localStart.Hour()*60 + localStart.Minute()
	if localStartMinute%30 != 0 {
		return AppointmentView{}, ErrSlotUnavailable
	}

	busy, err := s.repository.BusyWindowsForDate(ctx, masterID, localStart)
	if err != nil {
		return AppointmentView{}, err
	}
	busySegments := busySegmentsForWindows(busy, intervals)
	if slotReason(localStartMinute, durationMinutes, intervals, busySegments) != AvailabilityReasonAvailable {
		return AppointmentView{}, ErrSlotUnavailable
	}

	input.DurationMinutes = durationMinutes
	appointmentID, err := s.repository.CreateAppointment(ctx, input, masterID)
	if err != nil {
		return AppointmentView{}, err
	}
	appointment, err := s.repository.FindAppointmentByID(ctx, appointmentID)
	if err != nil {
		return AppointmentView{}, err
	}
	return s.withAppointmentEnd(ctx, appointment)
}

func (s *Service) UpdateMasterDuration(ctx context.Context, masterID string, appointmentID string, durationMinutes int) (UpdateDurationResult, error) {
	if durationMinutes <= 0 {
		return UpdateDurationResult{}, ErrInvalidDuration
	}

	appointment, err := s.repository.UpdateMasterAppointmentDuration(ctx, masterID, strings.TrimSpace(appointmentID), durationMinutes)
	if err != nil {
		return UpdateDurationResult{}, err
	}

	appointment, err = s.withAppointmentEnd(ctx, appointment)
	if err != nil {
		return UpdateDurationResult{}, err
	}

	warnings, err := s.durationWarnings(ctx, appointment, durationMinutes)
	if err != nil {
		return UpdateDurationResult{}, err
	}

	return UpdateDurationResult{
		Appointment: appointment,
		Warnings:    warnings,
	}, nil
}

func (s *Service) ListClient(ctx context.Context, clientID string) ([]AppointmentView, error) {
	appointments, err := s.repository.ListClientAppointments(ctx, clientID)
	if err != nil {
		return nil, err
	}
	return s.withAppointmentEnds(ctx, appointments)
}

func (s *Service) ListMaster(ctx context.Context, masterID string) ([]AppointmentView, error) {
	appointments, err := s.repository.ListMasterAppointments(ctx, masterID)
	if err != nil {
		return nil, err
	}
	return s.withAppointmentEnds(ctx, appointments)
}

func (s *Service) UpdateMasterStatus(ctx context.Context, masterID string, appointmentID string, status string) (AppointmentView, error) {
	status = strings.TrimSpace(status)
	switch status {
	case StatusPending, StatusConfirmed, StatusRejected, StatusCompleted, StatusCancelled:
	default:
		return AppointmentView{}, ErrInvalidStatus
	}
	appointment, err := s.repository.UpdateMasterAppointmentStatus(ctx, masterID, appointmentID, status)
	if err != nil {
		return AppointmentView{}, err
	}
	return s.withAppointmentEnd(ctx, appointment)
}

func CountsFromAppointments(items []AppointmentView) AppointmentCounts {
	counts := AppointmentCounts{All: len(items)}
	for _, item := range items {
		switch item.Status {
		case StatusPending:
			counts.Pending++
		case StatusConfirmed:
			counts.Confirmed++
		case StatusCancelled:
			counts.Cancelled++
		case StatusRejected:
			counts.Rejected++
		case StatusCompleted:
			counts.Completed++
		}
	}
	return counts
}

func mondayBasedDayIndex(date time.Time) int {
	return (int(date.Weekday()) + 6) % 7
}

func bookingLocation() *time.Location {
	return time.FixedZone("MSK", 3*60*60)
}

func (s *Service) withAppointmentEnds(ctx context.Context, appointments []AppointmentView) ([]AppointmentView, error) {
	for index := range appointments {
		appointment, err := s.withAppointmentEnd(ctx, appointments[index])
		if err != nil {
			return nil, err
		}
		appointments[index] = appointment
	}
	return appointments, nil
}

func (s *Service) withAppointmentEnd(ctx context.Context, appointment AppointmentView) (AppointmentView, error) {
	end := appointment.ScheduledAt.Add(time.Duration(durationMinutesFromService(appointment.Service)) * time.Minute)

	localStart := appointment.ScheduledAt.In(bookingLocation())
	dayIndex := mondayBasedDayIndex(localStart)
	intervals, enabled, err := s.repository.WorkIntervalsForDay(ctx, appointment.Master.ID, dayIndex)
	if err != nil {
		return AppointmentView{}, err
	}
	if enabled {
		startMinute := localStart.Hour()*60 + localStart.Minute()
		if wallEndMinute, ok := bookingWallEndMinute(
			startMinute,
			durationMinutesFromService(appointment.Service),
			sortedScheduleIntervals(intervals),
		); ok {
			startOfDay := time.Date(
				localStart.Year(),
				localStart.Month(),
				localStart.Day(),
				0,
				0,
				0,
				0,
				bookingLocation(),
			)
			end = startOfDay.Add(time.Duration(wallEndMinute) * time.Minute)
		}
	}

	appointment.ScheduledEndAt = timePtr(end)
	return appointment, nil
}

func (s *Service) durationWarnings(ctx context.Context, appointment AppointmentView, durationMinutes int) ([]string, error) {
	warnings := make([]string, 0, 2)
	localStart := appointment.ScheduledAt.In(bookingLocation())
	dayIndex := mondayBasedDayIndex(localStart)
	intervals, enabled, err := s.repository.WorkIntervalsForDay(ctx, appointment.Master.ID, dayIndex)
	if err != nil {
		return nil, err
	}

	localStartMinute := localStart.Hour()*60 + localStart.Minute()
	if !enabled {
		warnings = append(warnings, DurationWarningOutsideSchedule)
	} else {
		segments, ok := bookingSegments(localStartMinute, durationMinutes, sortedScheduleIntervals(intervals))
		if !ok || len(segments) == 0 {
			warnings = append(warnings, DurationWarningOutsideSchedule)
		}
	}

	end := appointment.ScheduledAt.Add(time.Duration(durationMinutes) * time.Minute)
	if appointment.ScheduledEndAt != nil {
		end = *appointment.ScheduledEndAt
	}
	overlaps, err := s.repository.HasOverlapExcluding(ctx, appointment.Master.ID, appointment.ScheduledAt, end, appointment.ID)
	if err != nil {
		return nil, err
	}
	if overlaps {
		warnings = append(warnings, DurationWarningOverlap)
	}

	return warnings, nil
}

func timePtr(value time.Time) *time.Time {
	return &value
}

func durationMinutesFromService(service ServiceSummary) int {
	if service.DurationHours == nil || *service.DurationHours <= 0 {
		return 60
	}
	minutes := int(*service.DurationHours*60 + 0.5)
	if minutes < 30 {
		return 30
	}
	return minutes
}

func availabilitySlots(intervals []scheduleInterval, busy []busyWindow, durationMinutes int) []AvailabilitySlot {
	first, last, ok := workdayBounds(intervals)
	if !ok {
		return []AvailabilitySlot{}
	}

	busySegments := busySegmentsForWindows(busy, intervals)
	slots := make([]AvailabilitySlot, 0, ((last-first)/30)+1)
	for minute := first; minute <= last; minute += 30 {
		reason := slotReason(minute, durationMinutes, intervals, busySegments)
		slots = append(slots, AvailabilitySlot{
			Time:      minuteLabel(minute),
			Available: reason == AvailabilityReasonAvailable,
			Reason:    reason,
		})
	}
	return slots
}

func slotReason(startMinute int, durationMinutes int, intervals []scheduleInterval, busySegments []timeSegment) string {
	if isBreakMinute(startMinute, intervals) {
		return AvailabilityReasonBreak
	}
	if !isWorkMinute(startMinute, intervals) {
		return AvailabilityReasonOutsideSchedule
	}

	segments, ok := bookingSegments(startMinute, durationMinutes, intervals)
	if !ok {
		return AvailabilityReasonTooShort
	}
	if segmentsOverlap(segments, busySegments) {
		return AvailabilityReasonBusy
	}
	return AvailabilityReasonAvailable
}

func bookingSegments(startMinute int, durationMinutes int, intervals []scheduleInterval) ([]timeSegment, bool) {
	remaining := durationMinutes
	current := startMinute
	var segments []timeSegment

	for guard := 0; remaining > 0 && guard < 100; guard++ {
		interval, ok := intervalAt(current, intervals)
		if !ok {
			return nil, false
		}
		switch interval.Type {
		case "break":
			current = interval.EndMinute
		case "work":
			available := interval.EndMinute - current
			if available <= 0 {
				return nil, false
			}
			take := available
			if take > remaining {
				take = remaining
			}
			segments = append(segments, timeSegment{
				StartMinute: current,
				EndMinute:   current + take,
			})
			current += take
			remaining -= take
		default:
			return nil, false
		}
	}

	return segments, remaining == 0
}

func bookingWallEndMinute(startMinute int, durationMinutes int, intervals []scheduleInterval) (int, bool) {
	segments, ok := bookingSegments(startMinute, durationMinutes, intervals)
	if !ok || len(segments) == 0 {
		return 0, false
	}
	return segments[len(segments)-1].EndMinute, true
}

func intervalAt(minute int, intervals []scheduleInterval) (scheduleInterval, bool) {
	for _, interval := range intervals {
		if minute >= interval.StartMinute && minute < interval.EndMinute {
			return interval, true
		}
	}
	return scheduleInterval{}, false
}

func isWorkMinute(minute int, intervals []scheduleInterval) bool {
	interval, ok := intervalAt(minute, intervals)
	return ok && interval.Type == "work"
}

func isBreakMinute(minute int, intervals []scheduleInterval) bool {
	interval, ok := intervalAt(minute, intervals)
	return ok && interval.Type == "break"
}

func busySegmentsForWindows(busy []busyWindow, intervals []scheduleInterval) []timeSegment {
	var segments []timeSegment
	for _, window := range busy {
		nextSegments, ok := bookingSegments(window.StartMinute, window.DurationMinutes, intervals)
		if ok {
			segments = append(segments, nextSegments...)
			continue
		}
		segments = append(segments, timeSegment{
			StartMinute: window.StartMinute,
			EndMinute:   window.StartMinute + window.DurationMinutes,
		})
	}
	return segments
}

func segmentsOverlap(left []timeSegment, right []timeSegment) bool {
	for _, a := range left {
		for _, b := range right {
			if a.StartMinute < b.EndMinute && a.EndMinute > b.StartMinute {
				return true
			}
		}
	}
	return false
}

func workdayBounds(intervals []scheduleInterval) (int, int, bool) {
	first := 0
	last := 0
	found := false
	for _, interval := range intervals {
		if interval.Type != "work" || interval.EndMinute <= interval.StartMinute {
			continue
		}
		if !found || interval.StartMinute < first {
			first = interval.StartMinute
		}
		if !found || interval.EndMinute > last {
			last = interval.EndMinute
		}
		found = true
	}
	return first, last, found
}

func sortedScheduleIntervals(intervals []scheduleInterval) []scheduleInterval {
	items := append([]scheduleInterval(nil), intervals...)
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].StartMinute == items[j].StartMinute {
			return items[i].EndMinute < items[j].EndMinute
		}
		return items[i].StartMinute < items[j].StartMinute
	})
	return items
}

type timeSegment struct {
	StartMinute int
	EndMinute   int
}

func minuteLabel(total int) string {
	hour := total / 60
	minute := total % 60
	return twoDigits(hour) + ":" + twoDigits(minute)
}

func twoDigits(value int) string {
	if value < 10 {
		return "0" + string(rune('0'+value))
	}
	return string(rune('0'+value/10)) + string(rune('0'+value%10))
}

func formatDate(date time.Time) string {
	return date.Format("2006-01-02")
}
