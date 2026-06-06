package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"inkconnect/internal/config"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

const (
	HealthStatusDisabled = "disabled"
	HealthStatusOK       = "ok"
	HealthStatusError    = "error"
)

var ErrUnavailable = errors.New("s3 storage is unavailable")

type HealthStatus struct {
	Status   string `json:"status"`
	Bucket   string `json:"bucket,omitempty"`
	Endpoint string `json:"endpoint,omitempty"`
	Error    string `json:"error,omitempty"`
}

type S3Client struct {
	cfg     config.S3Config
	client  *minio.Client
	initErr error
}

type Object struct {
	Body io.ReadCloser
	Size int64
}

func NewS3Client(cfg config.S3Config) *S3Client {
	s3 := &S3Client{cfg: cfg}
	if !cfg.Enabled {
		return s3
	}

	endpoint, secure := normalizeEndpoint(cfg.Endpoint, cfg.UseSSL)
	if endpoint == "" || strings.TrimSpace(cfg.Bucket) == "" || strings.TrimSpace(cfg.AccessKey) == "" || strings.TrimSpace(cfg.SecretKey) == "" {
		s3.initErr = fmt.Errorf("S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY and S3_SECRET_KEY are required when S3_ENABLED=true")
		return s3
	}

	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: secure,
		Region: cfg.Region,
	})
	if err != nil {
		s3.initErr = err
		return s3
	}

	s3.client = client
	return s3
}

func (s *S3Client) Bucket() string {
	return strings.TrimSpace(s.cfg.Bucket)
}

func (s *S3Client) PutObject(ctx context.Context, objectKey string, body io.Reader, size int64, contentType string) error {
	if err := s.ready(); err != nil {
		return err
	}

	_, err := s.client.PutObject(ctx, s.cfg.Bucket, objectKey, body, size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		return fmt.Errorf("put s3 object: %w", err)
	}

	return nil
}

func (s *S3Client) GetObject(ctx context.Context, objectKey string) (Object, error) {
	if err := s.ready(); err != nil {
		return Object{}, err
	}

	info, err := s.client.StatObject(ctx, s.cfg.Bucket, objectKey, minio.StatObjectOptions{})
	if err != nil {
		return Object{}, fmt.Errorf("stat s3 object: %w", err)
	}

	object, err := s.client.GetObject(ctx, s.cfg.Bucket, objectKey, minio.GetObjectOptions{})
	if err != nil {
		return Object{}, fmt.Errorf("get s3 object: %w", err)
	}

	return Object{
		Body: object,
		Size: info.Size,
	}, nil
}

func (s *S3Client) RemoveObject(ctx context.Context, objectKey string) error {
	if err := s.ready(); err != nil {
		return err
	}

	if err := s.client.RemoveObject(ctx, s.cfg.Bucket, objectKey, minio.RemoveObjectOptions{}); err != nil {
		return fmt.Errorf("remove s3 object: %w", err)
	}

	return nil
}

func (s *S3Client) Health(ctx context.Context) HealthStatus {
	status := HealthStatus{
		Bucket:   s.cfg.Bucket,
		Endpoint: s.cfg.Endpoint,
	}

	if !s.cfg.Enabled {
		status.Status = HealthStatusDisabled
		return status
	}

	if s.initErr != nil {
		status.Status = HealthStatusError
		status.Error = s.initErr.Error()
		return status
	}

	exists, err := s.client.BucketExists(ctx, s.cfg.Bucket)
	if err != nil {
		status.Status = HealthStatusError
		status.Error = err.Error()
		return status
	}
	if !exists {
		status.Status = HealthStatusError
		status.Error = fmt.Sprintf("bucket %q does not exist", s.cfg.Bucket)
		return status
	}

	status.Status = HealthStatusOK
	return status
}

func (s *S3Client) ready() error {
	if !s.cfg.Enabled || s.client == nil {
		return ErrUnavailable
	}
	if s.initErr != nil {
		return fmt.Errorf("%w: %v", ErrUnavailable, s.initErr)
	}
	if strings.TrimSpace(s.cfg.Bucket) == "" {
		return fmt.Errorf("%w: S3_BUCKET is required", ErrUnavailable)
	}

	return nil
}

func normalizeEndpoint(endpoint string, useSSL bool) (string, bool) {
	normalized := strings.TrimSpace(endpoint)
	secure := useSSL

	if strings.HasPrefix(normalized, "http://") {
		normalized = strings.TrimPrefix(normalized, "http://")
		secure = false
	}
	if strings.HasPrefix(normalized, "https://") {
		normalized = strings.TrimPrefix(normalized, "https://")
		secure = true
	}

	normalized = strings.TrimRight(normalized, "/")
	return normalized, secure
}
