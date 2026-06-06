package publications

import (
	"errors"
	"io"
	"time"
)

const (
	MaxPublicationPhotos      = 10
	MaxPublicationPhotoBytes  = 50 * 1024 * 1024
	MaxPublicationDescription = 2000
	MaxPublicationStyleLength = 120
)

var (
	ErrPublicationNotFound           = errors.New("publication not found")
	ErrPublicationForbidden          = errors.New("publication access forbidden")
	ErrPublicationInvalidInput       = errors.New("publication input is invalid")
	ErrPublicationPhotoRequired      = errors.New("publication photo is required")
	ErrPublicationTooManyPhotos      = errors.New("publication has too many photos")
	ErrPublicationMediaNotFound      = errors.New("publication media not found")
	ErrPublicationMasterOnly         = errors.New("publication requires master account")
	ErrPublicationStorageUnavailable = errors.New("publication storage unavailable")
	ErrPublicationUnsupportedContent = errors.New("publication photo content type is unsupported")
	ErrPublicationFileRequired       = errors.New("publication photo file is required")
	ErrPublicationFileTooLarge       = errors.New("publication photo file is too large")
)

type Publication struct {
	ID               string             `json:"id"`
	MasterID         string             `json:"master_id"`
	Description      string             `json:"description"`
	CommentsDisabled bool               `json:"comments_disabled"`
	Styles           []string           `json:"styles"`
	Media            []PublicationMedia `json:"media"`
	CoverImageURL    string             `json:"cover_image_url,omitempty"`
	CreatedAt        time.Time          `json:"created_at"`
	UpdatedAt        time.Time          `json:"updated_at"`
}

type PublicationMedia struct {
	ID          string `json:"id"`
	MediaID     string `json:"media_id"`
	ImageURL    string `json:"image_url"`
	SortOrder   int    `json:"sort_order"`
	IsCover     bool   `json:"is_cover"`
	ContentType string `json:"content_type"`
	SizeBytes   int64  `json:"size_bytes"`
}

type CreatePublicationInput struct {
	Description      string
	CommentsDisabled bool
	Styles           []string
	Media            []PublicationMediaInput
}

type CreatePublicationWithPhotosInput struct {
	Description      string
	CommentsDisabled bool
	Styles           []string
	Photos           []PublicationPhotoUpload
}

type PublicationMediaInput struct {
	MediaID   string
	SortOrder int
	IsCover   bool
}

type PublicationPhotoUpload struct {
	Reader    io.Reader
	SizeBytes int64
}
