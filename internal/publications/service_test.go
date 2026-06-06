package publications

import (
	"bytes"
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	mediastore "inkconnect/internal/media"
	"inkconnect/internal/platform/storage"
)

func TestCreateRequiresMaster(t *testing.T) {
	t.Run("empty master id", func(t *testing.T) {
		repository := &fakePublicationRepository{isMaster: true}
		service := NewService(repository, nil)

		_, err := service.Create(context.Background(), "   ", validCreatePublicationInput())
		if !errors.Is(err, ErrPublicationMasterOnly) {
			t.Fatalf("Create error = %v, want %v", err, ErrPublicationMasterOnly)
		}
		if repository.isMasterCalled {
			t.Fatal("IsMaster should not be called")
		}
		if repository.createCalled {
			t.Fatal("Create repository method should not be called")
		}
	})

	t.Run("not master", func(t *testing.T) {
		repository := &fakePublicationRepository{isMaster: false}
		service := NewService(repository, nil)

		_, err := service.Create(context.Background(), "user-1", validCreatePublicationInput())
		if !errors.Is(err, ErrPublicationMasterOnly) {
			t.Fatalf("Create error = %v, want %v", err, ErrPublicationMasterOnly)
		}
		if !repository.isMasterCalled {
			t.Fatal("IsMaster should be called")
		}
		if repository.createCalled {
			t.Fatal("Create repository method should not be called")
		}
	})
}

func TestCreateNormalizesInputAndPersists(t *testing.T) {
	repository := &fakePublicationRepository{isMaster: true}
	service := NewService(repository, nil)

	publication, err := service.Create(context.Background(), " master-1 ", CreatePublicationInput{
		Description:      "  Fresh work  ",
		CommentsDisabled: true,
		Styles:           []string{"Realism", " ", "Realism", "Fine Line"},
		Media: []PublicationMediaInput{
			{MediaID: " media-2 ", SortOrder: 99, IsCover: false},
			{MediaID: "media-1", SortOrder: 99, IsCover: true},
		},
	})
	if err != nil {
		t.Fatalf("Create returned error: %v", err)
	}
	if !repository.createCalled {
		t.Fatal("Create repository method should be called")
	}
	if repository.createMasterID != "master-1" {
		t.Fatalf("create master id = %q, want master-1", repository.createMasterID)
	}
	if repository.createInput.Description != "Fresh work" {
		t.Fatalf("description = %q, want Fresh work", repository.createInput.Description)
	}
	if len(repository.createInput.Styles) != 2 || repository.createInput.Styles[0] != "Realism" || repository.createInput.Styles[1] != "Fine Line" {
		t.Fatalf("styles = %#v, want deduplicated styles", repository.createInput.Styles)
	}
	if repository.createInput.Media[0] != (PublicationMediaInput{MediaID: "media-2", SortOrder: 0, IsCover: true}) {
		t.Fatalf("first media = %#v", repository.createInput.Media[0])
	}
	if repository.createInput.Media[1] != (PublicationMediaInput{MediaID: "media-1", SortOrder: 1, IsCover: false}) {
		t.Fatalf("second media = %#v", repository.createInput.Media[1])
	}
	if publication.ID != "publication-created" {
		t.Fatalf("publication id = %q, want publication-created", publication.ID)
	}
}

func TestCreateRejectsInvalidInput(t *testing.T) {
	tests := []struct {
		name      string
		input     CreatePublicationInput
		wantError error
	}{
		{name: "description too long", input: CreatePublicationInput{Description: strings.Repeat("a", MaxPublicationDescription+1), Media: []PublicationMediaInput{{MediaID: "media-1"}}}, wantError: ErrPublicationInvalidInput},
		{name: "no media", input: CreatePublicationInput{Description: "work"}, wantError: ErrPublicationPhotoRequired},
		{name: "too many media", input: CreatePublicationInput{Media: manyMediaInputs(MaxPublicationPhotos + 1)}, wantError: ErrPublicationTooManyPhotos},
		{name: "empty media id", input: CreatePublicationInput{Media: []PublicationMediaInput{{MediaID: " "}}}, wantError: ErrPublicationInvalidInput},
		{name: "duplicate media id", input: CreatePublicationInput{Media: []PublicationMediaInput{{MediaID: "media-1"}, {MediaID: " media-1 "}}}, wantError: ErrPublicationInvalidInput},
		{name: "style too long", input: CreatePublicationInput{Styles: []string{strings.Repeat("a", MaxPublicationStyleLength+1)}, Media: []PublicationMediaInput{{MediaID: "media-1"}}}, wantError: ErrPublicationInvalidInput},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := &fakePublicationRepository{isMaster: true}
			service := NewService(repository, nil)

			_, err := service.Create(context.Background(), "master-1", tt.input)
			if !errors.Is(err, tt.wantError) {
				t.Fatalf("Create error = %v, want %v", err, tt.wantError)
			}
			if repository.createCalled {
				t.Fatal("Create repository method should not be called")
			}
		})
	}
}

func TestCreateWithPhotosUploadsAndPersistsGeneratedObjects(t *testing.T) {
	ctx := context.Background()
	repository := &fakePublicationRepository{isMaster: true}
	storage := &fakePublicationStorage{bucket: "inkconnect-files"}
	service := NewService(repository, storage)

	first := pngBytes("first")
	second := pngBytes("second")
	publication, err := service.CreateWithPhotos(ctx, "master-1", CreatePublicationWithPhotosInput{
		Description:      "  fresh work  ",
		Styles:           []string{"Реализм", "Реализм", "Fine Line"},
		CommentsDisabled: true,
		Photos: []PublicationPhotoUpload{
			{Reader: bytes.NewReader(first), SizeBytes: int64(len(first))},
			{Reader: bytes.NewReader(second), SizeBytes: int64(len(second))},
		},
	})
	if err != nil {
		t.Fatalf("CreateWithPhotos returned error: %v", err)
	}

	if publication.ID == "" || repository.publicationID == "" {
		t.Fatal("publication id was not generated")
	}
	if publication.ID != repository.publicationID {
		t.Fatalf("publication id mismatch: got %q want %q", publication.ID, repository.publicationID)
	}
	if repository.input.Description != "fresh work" {
		t.Fatalf("description was not normalized: %q", repository.input.Description)
	}
	if len(repository.input.Styles) != 2 {
		t.Fatalf("styles were not deduplicated: %#v", repository.input.Styles)
	}
	if len(storage.puts) != 2 {
		t.Fatalf("expected 2 uploaded objects, got %d", len(storage.puts))
	}
	if len(repository.objects) != 2 || len(repository.input.Media) != 2 {
		t.Fatalf("expected 2 saved media objects, got objects=%d media=%d", len(repository.objects), len(repository.input.Media))
	}

	for index, object := range repository.objects {
		if object.OwnerUserID != "master-1" {
			t.Fatalf("object owner mismatch: %q", object.OwnerUserID)
		}
		if object.Bucket != "inkconnect-files" {
			t.Fatalf("object bucket mismatch: %q", object.Bucket)
		}
		if object.Kind != mediastore.KindMasterPublicationPhoto {
			t.Fatalf("object kind mismatch: %q", object.Kind)
		}
		if object.ContentType != "image/png" {
			t.Fatalf("object content type mismatch: %q", object.ContentType)
		}
		expectedPrefix := "masters/master-1/publications/" + publication.ID + "/"
		if !strings.HasPrefix(object.ObjectKey, expectedPrefix) || !strings.HasSuffix(object.ObjectKey, ".png") {
			t.Fatalf("unexpected object key: %q", object.ObjectKey)
		}
		if repository.input.Media[index].SortOrder != index {
			t.Fatalf("sort order mismatch at %d: %d", index, repository.input.Media[index].SortOrder)
		}
		if repository.input.Media[index].IsCover != (index == 0) {
			t.Fatalf("cover flag mismatch at %d", index)
		}
		if storage.puts[index].objectKey != object.ObjectKey {
			t.Fatalf("uploaded key mismatch at %d", index)
		}
		if len(storage.puts[index].body) != int(object.SizeBytes) {
			t.Fatalf("uploaded body size mismatch at %d", index)
		}
	}
}

func TestCreateWithPhotosCleansUpUploadedObjectsOnRepositoryError(t *testing.T) {
	ctx := context.Background()
	repository := &fakePublicationRepository{
		isMaster:  true,
		createErr: errors.New("metadata failed"),
	}
	storage := &fakePublicationStorage{bucket: "inkconnect-files"}
	service := NewService(repository, storage)

	photo := pngBytes("cleanup")
	_, err := service.CreateWithPhotos(ctx, "master-1", CreatePublicationWithPhotosInput{
		Photos: []PublicationPhotoUpload{{Reader: bytes.NewReader(photo), SizeBytes: int64(len(photo))}},
	})
	if !errors.Is(err, repository.createErr) {
		t.Fatalf("expected repository error, got %v", err)
	}
	if len(storage.puts) != 1 {
		t.Fatalf("expected 1 uploaded object, got %d", len(storage.puts))
	}
	if len(storage.removed) != 1 {
		t.Fatalf("expected uploaded object cleanup, got %d removals", len(storage.removed))
	}
	if storage.removed[0] != storage.puts[0].objectKey {
		t.Fatalf("cleanup removed %q, want %q", storage.removed[0], storage.puts[0].objectKey)
	}
}

func TestCreateWithPhotosRejectsUnsupportedContent(t *testing.T) {
	ctx := context.Background()
	repository := &fakePublicationRepository{isMaster: true}
	storage := &fakePublicationStorage{bucket: "inkconnect-files"}
	service := NewService(repository, storage)

	payload := []byte("not an image")
	_, err := service.CreateWithPhotos(ctx, "master-1", CreatePublicationWithPhotosInput{
		Photos: []PublicationPhotoUpload{{Reader: bytes.NewReader(payload), SizeBytes: int64(len(payload))}},
	})
	if !errors.Is(err, ErrPublicationUnsupportedContent) {
		t.Fatalf("expected unsupported content error, got %v", err)
	}
	if len(storage.puts) != 0 {
		t.Fatalf("unsupported content should not upload, got %d uploads", len(storage.puts))
	}
}

func TestCreateWithPhotosRequiresStorage(t *testing.T) {
	t.Run("nil storage", func(t *testing.T) {
		repository := &fakePublicationRepository{isMaster: true}
		service := NewService(repository, nil)

		_, err := service.CreateWithPhotos(context.Background(), "master-1", validCreateWithPhotosInput())
		if !errors.Is(err, ErrPublicationStorageUnavailable) {
			t.Fatalf("CreateWithPhotos error = %v, want %v", err, ErrPublicationStorageUnavailable)
		}
		if repository.isMasterCalled {
			t.Fatal("IsMaster should not be called")
		}
		if repository.publicationID != "" {
			t.Fatal("CreateWithMediaObjects should not be called")
		}
	})

	t.Run("empty bucket", func(t *testing.T) {
		repository := &fakePublicationRepository{isMaster: true}
		storage := &fakePublicationStorage{}
		service := NewService(repository, storage)

		_, err := service.CreateWithPhotos(context.Background(), "master-1", validCreateWithPhotosInput())
		if !errors.Is(err, ErrPublicationStorageUnavailable) {
			t.Fatalf("CreateWithPhotos error = %v, want %v", err, ErrPublicationStorageUnavailable)
		}
		if repository.isMasterCalled {
			t.Fatal("IsMaster should not be called")
		}
		if len(storage.puts) != 0 {
			t.Fatalf("uploads = %d, want 0", len(storage.puts))
		}
	})
}

func TestCreateWithPhotosRejectsInvalidPhotoInput(t *testing.T) {
	tests := []struct {
		name      string
		input     CreatePublicationWithPhotosInput
		wantError error
	}{
		{name: "no photos", input: CreatePublicationWithPhotosInput{}, wantError: ErrPublicationPhotoRequired},
		{name: "too many photos", input: CreatePublicationWithPhotosInput{Photos: manyPhotos(MaxPublicationPhotos + 1)}, wantError: ErrPublicationTooManyPhotos},
		{name: "nil reader", input: CreatePublicationWithPhotosInput{Photos: []PublicationPhotoUpload{{SizeBytes: 1}}}, wantError: ErrPublicationFileRequired},
		{name: "zero size", input: CreatePublicationWithPhotosInput{Photos: []PublicationPhotoUpload{{Reader: bytes.NewReader(pngBytes("x")), SizeBytes: 0}}}, wantError: ErrPublicationFileRequired},
		{name: "too large", input: CreatePublicationWithPhotosInput{Photos: []PublicationPhotoUpload{{Reader: bytes.NewReader(pngBytes("x")), SizeBytes: MaxPublicationPhotoBytes + 1}}}, wantError: ErrPublicationFileTooLarge},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := &fakePublicationRepository{isMaster: true}
			storage := &fakePublicationStorage{bucket: "inkconnect-files"}
			service := NewService(repository, storage)

			_, err := service.CreateWithPhotos(context.Background(), "master-1", tt.input)
			if !errors.Is(err, tt.wantError) {
				t.Fatalf("CreateWithPhotos error = %v, want %v", err, tt.wantError)
			}
			if len(storage.puts) != 0 {
				t.Fatalf("uploads = %d, want 0", len(storage.puts))
			}
			if repository.publicationID != "" {
				t.Fatal("CreateWithMediaObjects should not be called")
			}
		})
	}
}

func TestCreateWithPhotosSupportsJPEGPNGWEBP(t *testing.T) {
	tests := []struct {
		name        string
		photo       []byte
		contentType string
		extension   string
	}{
		{name: "jpeg", photo: jpegBytes("photo"), contentType: "image/jpeg", extension: ".jpg"},
		{name: "png", photo: pngBytes("photo"), contentType: "image/png", extension: ".png"},
		{name: "webp", photo: webpBytes("photo"), contentType: "image/webp", extension: ".webp"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := &fakePublicationRepository{isMaster: true}
			storage := &fakePublicationStorage{bucket: "inkconnect-files"}
			service := NewService(repository, storage)

			_, err := service.CreateWithPhotos(context.Background(), "master-1", CreatePublicationWithPhotosInput{
				Photos: []PublicationPhotoUpload{{Reader: bytes.NewReader(tt.photo), SizeBytes: int64(len(tt.photo))}},
			})
			if err != nil {
				t.Fatalf("CreateWithPhotos returned error: %v", err)
			}
			if len(repository.objects) != 1 {
				t.Fatalf("objects = %d, want 1", len(repository.objects))
			}
			if repository.objects[0].ContentType != tt.contentType {
				t.Fatalf("content type = %q, want %q", repository.objects[0].ContentType, tt.contentType)
			}
			if !strings.HasSuffix(repository.objects[0].ObjectKey, tt.extension) {
				t.Fatalf("object key = %q, want suffix %q", repository.objects[0].ObjectKey, tt.extension)
			}
		})
	}
}

func TestCreateWithPhotosMapsStorageUnavailableAndCleansUploaded(t *testing.T) {
	repository := &fakePublicationRepository{isMaster: true}
	storage := &fakePublicationStorage{
		bucket:        "inkconnect-files",
		putErr:        storage.ErrUnavailable,
		failOnPutCall: 2,
	}
	service := NewService(repository, storage)
	first := pngBytes("first")
	second := pngBytes("second")

	_, err := service.CreateWithPhotos(context.Background(), "master-1", CreatePublicationWithPhotosInput{
		Photos: []PublicationPhotoUpload{
			{Reader: bytes.NewReader(first), SizeBytes: int64(len(first))},
			{Reader: bytes.NewReader(second), SizeBytes: int64(len(second))},
		},
	})
	if !errors.Is(err, ErrPublicationStorageUnavailable) {
		t.Fatalf("CreateWithPhotos error = %v, want %v", err, ErrPublicationStorageUnavailable)
	}
	if len(storage.puts) != 1 {
		t.Fatalf("successful uploads = %d, want 1", len(storage.puts))
	}
	if len(storage.removed) != 1 || storage.removed[0] != storage.puts[0].objectKey {
		t.Fatalf("removed keys = %#v, want cleanup for %q", storage.removed, storage.puts[0].objectKey)
	}
	if repository.publicationID != "" {
		t.Fatal("CreateWithMediaObjects should not be called")
	}
}

func TestListByMasterUsernameTrimsAndDelegates(t *testing.T) {
	repository := &fakePublicationRepository{
		listResult: []Publication{{ID: "publication-1", MasterID: "master-1"}},
	}
	service := NewService(repository, nil)

	publications, err := service.ListByMasterUsername(context.Background(), " master ")
	if err != nil {
		t.Fatalf("ListByMasterUsername returned error: %v", err)
	}
	if repository.listUsername != "master" {
		t.Fatalf("list username = %q, want master", repository.listUsername)
	}
	if len(publications) != 1 || publications[0].ID != "publication-1" {
		t.Fatalf("publications = %#v", publications)
	}
}

func TestListByMasterUsernameRejectsEmptyUsername(t *testing.T) {
	repository := &fakePublicationRepository{}
	service := NewService(repository, nil)

	_, err := service.ListByMasterUsername(context.Background(), "   ")
	if !errors.Is(err, ErrPublicationNotFound) {
		t.Fatalf("ListByMasterUsername error = %v, want %v", err, ErrPublicationNotFound)
	}
	if repository.listCalled {
		t.Fatal("ListByMasterUsername repository method should not be called")
	}
}

func TestGetTrimsAndDelegates(t *testing.T) {
	repository := &fakePublicationRepository{findResult: Publication{ID: "publication-1", MasterID: "master-1"}}
	service := NewService(repository, nil)

	publication, err := service.Get(context.Background(), " publication-1 ")
	if err != nil {
		t.Fatalf("Get returned error: %v", err)
	}
	if repository.findPublicationID != "publication-1" {
		t.Fatalf("find publication id = %q, want publication-1", repository.findPublicationID)
	}
	if publication.ID != "publication-1" {
		t.Fatalf("publication id = %q, want publication-1", publication.ID)
	}
}

func TestGetRejectsEmptyID(t *testing.T) {
	repository := &fakePublicationRepository{}
	service := NewService(repository, nil)

	_, err := service.Get(context.Background(), "   ")
	if !errors.Is(err, ErrPublicationNotFound) {
		t.Fatalf("Get error = %v, want %v", err, ErrPublicationNotFound)
	}
	if repository.findCalled {
		t.Fatal("FindByID should not be called")
	}
}

func TestDeleteRequiresMasterAndPublicationID(t *testing.T) {
	t.Run("empty master", func(t *testing.T) {
		repository := &fakePublicationRepository{isMaster: true}
		service := NewService(repository, nil)

		err := service.Delete(context.Background(), "   ", "publication-1")
		if !errors.Is(err, ErrPublicationMasterOnly) {
			t.Fatalf("Delete error = %v, want %v", err, ErrPublicationMasterOnly)
		}
		if repository.softDeleteCalled {
			t.Fatal("SoftDelete should not be called")
		}
	})

	t.Run("empty publication", func(t *testing.T) {
		repository := &fakePublicationRepository{isMaster: true}
		service := NewService(repository, nil)

		err := service.Delete(context.Background(), "master-1", "   ")
		if !errors.Is(err, ErrPublicationNotFound) {
			t.Fatalf("Delete error = %v, want %v", err, ErrPublicationNotFound)
		}
		if repository.softDeleteCalled {
			t.Fatal("SoftDelete should not be called")
		}
	})
}

func TestDeleteRejectsNonMaster(t *testing.T) {
	repository := &fakePublicationRepository{isMaster: false}
	service := NewService(repository, nil)

	err := service.Delete(context.Background(), "user-1", "publication-1")
	if !errors.Is(err, ErrPublicationMasterOnly) {
		t.Fatalf("Delete error = %v, want %v", err, ErrPublicationMasterOnly)
	}
	if repository.findCalled {
		t.Fatal("FindByID should not be called")
	}
	if repository.softDeleteCalled {
		t.Fatal("SoftDelete should not be called")
	}
}

func TestDeleteRejectsForeignPublication(t *testing.T) {
	repository := &fakePublicationRepository{
		isMaster:   true,
		findResult: Publication{ID: "publication-1", MasterID: "other-master"},
	}
	service := NewService(repository, nil)

	err := service.Delete(context.Background(), "master-1", "publication-1")
	if !errors.Is(err, ErrPublicationForbidden) {
		t.Fatalf("Delete error = %v, want %v", err, ErrPublicationForbidden)
	}
	if repository.softDeleteCalled {
		t.Fatal("SoftDelete should not be called")
	}
}

func TestDeleteSoftDeletesOwnPublication(t *testing.T) {
	repository := &fakePublicationRepository{
		isMaster:   true,
		findResult: Publication{ID: "publication-1", MasterID: "master-1"},
	}
	service := NewService(repository, nil)

	if err := service.Delete(context.Background(), " master-1 ", " publication-1 "); err != nil {
		t.Fatalf("Delete returned error: %v", err)
	}
	if !repository.softDeleteCalled {
		t.Fatal("SoftDelete should be called")
	}
	if repository.softDeleteMasterID != "master-1" || repository.softDeletePublicationID != "publication-1" {
		t.Fatalf("soft delete args = (%q, %q)", repository.softDeleteMasterID, repository.softDeletePublicationID)
	}
}

func TestPublicationObjectKeyTrimsParts(t *testing.T) {
	key := publicationObjectKey(" master-1 ", " publication-1 ", " media-1 ", ".jpg")
	want := "masters/master-1/publications/publication-1/media-1.jpg"
	if key != want {
		t.Fatalf("publicationObjectKey = %q, want %q", key, want)
	}
}

func pngBytes(label string) []byte {
	payload := append([]byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}, []byte(label)...)
	return payload
}

func jpegBytes(label string) []byte {
	payload := append([]byte{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 'J', 'F', 'I', 'F', 0x00}, []byte(label)...)
	return payload
}

func webpBytes(label string) []byte {
	payload := append([]byte{'R', 'I', 'F', 'F', 0x00, 0x00, 0x00, 0x00, 'W', 'E', 'B', 'P'}, []byte(label)...)
	return payload
}

func manyMediaInputs(count int) []PublicationMediaInput {
	media := make([]PublicationMediaInput, 0, count)
	for index := 0; index < count; index++ {
		media = append(media, PublicationMediaInput{MediaID: "media-" + string(rune('a'+index))})
	}
	return media
}

func manyPhotos(count int) []PublicationPhotoUpload {
	photos := make([]PublicationPhotoUpload, 0, count)
	for index := 0; index < count; index++ {
		photo := pngBytes("photo")
		photos = append(photos, PublicationPhotoUpload{Reader: bytes.NewReader(photo), SizeBytes: int64(len(photo))})
	}
	return photos
}

func validCreatePublicationInput() CreatePublicationInput {
	return CreatePublicationInput{
		Description: "Fresh work",
		Media:       []PublicationMediaInput{{MediaID: "media-1"}},
	}
}

func validCreateWithPhotosInput() CreatePublicationWithPhotosInput {
	photo := pngBytes("valid")
	return CreatePublicationWithPhotosInput{
		Photos: []PublicationPhotoUpload{{Reader: bytes.NewReader(photo), SizeBytes: int64(len(photo))}},
	}
}

type fakePublicationRepository struct {
	isMaster       bool
	isMasterCalled bool
	isMasterErr    error

	createCalled      bool
	createMasterID    string
	createInput       CreatePublicationInput
	createPublication Publication
	createErr         error

	publicationID string
	input         CreatePublicationInput
	objects       []mediastore.Object

	listCalled   bool
	listUsername string
	listResult   []Publication
	listErr      error

	findCalled        bool
	findPublicationID string
	findResult        Publication
	findErr           error

	softDeleteCalled        bool
	softDeleteMasterID      string
	softDeletePublicationID string
	softDeleteErr           error
}

func (r *fakePublicationRepository) IsMaster(ctx context.Context, userID string) (bool, error) {
	r.isMasterCalled = true
	if r.isMasterErr != nil {
		return false, r.isMasterErr
	}
	return r.isMaster, nil
}

func (r *fakePublicationRepository) Create(ctx context.Context, masterID string, input CreatePublicationInput) (Publication, error) {
	r.createCalled = true
	r.createMasterID = masterID
	r.createInput = input
	if r.createErr != nil {
		return Publication{}, r.createErr
	}
	if r.createPublication.ID != "" {
		return r.createPublication, nil
	}
	return Publication{ID: "publication-created", MasterID: masterID}, nil
}

func (r *fakePublicationRepository) CreateWithMediaObjects(ctx context.Context, masterID string, publicationID string, input CreatePublicationInput, objects []mediastore.Object) (Publication, error) {
	r.publicationID = publicationID
	r.input = input
	r.objects = append([]mediastore.Object(nil), objects...)
	if r.createErr != nil {
		return Publication{}, r.createErr
	}
	return Publication{ID: publicationID, MasterID: masterID}, nil
}

func (r *fakePublicationRepository) ListByMasterUsername(ctx context.Context, username string) ([]Publication, error) {
	r.listCalled = true
	r.listUsername = username
	if r.listErr != nil {
		return nil, r.listErr
	}
	return r.listResult, nil
}

func (r *fakePublicationRepository) FindByID(ctx context.Context, publicationID string) (Publication, error) {
	r.findCalled = true
	r.findPublicationID = publicationID
	if r.findErr != nil {
		return Publication{}, r.findErr
	}
	if r.findResult.ID != "" {
		return r.findResult, nil
	}
	return Publication{}, ErrPublicationNotFound
}

func (r *fakePublicationRepository) SoftDelete(ctx context.Context, masterID string, publicationID string) error {
	r.softDeleteCalled = true
	r.softDeleteMasterID = masterID
	r.softDeletePublicationID = publicationID
	if r.softDeleteErr != nil {
		return r.softDeleteErr
	}
	return nil
}

type fakePublicationStorage struct {
	bucket        string
	puts          []fakePublicationPut
	removed       []string
	putErr        error
	putCalls      int
	failOnPutCall int
}

type fakePublicationPut struct {
	objectKey   string
	contentType string
	size        int64
	body        []byte
}

func (s *fakePublicationStorage) Bucket() string {
	return s.bucket
}

func (s *fakePublicationStorage) PutObject(ctx context.Context, objectKey string, body io.Reader, size int64, contentType string) error {
	s.putCalls++
	if s.putErr != nil && (s.failOnPutCall == 0 || s.failOnPutCall == s.putCalls) {
		return s.putErr
	}
	bytes, err := io.ReadAll(body)
	if err != nil {
		return err
	}
	s.puts = append(s.puts, fakePublicationPut{
		objectKey:   objectKey,
		contentType: contentType,
		size:        size,
		body:        bytes,
	})
	return nil
}

func (s *fakePublicationStorage) RemoveObject(ctx context.Context, objectKey string) error {
	s.removed = append(s.removed, objectKey)
	return nil
}
