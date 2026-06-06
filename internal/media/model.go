package media

import (
	"errors"
	"io"
	"time"
)

const (
	KindUserAvatar             = "user_avatar"
	KindMasterPortfolio        = "master_portfolio"
	KindMasterPublicationPhoto = "master_publication_photo"

	MaxAvatarBytes = 5 * 1024 * 1024
)

var (
	ErrMediaNotFound          = errors.New("media not found")
	ErrOwnerNotFound          = errors.New("media owner not found")
	ErrStorageUnavailable     = errors.New("storage unavailable")
	ErrUnsupportedContentType = errors.New("unsupported content type")
	ErrFileRequired           = errors.New("file is required")
	ErrFileTooLarge           = errors.New("file is too large")
)

type Object struct {
	ID          string
	OwnerUserID string
	Bucket      string
	ObjectKey   string
	Kind        string
	ContentType string
	SizeBytes   int64
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

type AvatarUpload struct {
	Reader      io.Reader
	SizeBytes   int64
	ContentType string
	Extension   string
}

type ServedObject struct {
	Media Object
	Body  io.ReadCloser
	Size  int64
}
