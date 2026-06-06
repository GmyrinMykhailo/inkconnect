package storage

import (
	"context"
	"testing"

	"inkconnect/internal/config"
)

func TestS3ClientHealthDisabled(t *testing.T) {
	client := NewS3Client(config.S3Config{Enabled: false})

	status := client.Health(context.Background())

	if status.Status != HealthStatusDisabled {
		t.Fatalf("expected disabled status, got %q", status.Status)
	}
}

func TestS3ClientHealthMissingRequiredConfig(t *testing.T) {
	client := NewS3Client(config.S3Config{Enabled: true})

	status := client.Health(context.Background())

	if status.Status != HealthStatusError {
		t.Fatalf("expected error status, got %q", status.Status)
	}
	if status.Error == "" {
		t.Fatal("expected missing config error")
	}
}
