package media

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	storagepkg "inkconnect/internal/platform/storage"
)

func TestUploadUserAvatarStoresObjectAndReplacesMetadata(t *testing.T) {
	tests := []struct {
		name        string
		contentType string
		extension   string
	}{
		{name: "jpeg", contentType: "image/jpeg", extension: ".jpg"},
		{name: "png", contentType: "image/png", extension: "png"},
		{name: "webp", contentType: "image/webp", extension: "webp"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := &fakeMediaRepository{}
			storage := newFakeObjectStorage()
			service := NewService(repository, storage)

			saved, err := service.UploadUserAvatar(context.Background(), " user-1 ", AvatarUpload{
				Reader:      strings.NewReader("avatar-bytes"),
				SizeBytes:   int64(len("avatar-bytes")),
				ContentType: tt.contentType,
				Extension:   tt.extension,
			})
			if err != nil {
				t.Fatalf("UploadUserAvatar returned error: %v", err)
			}

			if !storage.putCalled {
				t.Fatal("PutObject should be called")
			}
			if !repository.replaceCalled {
				t.Fatal("ReplaceUserAvatar should be called")
			}
			if repository.replacedObject.ID == "" {
				t.Fatal("media id should be generated")
			}
			if repository.replacedObject.OwnerUserID != "user-1" {
				t.Fatalf("owner user id = %q, want user-1", repository.replacedObject.OwnerUserID)
			}
			if repository.replacedObject.Bucket != "inkconnect-files" {
				t.Fatalf("bucket = %q, want inkconnect-files", repository.replacedObject.Bucket)
			}
			if repository.replacedObject.Kind != KindUserAvatar {
				t.Fatalf("kind = %q, want %q", repository.replacedObject.Kind, KindUserAvatar)
			}
			if repository.replacedObject.ContentType != tt.contentType {
				t.Fatalf("content type = %q, want %q", repository.replacedObject.ContentType, tt.contentType)
			}
			if repository.replacedObject.SizeBytes != int64(len("avatar-bytes")) {
				t.Fatalf("size bytes = %d, want %d", repository.replacedObject.SizeBytes, len("avatar-bytes"))
			}
			if !strings.HasPrefix(repository.replacedObject.ObjectKey, "users/user-1/avatar/") {
				t.Fatalf("object key = %q, want users/user-1/avatar/... prefix", repository.replacedObject.ObjectKey)
			}
			if !strings.HasSuffix(repository.replacedObject.ObjectKey, "."+strings.TrimPrefix(tt.extension, ".")) {
				t.Fatalf("object key = %q, want extension %q", repository.replacedObject.ObjectKey, tt.extension)
			}
			if storage.putObjectKey != repository.replacedObject.ObjectKey {
				t.Fatalf("put object key = %q, want %q", storage.putObjectKey, repository.replacedObject.ObjectKey)
			}
			if storage.putContentType != tt.contentType {
				t.Fatalf("put content type = %q, want %q", storage.putContentType, tt.contentType)
			}
			if storage.putSize != int64(len("avatar-bytes")) {
				t.Fatalf("put size = %d, want %d", storage.putSize, len("avatar-bytes"))
			}
			if string(storage.putBody) != "avatar-bytes" {
				t.Fatalf("put body = %q, want avatar-bytes", storage.putBody)
			}
			if saved.ID != repository.replacedObject.ID {
				t.Fatalf("saved id = %q, want %q", saved.ID, repository.replacedObject.ID)
			}
		})
	}
}

func TestUploadUserAvatarRemovesNewObjectWhenRepositoryFails(t *testing.T) {
	repositoryErr := errors.New("replace avatar failed")
	repository := &fakeMediaRepository{replaceErr: repositoryErr}
	storage := newFakeObjectStorage()
	service := NewService(repository, storage)

	_, err := service.UploadUserAvatar(context.Background(), "user-1", validAvatarUpload())
	if !errors.Is(err, repositoryErr) {
		t.Fatalf("UploadUserAvatar error = %v, want %v", err, repositoryErr)
	}
	if len(storage.removedObjectKeys) != 1 {
		t.Fatalf("removed object count = %d, want 1", len(storage.removedObjectKeys))
	}
	if storage.removedObjectKeys[0] != storage.putObjectKey {
		t.Fatalf("removed key = %q, want uploaded key %q", storage.removedObjectKeys[0], storage.putObjectKey)
	}
}

func TestUploadUserAvatarRemovesOldAvatarAfterSuccessfulReplace(t *testing.T) {
	oldObject := Object{ObjectKey: "users/user-1/avatar/old.jpg"}
	repository := &fakeMediaRepository{oldObject: &oldObject}
	storage := newFakeObjectStorage()
	service := NewService(repository, storage)

	_, err := service.UploadUserAvatar(context.Background(), "user-1", validAvatarUpload())
	if err != nil {
		t.Fatalf("UploadUserAvatar returned error: %v", err)
	}
	if len(storage.removedObjectKeys) != 1 {
		t.Fatalf("removed object count = %d, want 1", len(storage.removedObjectKeys))
	}
	if storage.removedObjectKeys[0] != oldObject.ObjectKey {
		t.Fatalf("removed key = %q, want %q", storage.removedObjectKeys[0], oldObject.ObjectKey)
	}
}

func TestUploadUserAvatarMapsStorageUnavailable(t *testing.T) {
	repository := &fakeMediaRepository{}
	storage := newFakeObjectStorage()
	storage.putErr = storagepkg.ErrUnavailable
	service := NewService(repository, storage)

	_, err := service.UploadUserAvatar(context.Background(), "user-1", validAvatarUpload())
	if !errors.Is(err, ErrStorageUnavailable) {
		t.Fatalf("UploadUserAvatar error = %v, want %v", err, ErrStorageUnavailable)
	}
	if repository.replaceCalled {
		t.Fatal("ReplaceUserAvatar should not be called")
	}
}

func TestUploadUserAvatarRejectsInvalidInput(t *testing.T) {
	tests := []struct {
		name      string
		upload    AvatarUpload
		wantError error
	}{
		{name: "nil reader", upload: AvatarUpload{SizeBytes: 1, ContentType: "image/jpeg", Extension: "jpg"}, wantError: ErrFileRequired},
		{name: "zero size", upload: AvatarUpload{Reader: strings.NewReader("x"), SizeBytes: 0, ContentType: "image/jpeg", Extension: "jpg"}, wantError: ErrFileRequired},
		{name: "too large", upload: AvatarUpload{Reader: strings.NewReader("x"), SizeBytes: MaxAvatarBytes + 1, ContentType: "image/jpeg", Extension: "jpg"}, wantError: ErrFileTooLarge},
		{name: "unsupported content type", upload: AvatarUpload{Reader: strings.NewReader("x"), SizeBytes: 1, ContentType: "image/gif", Extension: "gif"}, wantError: ErrUnsupportedContentType},
		{name: "empty extension", upload: AvatarUpload{Reader: strings.NewReader("x"), SizeBytes: 1, ContentType: "image/jpeg"}, wantError: ErrUnsupportedContentType},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := &fakeMediaRepository{}
			storage := newFakeObjectStorage()
			service := NewService(repository, storage)

			_, err := service.UploadUserAvatar(context.Background(), "user-1", tt.upload)
			if !errors.Is(err, tt.wantError) {
				t.Fatalf("UploadUserAvatar error = %v, want %v", err, tt.wantError)
			}
			if storage.putCalled {
				t.Fatal("PutObject should not be called")
			}
			if repository.replaceCalled {
				t.Fatal("ReplaceUserAvatar should not be called")
			}
		})
	}
}

func TestUploadUserAvatarRequiresStorage(t *testing.T) {
	repository := &fakeMediaRepository{}
	service := NewService(repository, nil)

	_, err := service.UploadUserAvatar(context.Background(), "user-1", validAvatarUpload())
	if !errors.Is(err, ErrStorageUnavailable) {
		t.Fatalf("UploadUserAvatar error = %v, want %v", err, ErrStorageUnavailable)
	}
	if repository.replaceCalled {
		t.Fatal("ReplaceUserAvatar should not be called")
	}
}

func TestDeleteUserAvatarClearsMetadataAndRemovesObject(t *testing.T) {
	oldObject := Object{ObjectKey: "users/user-1/avatar/old.jpg"}
	repository := &fakeMediaRepository{clearObject: &oldObject}
	storage := newFakeObjectStorage()
	service := NewService(repository, storage)

	if err := service.DeleteUserAvatar(context.Background(), "user-1"); err != nil {
		t.Fatalf("DeleteUserAvatar returned error: %v", err)
	}
	if !repository.clearCalled {
		t.Fatal("ClearUserAvatar should be called")
	}
	if repository.clearUserID != "user-1" {
		t.Fatalf("clear user id = %q, want user-1", repository.clearUserID)
	}
	if len(storage.removedObjectKeys) != 1 || storage.removedObjectKeys[0] != oldObject.ObjectKey {
		t.Fatalf("removed keys = %#v, want [%q]", storage.removedObjectKeys, oldObject.ObjectKey)
	}
}

func TestDeleteUserAvatarDoesNothingWhenNoOldAvatarOrStorageMissing(t *testing.T) {
	t.Run("no old avatar", func(t *testing.T) {
		repository := &fakeMediaRepository{}
		storage := newFakeObjectStorage()
		service := NewService(repository, storage)

		if err := service.DeleteUserAvatar(context.Background(), "user-1"); err != nil {
			t.Fatalf("DeleteUserAvatar returned error: %v", err)
		}
		if len(storage.removedObjectKeys) != 0 {
			t.Fatalf("removed keys = %#v, want empty", storage.removedObjectKeys)
		}
	})

	t.Run("storage missing", func(t *testing.T) {
		oldObject := Object{ObjectKey: "users/user-1/avatar/old.jpg"}
		repository := &fakeMediaRepository{clearObject: &oldObject}
		service := NewService(repository, nil)

		if err := service.DeleteUserAvatar(context.Background(), "user-1"); err != nil {
			t.Fatalf("DeleteUserAvatar returned error: %v", err)
		}
		if !repository.clearCalled {
			t.Fatal("ClearUserAvatar should be called")
		}
	})
}

func TestDeleteUserAvatarReturnsRepositoryError(t *testing.T) {
	repositoryErr := errors.New("clear avatar failed")
	repository := &fakeMediaRepository{clearErr: repositoryErr}
	storage := newFakeObjectStorage()
	service := NewService(repository, storage)

	err := service.DeleteUserAvatar(context.Background(), "user-1")
	if !errors.Is(err, repositoryErr) {
		t.Fatalf("DeleteUserAvatar error = %v, want %v", err, repositoryErr)
	}
	if len(storage.removedObjectKeys) != 0 {
		t.Fatalf("removed keys = %#v, want empty", storage.removedObjectKeys)
	}
}

func TestOpenPublicObjectReturnsStoredObject(t *testing.T) {
	tests := []struct {
		name string
		kind string
	}{
		{name: "avatar", kind: KindUserAvatar},
		{name: "publication photo", kind: KindMasterPublicationPhoto},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := &fakeMediaRepository{
				activeObject: Object{
					ID:          "media-1",
					Bucket:      "inkconnect-files",
					ObjectKey:   "objects/media-1.jpg",
					Kind:        tt.kind,
					ContentType: "image/jpeg",
					SizeBytes:   99,
				},
			}
			storage := newFakeObjectStorage()
			storage.getBody = "stored-image"
			storage.getSize = 12
			service := NewService(repository, storage)

			served, err := service.OpenPublicObject(context.Background(), " media-1 ")
			if err != nil {
				t.Fatalf("OpenPublicObject returned error: %v", err)
			}
			defer served.Body.Close()

			if !repository.findCalled {
				t.Fatal("FindActiveObjectByID should be called")
			}
			if repository.findMediaID != "media-1" {
				t.Fatalf("find media id = %q, want media-1", repository.findMediaID)
			}
			if !storage.getCalled {
				t.Fatal("GetObject should be called")
			}
			if storage.getObjectKey != repository.activeObject.ObjectKey {
				t.Fatalf("get object key = %q, want %q", storage.getObjectKey, repository.activeObject.ObjectKey)
			}
			if served.Media.ID != "media-1" {
				t.Fatalf("served media id = %q, want media-1", served.Media.ID)
			}
			if served.Size != 12 {
				t.Fatalf("served size = %d, want 12", served.Size)
			}
			body, err := io.ReadAll(served.Body)
			if err != nil {
				t.Fatalf("read served body: %v", err)
			}
			if string(body) != "stored-image" {
				t.Fatalf("served body = %q, want stored-image", body)
			}
		})
	}
}

func TestOpenPublicObjectRejectsPrivateOrWrongBucketMedia(t *testing.T) {
	tests := []struct {
		name   string
		object Object
	}{
		{
			name: "private kind",
			object: Object{
				ID:        "media-1",
				Bucket:    "inkconnect-files",
				ObjectKey: "objects/media-1.jpg",
				Kind:      KindMasterPortfolio,
			},
		},
		{
			name: "wrong bucket",
			object: Object{
				ID:        "media-1",
				Bucket:    "other-bucket",
				ObjectKey: "objects/media-1.jpg",
				Kind:      KindUserAvatar,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := &fakeMediaRepository{activeObject: tt.object}
			storage := newFakeObjectStorage()
			service := NewService(repository, storage)

			_, err := service.OpenPublicObject(context.Background(), "media-1")
			if !errors.Is(err, ErrMediaNotFound) {
				t.Fatalf("OpenPublicObject error = %v, want %v", err, ErrMediaNotFound)
			}
			if storage.getCalled {
				t.Fatal("GetObject should not be called")
			}
		})
	}
}

func TestOpenPublicObjectMapsStorageUnavailable(t *testing.T) {
	repository := &fakeMediaRepository{
		activeObject: Object{
			ID:        "media-1",
			Bucket:    "inkconnect-files",
			ObjectKey: "objects/media-1.jpg",
			Kind:      KindUserAvatar,
		},
	}
	storage := newFakeObjectStorage()
	storage.getErr = storagepkg.ErrUnavailable
	service := NewService(repository, storage)

	_, err := service.OpenPublicObject(context.Background(), "media-1")
	if !errors.Is(err, ErrStorageUnavailable) {
		t.Fatalf("OpenPublicObject error = %v, want %v", err, ErrStorageUnavailable)
	}
}

func TestOpenPublicObjectRequiresStorage(t *testing.T) {
	repository := &fakeMediaRepository{}
	service := NewService(repository, nil)

	_, err := service.OpenPublicObject(context.Background(), "media-1")
	if !errors.Is(err, ErrStorageUnavailable) {
		t.Fatalf("OpenPublicObject error = %v, want %v", err, ErrStorageUnavailable)
	}
	if repository.findCalled {
		t.Fatal("FindActiveObjectByID should not be called")
	}
}

func TestIsPublicMediaKind(t *testing.T) {
	tests := []struct {
		kind string
		want bool
	}{
		{kind: KindUserAvatar, want: true},
		{kind: KindMasterPublicationPhoto, want: true},
		{kind: KindMasterPortfolio, want: false},
		{kind: "", want: false},
	}

	for _, tt := range tests {
		if got := isPublicMediaKind(tt.kind); got != tt.want {
			t.Fatalf("isPublicMediaKind(%q) = %v, want %v", tt.kind, got, tt.want)
		}
	}
}

func TestAvatarObjectKeyTrimsUserAndExtension(t *testing.T) {
	key := avatarObjectKey(" user-1 ", "media-1", ".jpg")
	want := "users/user-1/avatar/media-1.jpg"
	if key != want {
		t.Fatalf("avatarObjectKey = %q, want %q", key, want)
	}
}

type fakeMediaRepository struct {
	replaceCalled  bool
	replacedObject Object
	oldObject      *Object
	replaceErr     error

	clearCalled bool
	clearUserID string
	clearObject *Object
	clearErr    error

	findCalled   bool
	findMediaID  string
	activeObject Object
	findErr      error
}

func (r *fakeMediaRepository) ReplaceUserAvatar(ctx context.Context, object Object) (Object, *Object, error) {
	r.replaceCalled = true
	r.replacedObject = object
	if r.replaceErr != nil {
		return Object{}, nil, r.replaceErr
	}
	return object, r.oldObject, nil
}

func (r *fakeMediaRepository) ClearUserAvatar(ctx context.Context, userID string) (*Object, error) {
	r.clearCalled = true
	r.clearUserID = userID
	if r.clearErr != nil {
		return nil, r.clearErr
	}
	return r.clearObject, nil
}

func (r *fakeMediaRepository) FindActiveObjectByID(ctx context.Context, mediaID string) (Object, error) {
	r.findCalled = true
	r.findMediaID = mediaID
	if r.findErr != nil {
		return Object{}, r.findErr
	}
	return r.activeObject, nil
}

type fakeObjectStorage struct {
	bucket string

	putCalled      bool
	putObjectKey   string
	putSize        int64
	putContentType string
	putBody        []byte
	putErr         error

	getCalled    bool
	getObjectKey string
	getBody      string
	getSize      int64
	getErr       error

	removedObjectKeys []string
	removeErr         error
}

func newFakeObjectStorage() *fakeObjectStorage {
	return &fakeObjectStorage{
		bucket:  "inkconnect-files",
		getBody: "stored-object",
		getSize: int64(len("stored-object")),
	}
}

func (s *fakeObjectStorage) Bucket() string {
	return s.bucket
}

func (s *fakeObjectStorage) PutObject(ctx context.Context, objectKey string, body io.Reader, size int64, contentType string) error {
	s.putCalled = true
	s.putObjectKey = objectKey
	s.putSize = size
	s.putContentType = contentType
	if body != nil {
		s.putBody, _ = io.ReadAll(body)
	}
	if s.putErr != nil {
		return s.putErr
	}
	return nil
}

func (s *fakeObjectStorage) GetObject(ctx context.Context, objectKey string) (storagepkg.Object, error) {
	s.getCalled = true
	s.getObjectKey = objectKey
	if s.getErr != nil {
		return storagepkg.Object{}, s.getErr
	}
	return storagepkg.Object{
		Body: io.NopCloser(strings.NewReader(s.getBody)),
		Size: s.getSize,
	}, nil
}

func (s *fakeObjectStorage) RemoveObject(ctx context.Context, objectKey string) error {
	s.removedObjectKeys = append(s.removedObjectKeys, objectKey)
	if s.removeErr != nil {
		return s.removeErr
	}
	return nil
}

func validAvatarUpload() AvatarUpload {
	return AvatarUpload{
		Reader:      strings.NewReader("avatar-bytes"),
		SizeBytes:   int64(len("avatar-bytes")),
		ContentType: "image/jpeg",
		Extension:   "jpg",
	}
}
