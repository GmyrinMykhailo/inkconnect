package publications

import (
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"unicode/utf8"

	mediastore "inkconnect/internal/media"
	"inkconnect/internal/platform/storage"
)

type ObjectStorage interface {
	Bucket() string
	PutObject(ctx context.Context, objectKey string, body io.Reader, size int64, contentType string) error
	RemoveObject(ctx context.Context, objectKey string) error
}

type Service struct {
	repository Repository
	storage    ObjectStorage
}

func NewService(repository Repository, storage ObjectStorage) *Service {
	return &Service{
		repository: repository,
		storage:    storage,
	}
}

func (s *Service) Create(ctx context.Context, masterID string, input CreatePublicationInput) (Publication, error) {
	masterID = strings.TrimSpace(masterID)
	if masterID == "" {
		return Publication{}, ErrPublicationMasterOnly
	}

	isMaster, err := s.repository.IsMaster(ctx, masterID)
	if err != nil {
		return Publication{}, err
	}
	if !isMaster {
		return Publication{}, ErrPublicationMasterOnly
	}

	normalized, err := normalizeCreateInput(input)
	if err != nil {
		return Publication{}, err
	}

	return s.repository.Create(ctx, masterID, normalized)
}

func (s *Service) CreateWithPhotos(ctx context.Context, masterID string, input CreatePublicationWithPhotosInput) (Publication, error) {
	masterID = strings.TrimSpace(masterID)
	if masterID == "" {
		return Publication{}, ErrPublicationMasterOnly
	}
	if s.storage == nil || strings.TrimSpace(s.storage.Bucket()) == "" {
		return Publication{}, ErrPublicationStorageUnavailable
	}

	isMaster, err := s.repository.IsMaster(ctx, masterID)
	if err != nil {
		return Publication{}, err
	}
	if !isMaster {
		return Publication{}, ErrPublicationMasterOnly
	}

	normalized, err := normalizeCreateWithPhotosInput(input)
	if err != nil {
		return Publication{}, err
	}

	publicationID, err := newUUID()
	if err != nil {
		return Publication{}, err
	}

	createInput := CreatePublicationInput{
		Description:      normalized.Description,
		CommentsDisabled: normalized.CommentsDisabled,
		Styles:           normalized.Styles,
		Media:            make([]PublicationMediaInput, 0, len(normalized.Photos)),
	}
	objects := make([]mediastore.Object, 0, len(normalized.Photos))

	for index, photo := range normalized.Photos {
		prepared, err := preparePublicationPhoto(photo)
		if err != nil {
			cleanupUploadedObjects(ctx, s.storage, objects)
			return Publication{}, err
		}

		mediaID, err := newUUID()
		if err != nil {
			cleanupUploadedObjects(ctx, s.storage, objects)
			return Publication{}, err
		}

		object := mediastore.Object{
			ID:          mediaID,
			OwnerUserID: masterID,
			Bucket:      s.storage.Bucket(),
			ObjectKey:   publicationObjectKey(masterID, publicationID, mediaID, prepared.Extension),
			Kind:        mediastore.KindMasterPublicationPhoto,
			ContentType: prepared.ContentType,
			SizeBytes:   photo.SizeBytes,
		}

		if err := s.storage.PutObject(ctx, object.ObjectKey, prepared.Reader, object.SizeBytes, object.ContentType); err != nil {
			cleanupUploadedObjects(ctx, s.storage, objects)
			if errors.Is(err, storage.ErrUnavailable) {
				return Publication{}, ErrPublicationStorageUnavailable
			}
			return Publication{}, err
		}

		objects = append(objects, object)
		createInput.Media = append(createInput.Media, PublicationMediaInput{
			MediaID:   mediaID,
			SortOrder: index,
			IsCover:   index == 0,
		})
	}

	publication, err := s.repository.CreateWithMediaObjects(ctx, masterID, publicationID, createInput, objects)
	if err != nil {
		cleanupUploadedObjects(ctx, s.storage, objects)
		return Publication{}, err
	}

	return publication, nil
}

func (s *Service) ListByMasterUsername(ctx context.Context, username string) ([]Publication, error) {
	username = strings.TrimSpace(username)
	if username == "" {
		return nil, ErrPublicationNotFound
	}

	return s.repository.ListByMasterUsername(ctx, username)
}

func (s *Service) Get(ctx context.Context, publicationID string) (Publication, error) {
	publicationID = strings.TrimSpace(publicationID)
	if publicationID == "" {
		return Publication{}, ErrPublicationNotFound
	}

	return s.repository.FindByID(ctx, publicationID)
}

func (s *Service) Delete(ctx context.Context, masterID string, publicationID string) error {
	masterID = strings.TrimSpace(masterID)
	publicationID = strings.TrimSpace(publicationID)
	if masterID == "" {
		return ErrPublicationMasterOnly
	}
	if publicationID == "" {
		return ErrPublicationNotFound
	}

	isMaster, err := s.repository.IsMaster(ctx, masterID)
	if err != nil {
		return err
	}
	if !isMaster {
		return ErrPublicationMasterOnly
	}

	publication, err := s.repository.FindByID(ctx, publicationID)
	if err != nil {
		return err
	}
	if publication.MasterID != masterID {
		return ErrPublicationForbidden
	}

	return s.repository.SoftDelete(ctx, masterID, publicationID)
}

func normalizeCreateInput(input CreatePublicationInput) (CreatePublicationInput, error) {
	input.Description = strings.TrimSpace(input.Description)
	if utf8.RuneCountInString(input.Description) > MaxPublicationDescription {
		return CreatePublicationInput{}, ErrPublicationInvalidInput
	}

	if len(input.Media) == 0 {
		return CreatePublicationInput{}, ErrPublicationPhotoRequired
	}
	if len(input.Media) > MaxPublicationPhotos {
		return CreatePublicationInput{}, ErrPublicationTooManyPhotos
	}

	seenMedia := map[string]bool{}
	mediaInputs := make([]PublicationMediaInput, 0, len(input.Media))
	for index, item := range input.Media {
		mediaID := strings.TrimSpace(item.MediaID)
		if mediaID == "" || seenMedia[mediaID] {
			return CreatePublicationInput{}, ErrPublicationInvalidInput
		}
		seenMedia[mediaID] = true
		mediaInputs = append(mediaInputs, PublicationMediaInput{
			MediaID:   mediaID,
			SortOrder: index,
			IsCover:   index == 0,
		})
	}
	input.Media = mediaInputs

	seenStyles := map[string]bool{}
	styles := []string{}
	for _, style := range input.Styles {
		trimmed := strings.TrimSpace(style)
		if trimmed == "" || seenStyles[trimmed] {
			continue
		}
		if utf8.RuneCountInString(trimmed) > MaxPublicationStyleLength {
			return CreatePublicationInput{}, ErrPublicationInvalidInput
		}
		seenStyles[trimmed] = true
		styles = append(styles, trimmed)
	}
	input.Styles = styles

	return input, nil
}

func normalizeCreateWithPhotosInput(input CreatePublicationWithPhotosInput) (CreatePublicationWithPhotosInput, error) {
	normalized, err := normalizeCreateInput(CreatePublicationInput{
		Description:      input.Description,
		CommentsDisabled: input.CommentsDisabled,
		Styles:           input.Styles,
		Media:            publicationMediaPlaceholders(len(input.Photos)),
	})
	if err != nil {
		return CreatePublicationWithPhotosInput{}, err
	}

	photos := make([]PublicationPhotoUpload, 0, len(input.Photos))
	for _, photo := range input.Photos {
		if photo.Reader == nil || photo.SizeBytes <= 0 {
			return CreatePublicationWithPhotosInput{}, ErrPublicationFileRequired
		}
		if photo.SizeBytes > MaxPublicationPhotoBytes {
			return CreatePublicationWithPhotosInput{}, ErrPublicationFileTooLarge
		}
		photos = append(photos, photo)
	}

	return CreatePublicationWithPhotosInput{
		Description:      normalized.Description,
		CommentsDisabled: normalized.CommentsDisabled,
		Styles:           normalized.Styles,
		Photos:           photos,
	}, nil
}

func publicationMediaPlaceholders(count int) []PublicationMediaInput {
	media := make([]PublicationMediaInput, 0, count)
	for index := 0; index < count; index++ {
		media = append(media, PublicationMediaInput{
			MediaID: fmt.Sprintf("photo-%d", index),
		})
	}
	return media
}

type preparedPublicationPhoto struct {
	Reader      io.Reader
	ContentType string
	Extension   string
}

func preparePublicationPhoto(upload PublicationPhotoUpload) (preparedPublicationPhoto, error) {
	header := make([]byte, 512)
	n, err := io.ReadFull(upload.Reader, header)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		return preparedPublicationPhoto{}, err
	}
	header = header[:n]

	contentType, extension, ok := detectPublicationImage(header)
	if !ok {
		return preparedPublicationPhoto{}, ErrPublicationUnsupportedContent
	}

	return preparedPublicationPhoto{
		Reader:      io.MultiReader(bytes.NewReader(header), upload.Reader),
		ContentType: contentType,
		Extension:   extension,
	}, nil
}

func detectPublicationImage(header []byte) (string, string, bool) {
	if len(header) >= 12 && string(header[0:4]) == "RIFF" && string(header[8:12]) == "WEBP" {
		return "image/webp", "webp", true
	}

	switch http.DetectContentType(header) {
	case "image/jpeg":
		return "image/jpeg", "jpg", true
	case "image/png":
		return "image/png", "png", true
	default:
		return "", "", false
	}
}

func publicationObjectKey(masterID string, publicationID string, mediaID string, extension string) string {
	return fmt.Sprintf(
		"masters/%s/publications/%s/%s.%s",
		strings.TrimSpace(masterID),
		strings.TrimSpace(publicationID),
		strings.TrimSpace(mediaID),
		strings.TrimPrefix(strings.TrimSpace(extension), "."),
	)
}

func cleanupUploadedObjects(ctx context.Context, storage ObjectStorage, objects []mediastore.Object) {
	if storage == nil {
		return
	}
	for _, object := range objects {
		_ = storage.RemoveObject(ctx, object.ObjectKey)
	}
}

func newUUID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("generate uuid: %w", err)
	}

	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80

	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}
