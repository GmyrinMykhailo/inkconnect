package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

type Config struct {
	AppAddr                   string
	DatabaseURL               string
	TemplatesDir              string
	StaticDir                 string
	SessionCookieName         string
	SessionDuration           time.Duration
	SigningKeyEncryptionKey   string
	SigningKeyEncryptionKeyID string
	ChatEncryptionKey         string
	S3                        S3Config
}

type S3Config struct {
	Enabled        bool
	Endpoint       string
	PublicEndpoint string
	Bucket         string
	Region         string
	AccessKey      string
	SecretKey      string
	UseSSL         bool
}

func Load() (Config, error) {
	_ = godotenv.Load()

	host := getEnv("POSTGRES_HOST", "127.0.0.1")
	port := getEnv("POSTGRES_PORT", "5432")
	dbName := getEnv("POSTGRES_DB", "inkconnect")
	user := getEnv("POSTGRES_USER", "postgres")
	password := getEnv("POSTGRES_PASSWORD", "")
	sslMode := getEnv("POSTGRES_SSLMODE", "disable")

	if password == "" {
		return Config{}, fmt.Errorf("POSTGRES_PASSWORD is required")
	}

	return Config{
		AppAddr:                   getEnv("APP_ADDR", ":8080"),
		DatabaseURL:               fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s", user, password, host, port, dbName, sslMode),
		TemplatesDir:              getEnv("TEMPLATES_DIR", "web/templates"),
		StaticDir:                 getEnv("STATIC_DIR", "web/static"),
		SessionCookieName:         getEnv("SESSION_COOKIE_NAME", "inkconnect_session"),
		SessionDuration:           getEnvDuration("SESSION_DURATION_HOURS", 24*time.Hour),
		SigningKeyEncryptionKey:   getEnv("SIGNING_KEY_ENCRYPTION_KEY", ""),
		SigningKeyEncryptionKeyID: getEnv("SIGNING_KEY_ENCRYPTION_KEY_ID", ""),
		ChatEncryptionKey:         getEnv("CHAT_ENCRYPTION_KEY", ""),
		S3: S3Config{
			Enabled:        getEnvBool("S3_ENABLED", false),
			Endpoint:       getEnv("S3_ENDPOINT", ""),
			PublicEndpoint: getEnv("S3_PUBLIC_ENDPOINT", ""),
			Bucket:         getEnv("S3_BUCKET", "inkconnect-files"),
			Region:         getEnv("S3_REGION", "us-east-1"),
			AccessKey:      getEnv("S3_ACCESS_KEY", ""),
			SecretKey:      getEnv("S3_SECRET_KEY", ""),
			UseSSL:         getEnvBool("S3_USE_SSL", false),
		},
	}, nil
}

func getEnv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	return value
}

func getEnvBool(key string, fallback bool) bool {
	value := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if value == "" {
		return fallback
	}

	switch value {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}

func getEnvDuration(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	duration, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}

	return duration
}
