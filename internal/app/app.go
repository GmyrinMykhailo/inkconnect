package app

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"time"

	"inkconnect/internal/appointments"
	"inkconnect/internal/catalog"
	"inkconnect/internal/chat"
	"inkconnect/internal/config"
	httpapp "inkconnect/internal/http"
	"inkconnect/internal/http/handlers"
	"inkconnect/internal/journal"
	"inkconnect/internal/media"
	"inkconnect/internal/platform/database"
	"inkconnect/internal/platform/storage"
	"inkconnect/internal/publications"
	"inkconnect/internal/recommendations"
	"inkconnect/internal/users"
)

type App struct {
	cfg    config.Config
	db     *sql.DB
	server *http.Server
}

func New() (*App, error) {
	cfg, err := config.Load()
	if err != nil {
		return nil, err
	}

	db, err := database.Open(cfg.DatabaseURL)
	if err != nil {
		return nil, err
	}

	schemaCtx, cancelSchema := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelSchema()
	if err := media.EnsureMediaSchema(schemaCtx, db); err != nil {
		return nil, err
	}
	if err := publications.EnsurePublicationSchema(schemaCtx, db); err != nil {
		return nil, err
	}
	if err := catalog.EnsureMasterServicesSchema(schemaCtx, db); err != nil {
		return nil, err
	}
	if err := appointments.EnsureAppointmentsSchema(schemaCtx, db); err != nil {
		return nil, err
	}
	if err := recommendations.EnsureRecommendationsSchema(schemaCtx, db); err != nil {
		return nil, err
	}
	if err := journal.EnsureJournalSchema(schemaCtx, db, journal.RepositorySigningConfig{
		EncryptionKey:   cfg.SigningKeyEncryptionKey,
		EncryptionKeyID: cfg.SigningKeyEncryptionKeyID,
	}); err != nil {
		return nil, err
	}
	if err := users.EnsureFavoriteMastersSchema(schemaCtx, db); err != nil {
		return nil, err
	}
	if err := chat.EnsureChatSchema(schemaCtx, db); err != nil {
		return nil, err
	}

	userRepository := users.NewPostgresRepository(db)
	mediaRepository := media.NewPostgresRepository(db)
	publicationsRepository := publications.NewPostgresRepository(db)
	chatRepository := chat.NewPostgresRepository(db)
	serviceRepository := catalog.NewPostgresServiceRepository(db)
	appointmentsRepository := appointments.NewPostgresRepository(db)
	recommendationsRepository := recommendations.NewPostgresRepository(db)
	journalRepository := journal.NewPostgresRepository(db, journal.RepositorySigningConfig{
		EncryptionKey:   cfg.SigningKeyEncryptionKey,
		EncryptionKeyID: cfg.SigningKeyEncryptionKeyID,
	})
	registrationService := users.NewRegistrationService(userRepository, users.RegistrationSigningConfig{
		EncryptionKey:   cfg.SigningKeyEncryptionKey,
		EncryptionKeyID: cfg.SigningKeyEncryptionKeyID,
	})
	authenticationService := users.NewAuthenticationService(userRepository, cfg.SessionDuration)
	profileService := users.NewProfileService(userRepository)
	securityService := users.NewSecurityService(userRepository)
	storageClient := storage.NewS3Client(cfg.S3)
	mediaService := media.NewService(mediaRepository, storageClient)
	publicationsService := publications.NewService(publicationsRepository, storageClient)
	masterServicesService := catalog.NewMasterServicesService(serviceRepository)
	appointmentsService := appointments.NewService(appointmentsRepository)
	journalService := journal.NewService(journalRepository, appointmentsRepository)
	recommendationsService := recommendations.NewService(recommendationsRepository, appointmentsRepository, journalService)
	chatCipher, err := chat.NewMessageCipher(cfg.ChatEncryptionKey)
	if err != nil {
		return nil, err
	}
	chatService := chat.NewService(chatRepository, chatCipher)

	registerHandler, err := handlers.NewRegistrationHandler(cfg, registrationService)
	if err != nil {
		return nil, err
	}

	authHandler, err := handlers.NewAuthHandler(cfg, authenticationService)
	if err != nil {
		return nil, err
	}

	masterSearchHandler := handlers.NewMasterSearchHandler(userRepository)
	profileHandler := handlers.NewProfileHandler(cfg, authenticationService, profileService)
	mediaHandler := handlers.NewMediaHandler(cfg, authenticationService, profileService, mediaService)
	publicationsHandler := handlers.NewPublicationsHandler(cfg, authenticationService, publicationsService)
	securityHandler := handlers.NewSecurityHandler(cfg, authenticationService, securityService)
	masterServicesHandler := handlers.NewMasterServicesHandler(cfg, authenticationService, masterServicesService)
	appointmentsHandler := handlers.NewAppointmentsHandler(cfg, authenticationService, appointmentsService)
	recommendationsHandler := handlers.NewRecommendationsHandler(cfg, authenticationService, recommendationsService)
	journalHandler := handlers.NewJournalHandler(cfg, authenticationService, journalService)
	favoritesHandler := handlers.NewFavoritesHandler(cfg, authenticationService, userRepository)
	chatHandler := handlers.NewChatHandler(cfg, authenticationService, chatService)
	usernameHandler := handlers.NewUsernameHandler(userRepository)
	authAvailabilityHandler := handlers.NewAuthAvailabilityHandler(userRepository)
	storageHandler := handlers.NewStorageHandler(storageClient)

	router := httpapp.NewRouter(cfg, registerHandler, authHandler, masterSearchHandler, profileHandler, mediaHandler, publicationsHandler, securityHandler, masterServicesHandler, appointmentsHandler, recommendationsHandler, journalHandler, favoritesHandler, chatHandler, usernameHandler, authAvailabilityHandler, storageHandler)
	server := &http.Server{
		Addr:              cfg.AppAddr,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	return &App{
		cfg:    cfg,
		db:     db,
		server: server,
	}, nil
}

func (a *App) Run() error {
	log.Printf("InkConnect backend started on %s", a.cfg.AppAddr)
	log.Printf("Login page: http://localhost%s/login", a.cfg.AppAddr)
	log.Printf("Registration page: http://localhost%s/register", a.cfg.AppAddr)
	return a.server.ListenAndServe()
}

func (a *App) Close() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := a.server.Shutdown(ctx); err != nil && err != http.ErrServerClosed {
		log.Printf("shutdown server: %v", err)
	}

	if a.db != nil {
		if err := a.db.Close(); err != nil {
			log.Printf("close db: %v", err)
		}
	}
}

func (a *App) String() string {
	return fmt.Sprintf("App(addr=%s)", a.cfg.AppAddr)
}
