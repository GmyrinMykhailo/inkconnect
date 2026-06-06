package users

import (
	"context"
	"strings"
	"unicode/utf8"
)

type ProfileService struct {
	repository Repository
}

func NewProfileService(repository Repository) *ProfileService {
	return &ProfileService{repository: repository}
}

func (s *ProfileService) GetProfile(ctx context.Context, userID string) (UserProfile, error) {
	return s.repository.FindProfileByUserID(ctx, userID)
}

func (s *ProfileService) GetPublicProfile(ctx context.Context, username string) (PublicUserProfile, error) {
	return s.repository.FindPublicProfileByUsername(ctx, strings.TrimSpace(username))
}

func (s *ProfileService) UpdateProfile(ctx context.Context, userID string, input ProfileUpdateInput) (UserProfile, error) {
	current, err := s.repository.FindProfileByUserID(ctx, userID)
	if err != nil {
		return UserProfile{}, err
	}

	lastName := current.LastName
	firstName := current.FirstName
	middleName := current.MiddleName
	studioName := current.StudioName
	city := current.City
	bio := current.Bio
	showFullName := current.ShowFullNameInProfile
	showCity := current.ShowCityInProfile

	if input.LastName != nil {
		lastName = strings.TrimSpace(*input.LastName)
	}
	if input.FirstName != nil {
		firstName = strings.TrimSpace(*input.FirstName)
	}
	if input.MiddleName != nil {
		middleName = strings.TrimSpace(*input.MiddleName)
	}
	if input.StudioName != nil && current.Role == RoleMaster {
		studioName = strings.TrimSpace(*input.StudioName)
	}
	if input.City != nil {
		city = strings.TrimSpace(*input.City)
	}
	if input.Bio != nil {
		bio = strings.TrimSpace(*input.Bio)
	}
	if input.ShowFullNameInProfile != nil {
		showFullName = *input.ShowFullNameInProfile
	}
	if input.ShowCityInProfile != nil {
		showCity = *input.ShowCityInProfile
	}

	if lastName == "" {
		return UserProfile{}, ErrLastNameRequired
	}
	if firstName == "" {
		return UserProfile{}, ErrFirstNameRequired
	}
	if city == "" {
		return UserProfile{}, ErrCityRequired
	}
	if exceedsMaxLength(lastName, 128) ||
		exceedsMaxLength(firstName, 128) ||
		exceedsMaxLength(middleName, 128) ||
		exceedsMaxLength(studioName, 128) ||
		exceedsMaxLength(city, 128) {
		return UserProfile{}, ErrFieldTooLong
	}
	if !isValidHumanName(lastName) || !isValidHumanName(firstName) || (middleName != "" && !isValidHumanName(middleName)) {
		return UserProfile{}, ErrInvalidName
	}
	if !hasConsistentNameScript(lastName, firstName, middleName) {
		return UserProfile{}, ErrNameScriptMismatch
	}
	if !isValidCityName(city) {
		return UserProfile{}, ErrInvalidCity
	}
	if utf8.RuneCountInString(bio) > 150 {
		return UserProfile{}, ErrBioTooLong
	}

	return s.repository.UpdateProfile(ctx, userID, UpdateProfileParams{
		LastName:              lastName,
		FirstName:             firstName,
		MiddleName:            middleName,
		StudioName:            studioName,
		UpdateMasterStudio:    current.Role == RoleMaster,
		City:                  city,
		Bio:                   bio,
		ShowFullNameInProfile: showFullName,
		ShowCityInProfile:     showCity,
		FullName:              joinNonEmpty(lastName, firstName, middleName),
	})
}
