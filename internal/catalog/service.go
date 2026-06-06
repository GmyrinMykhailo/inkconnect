package catalog

import (
	"context"
	"sort"
	"strings"
	"unicode/utf8"
)

type MasterServicesService struct {
	repository ServiceRepository
}

func NewMasterServicesService(repository ServiceRepository) *MasterServicesService {
	return &MasterServicesService{repository: repository}
}

func (s *MasterServicesService) GetSettings(ctx context.Context, masterID string) (MasterSettings, error) {
	return s.repository.GetMasterSettings(ctx, masterID)
}

func (s *MasterServicesService) UpdateSettings(ctx context.Context, masterID string, input MasterSettingsInput) (MasterSettings, error) {
	normalized, err := normalizeMasterSettingsInput(input)
	if err != nil {
		return MasterSettings{}, err
	}

	return s.repository.UpdateMasterSettings(ctx, masterID, normalized)
}

func (s *MasterServicesService) List(ctx context.Context, masterID string) ([]MasterService, error) {
	services, err := s.repository.ListMasterServices(ctx, masterID)
	if err != nil {
		return nil, err
	}
	if len(services) > 0 {
		return services, nil
	}

	hasAny, err := s.repository.HasAnyMasterServices(ctx, masterID)
	if err != nil {
		return nil, err
	}
	if hasAny {
		return services, nil
	}

	service, err := s.repository.CreateMasterService(ctx, masterID, DefaultMinimalTattooService())
	if err != nil {
		return nil, err
	}

	return []MasterService{service}, nil
}

func (s *MasterServicesService) Create(ctx context.Context, masterID string, input ServiceInput) (MasterService, error) {
	normalized, err := normalizeServiceInput(input)
	if err != nil {
		return MasterService{}, err
	}

	return s.repository.CreateMasterService(ctx, masterID, normalized)
}

func (s *MasterServicesService) Update(ctx context.Context, masterID string, serviceID string, input ServiceInput) (MasterService, error) {
	normalized, err := normalizeServiceInput(input)
	if err != nil {
		return MasterService{}, err
	}

	return s.repository.UpdateMasterService(ctx, masterID, serviceID, normalized)
}

func (s *MasterServicesService) Delete(ctx context.Context, masterID string, serviceID string) error {
	return s.repository.DeleteMasterService(ctx, masterID, strings.TrimSpace(serviceID))
}

func (s *MasterServicesService) GetSchedule(ctx context.Context, masterID string) (MasterWorkSchedule, error) {
	return s.repository.GetMasterSchedule(ctx, masterID)
}

func (s *MasterServicesService) UpdateSchedule(ctx context.Context, masterID string, schedule MasterWorkSchedule) (MasterWorkSchedule, error) {
	normalized, err := normalizeMasterWorkSchedule(schedule)
	if err != nil {
		return MasterWorkSchedule{}, err
	}

	return s.repository.ReplaceMasterSchedule(ctx, masterID, normalized)
}

func normalizeServiceInput(input ServiceInput) (ServiceInput, error) {
	input.Name = strings.TrimSpace(input.Name)
	input.Description = strings.TrimSpace(input.Description)

	if input.Name == "" {
		return ServiceInput{}, ErrServiceTitleRequired
	}
	if utf8.RuneCountInString(input.Name) > 120 || utf8.RuneCountInString(input.Description) > 500 {
		return ServiceInput{}, ErrServiceFieldTooLong
	}
	if input.Price < 0 || input.Price > 9999999 {
		return ServiceInput{}, ErrServiceInvalidPrice
	}

	switch input.Type {
	case ServiceTypeSession:
		if input.DurationHours == nil || *input.DurationHours <= 0 {
			return ServiceInput{}, ErrServiceInvalidTime
		}
	case ServiceTypeConsultation:
		input.UseAutoPrice = false
		input.FromPrice = false
		if input.DurationHours == nil || *input.DurationHours <= 0 {
			return ServiceInput{}, ErrServiceInvalidTime
		}
	case ServiceTypeSketch:
		input.UseAutoPrice = false
		input.DurationHours = nil
	default:
		return ServiceInput{}, ErrServiceInvalidType
	}

	return input, nil
}

func normalizeMasterSettingsInput(input MasterSettingsInput) (MasterSettingsInput, error) {
	input.Category = strings.TrimSpace(input.Category)
	input.BreakBetweenClients = strings.TrimSpace(input.BreakBetweenClients)
	if input.Category == "" {
		input.Category = DefaultMasterSettings().Category
	}
	if input.BreakBetweenClients == "" {
		input.BreakBetweenClients = DefaultMasterSettings().BreakBetweenClients
	}
	if input.MinSessionPrice < 0 || input.MinSessionPrice > 9999999 {
		return MasterSettingsInput{}, ErrServiceInvalidPrice
	}
	if input.HourlyRate < 0 || input.HourlyRate > 9999999 {
		return MasterSettingsInput{}, ErrServiceInvalidPrice
	}

	seen := map[string]bool{}
	styles := []string{}
	for _, style := range input.Styles {
		trimmed := strings.TrimSpace(style)
		if trimmed == "" {
			continue
		}
		if utf8.RuneCountInString(trimmed) > 80 {
			return MasterSettingsInput{}, ErrServiceFieldTooLong
		}
		if seen[trimmed] {
			continue
		}
		seen[trimmed] = true
		styles = append(styles, trimmed)
	}
	input.Styles = styles

	return input, nil
}

func DefaultMasterSettings() MasterSettings {
	return MasterSettings{
		Category:            "Тату-мастер",
		Styles:              []string{},
		MinSessionPrice:     5000,
		HourlyRate:          2500,
		BreakBetweenClients: "30 минут",
	}
}

func DefaultMinimalTattooService() ServiceInput {
	duration := 1.0
	return ServiceInput{
		Name:          "Минимальная тату",
		Description:   "Небольшие татуировки до 5 см",
		Type:          ServiceTypeSession,
		DurationHours: &duration,
		Price:         5000,
		UseAutoPrice:  true,
		FromPrice:     false,
	}
}

func DefaultMasterWorkSchedule() MasterWorkSchedule {
	workdayIntervals := []WorkScheduleInterval{
		{Type: ScheduleIntervalTypeWork, StartMinute: 9 * 60, EndMinute: 13 * 60},
		{Type: ScheduleIntervalTypeBreak, StartMinute: 13 * 60, EndMinute: 14 * 60},
		{Type: ScheduleIntervalTypeWork, StartMinute: 14 * 60, EndMinute: 16 * 60},
		{Type: ScheduleIntervalTypeWork, StartMinute: 18 * 60, EndMinute: 20 * 60},
	}
	return MasterWorkSchedule{
		Days: []WorkScheduleDay{
			{DayIndex: 0, Enabled: true, Intervals: workdayIntervals},
			{DayIndex: 1, Enabled: true, Intervals: workdayIntervals},
			{DayIndex: 2, Enabled: true, Intervals: workdayIntervals},
			{DayIndex: 3, Enabled: true, Intervals: workdayIntervals},
			{DayIndex: 4, Enabled: true, Intervals: workdayIntervals},
			{DayIndex: 5, Enabled: true, Intervals: workdayIntervals},
			{DayIndex: 6, Enabled: false, Intervals: []WorkScheduleInterval{}},
		},
	}
}

func normalizeMasterWorkSchedule(schedule MasterWorkSchedule) (MasterWorkSchedule, error) {
	byDay := make(map[int]WorkScheduleDay, 7)
	for _, day := range schedule.Days {
		if day.DayIndex < 0 || day.DayIndex > 6 {
			return MasterWorkSchedule{}, ErrScheduleInvalidDay
		}

		normalized := WorkScheduleDay{
			DayIndex:  day.DayIndex,
			Enabled:   day.Enabled,
			Intervals: []WorkScheduleInterval{},
		}
		if day.Enabled {
			for _, interval := range day.Intervals {
				switch interval.Type {
				case ScheduleIntervalTypeWork, ScheduleIntervalTypeBreak:
				default:
					return MasterWorkSchedule{}, ErrScheduleInvalidType
				}
				if interval.StartMinute < 0 ||
					interval.EndMinute > 24*60 ||
					interval.EndMinute <= interval.StartMinute {
					return MasterWorkSchedule{}, ErrScheduleInvalidTime
				}
				normalized.Intervals = append(normalized.Intervals, interval)
			}

			sort.Slice(normalized.Intervals, func(i, j int) bool {
				return normalized.Intervals[i].StartMinute < normalized.Intervals[j].StartMinute
			})
			for index := 1; index < len(normalized.Intervals); index++ {
				if normalized.Intervals[index].StartMinute < normalized.Intervals[index-1].EndMinute {
					return MasterWorkSchedule{}, ErrScheduleOverlap
				}
			}
		}

		byDay[day.DayIndex] = normalized
	}

	days := make([]WorkScheduleDay, 0, 7)
	for dayIndex := 0; dayIndex < 7; dayIndex++ {
		day, ok := byDay[dayIndex]
		if !ok {
			day = WorkScheduleDay{
				DayIndex:  dayIndex,
				Enabled:   false,
				Intervals: []WorkScheduleInterval{},
			}
		}
		days = append(days, day)
	}

	return MasterWorkSchedule{Days: days}, nil
}
