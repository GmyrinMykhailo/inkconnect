package media

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"strings"

	"inkconnect/internal/platform/storage"
)

type ObjectStorage interface {
	Bucket() string
	PutObject(ctx context.Context, objectKey string, body io.Reader, size int64, contentType string) error
	GetObject(ctx context.Context, objectKey string) (storage.Object, error)
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

func (s *Service) UploadUserAvatar(ctx context.Context, userID string, upload AvatarUpload) (Object, error) {
	if err := validateAvatarUpload(upload); err != nil {
		return Object{}, err
	}
	if s.storage == nil {
		return Object{}, ErrStorageUnavailable
	}

	mediaID, err := newUUID()
	if err != nil {
		return Object{}, err
	}

	object := Object{
		ID:          mediaID,
		OwnerUserID: strings.TrimSpace(userID),
		Bucket:      s.storage.Bucket(),
		ObjectKey:   avatarObjectKey(userID, mediaID, upload.Extension),
		Kind:        KindUserAvatar,
		ContentType: upload.ContentType,
		SizeBytes:   upload.SizeBytes,
	}

	if err := s.storage.PutObject(ctx, object.ObjectKey, upload.Reader, upload.SizeBytes, upload.ContentType); err != nil {
		if errors.Is(err, storage.ErrUnavailable) {
			return Object{}, ErrStorageUnavailable
		}
		return Object{}, err
	}

	saved, oldObject, err := s.repository.ReplaceUserAvatar(ctx, object)
	if err != nil {
		_ = s.storage.RemoveObject(ctx, object.ObjectKey)
		return Object{}, err
	}

	if oldObject != nil {
		_ = s.storage.RemoveObject(ctx, oldObject.ObjectKey)
	}

	return saved, nil
}

func (s *Service) DeleteUserAvatar(ctx context.Context, userID string) error {
	oldObject, err := s.repository.ClearUserAvatar(ctx, userID)
	if err != nil {
		return err
	}
	if oldObject == nil || s.storage == nil {
		return nil
	}

	_ = s.storage.RemoveObject(ctx, oldObject.ObjectKey)
	return nil
}

func (s *Service) OpenPublicObject(ctx context.Context, mediaID string) (ServedObject, error) {
	if s.storage == nil {
		return ServedObject{}, ErrStorageUnavailable
	}

	object, err := s.repository.FindActiveObjectByID(ctx, strings.TrimSpace(mediaID))
	if err != nil {
		return ServedObject{}, err
	}
	if !isPublicMediaKind(object.Kind) || object.Bucket != s.storage.Bucket() {
		return ServedObject{}, ErrMediaNotFound
	}

	storedObject, err := s.storage.GetObject(ctx, object.ObjectKey)
	if err != nil {
		if errors.Is(err, storage.ErrUnavailable) {
			return ServedObject{}, ErrStorageUnavailable
		}
		return ServedObject{}, err
	}

	return ServedObject{
		Media: object,
		Body:  storedObject.Body,
		Size:  storedObject.Size,
	}, nil
}

func isPublicMediaKind(kind string) bool {
	switch kind {
	case KindUserAvatar, KindMasterPublicationPhoto:
		return true
	default:
		return false
	}
}

func validateAvatarUpload(upload AvatarUpload) error {
	if upload.Reader == nil || upload.SizeBytes <= 0 {
		return ErrFileRequired
	}
	if upload.SizeBytes > MaxAvatarBytes {
		return ErrFileTooLarge
	}
	if !allowedAvatarContentType(upload.ContentType) {
		return ErrUnsupportedContentType
	}
	if strings.TrimSpace(upload.Extension) == "" {
		return ErrUnsupportedContentType
	}

	return nil
}

func allowedAvatarContentType(contentType string) bool {
	switch strings.TrimSpace(strings.ToLower(contentType)) {
	case "image/jpeg", "image/png", "image/webp":
		return true
	default:
		return false
	}
}

func avatarObjectKey(userID string, mediaID string, extension string) string {
	return fmt.Sprintf("users/%s/avatar/%s.%s", strings.TrimSpace(userID), mediaID, strings.TrimPrefix(extension, "."))
}

func newUUID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("generate media id: %w", err)
	}

	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80

	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}
