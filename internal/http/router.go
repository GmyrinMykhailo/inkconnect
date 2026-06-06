package http

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"

	"inkconnect/internal/config"
	"inkconnect/internal/http/handlers"
)

func NewRouter(cfg config.Config, registrationHandler *handlers.RegistrationHandler, authHandler *handlers.AuthHandler, masterSearchHandler *handlers.MasterSearchHandler, profileHandler *handlers.ProfileHandler, mediaHandler *handlers.MediaHandler, publicationsHandler *handlers.PublicationsHandler, securityHandler *handlers.SecurityHandler, masterServicesHandler *handlers.MasterServicesHandler, appointmentsHandler *handlers.AppointmentsHandler, recommendationsHandler *handlers.RecommendationsHandler, journalHandler *handlers.JournalHandler, favoritesHandler *handlers.FavoritesHandler, chatHandler *handlers.ChatHandler, usernameHandler *handlers.UsernameHandler, authAvailabilityHandler *handlers.AuthAvailabilityHandler, storageHandler *handlers.StorageHandler) http.Handler {
	mux := http.NewServeMux()

	staticFS := http.FileServer(http.Dir(cfg.StaticDir))
	mux.Handle("/static/", http.StripPrefix("/static/", staticFS))

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		http.Redirect(w, r, "/login", http.StatusSeeOther)
	})

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"status": "ok",
			"app":    "inkconnect-backend",
		})
	})

	mux.HandleFunc("/api/v1/storage/health", storageHandler.HealthJSON)
	mux.HandleFunc("/register", registrationHandler.ServeHTTP)
	mux.HandleFunc("/login", authHandler.LoginPage)
	mux.HandleFunc("/logout", authHandler.Logout)
	mux.HandleFunc("/app", authHandler.AppPage)
	mux.HandleFunc("/api/v1/auth/register", registrationHandler.RegisterJSON)
	mux.HandleFunc("/api/v1/auth/login", authHandler.LoginJSON)
	mux.HandleFunc("/api/v1/auth/me", authHandler.CurrentUserJSON)
	mux.HandleFunc("/api/v1/auth/logout", authHandler.LogoutJSON)
	mux.HandleFunc("/api/v1/auth/check-username", usernameHandler.CheckAvailabilityJSON)
	mux.HandleFunc("/api/v1/auth/check-email", authAvailabilityHandler.CheckEmailAvailabilityJSON)
	mux.HandleFunc("/api/v1/auth/check-phone", authAvailabilityHandler.CheckPhoneAvailabilityJSON)
	mux.HandleFunc("/api/v1/profile/me", profileHandler.ServeHTTP)
	mux.HandleFunc("/api/v1/profile/avatar", mediaHandler.ServeCurrentAvatarHTTP)
	mux.HandleFunc("/api/v1/profiles/", profileHandler.ServePublicProfileHTTP)
	mux.HandleFunc("/api/v1/media/", mediaHandler.ServeObjectHTTP)
	mux.HandleFunc("/api/v1/security/password", securityHandler.ServePasswordHTTP)
	mux.HandleFunc("/api/v1/security/contact", securityHandler.ServeContactHTTP)
	mux.HandleFunc("/api/v1/security/email", securityHandler.ServeEmailHTTP)
	mux.HandleFunc("/api/v1/security/phone", securityHandler.ServePhoneHTTP)
	mux.HandleFunc("/api/v1/security/account", securityHandler.ServeAccountHTTP)
	mux.HandleFunc("/api/v1/masters/search", masterSearchHandler.SearchJSON)
	mux.HandleFunc("/api/v1/masters/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(strings.Trim(r.URL.Path, "/"), "/publications") {
			publicationsHandler.ServeMasterPublicationsHTTP(w, r)
			return
		}
		if strings.HasSuffix(strings.Trim(r.URL.Path, "/"), "/availability") {
			appointmentsHandler.ServeAvailabilityHTTP(w, r)
			return
		}
		masterSearchHandler.PublicProfileJSON(w, r)
	})
	mux.HandleFunc("/api/v1/publications/", publicationsHandler.ServePublicationHTTP)
	mux.HandleFunc("/api/v1/masters/me/profile", masterServicesHandler.ServeSettingsHTTP)
	mux.HandleFunc("/api/v1/masters/me/schedule", masterServicesHandler.ServeScheduleHTTP)
	mux.HandleFunc("/api/v1/masters/me/services", masterServicesHandler.ServeCollectionHTTP)
	mux.HandleFunc("/api/v1/masters/me/services/", masterServicesHandler.ServeItemHTTP)
	mux.HandleFunc("/api/v1/favorites/masters", favoritesHandler.ServeMasterCollectionHTTP)
	mux.HandleFunc("/api/v1/favorites/masters/", favoritesHandler.ServeMasterItemHTTP)
	mux.HandleFunc("/api/v1/chats", chatHandler.ServeCollectionHTTP)
	mux.HandleFunc("/api/v1/chats/with/", chatHandler.ServeWithUserHTTP)
	mux.HandleFunc("/api/v1/chats/", chatHandler.ServeThreadHTTP)
	mux.HandleFunc("/api/v1/appointments", appointmentsHandler.ServeCollectionHTTP)
	mux.HandleFunc("/api/v1/appointments/me", appointmentsHandler.ServeClientHTTP)
	mux.HandleFunc("/api/v1/appointments/", func(w http.ResponseWriter, r *http.Request) {
		trimmedPath := strings.Trim(r.URL.Path, "/")
		if strings.HasSuffix(trimmedPath, "/journals") {
			journalHandler.ServeAppointmentListHTTP(w, r)
			return
		}
		if strings.HasSuffix(trimmedPath, "/journal") {
			journalHandler.ServeAppointmentHTTP(w, r)
			return
		}
		recommendationsHandler.ServeClientHTTP(w, r)
	})
	mux.HandleFunc("/api/v1/journals/me", journalHandler.ServeClientListHTTP)
	mux.HandleFunc("/api/v1/journals/", journalHandler.ServeJournalHTTP)
	mux.HandleFunc("/api/v1/master/journals", journalHandler.ServeMasterListHTTP)
	mux.HandleFunc("/api/v1/master/publications", publicationsHandler.ServeCurrentMasterCollectionHTTP)
	mux.HandleFunc("/api/v1/master/publications/", publicationsHandler.ServeCurrentMasterItemHTTP)
	mux.HandleFunc("/api/v1/master/appointments", appointmentsHandler.ServeMasterHTTP)
	mux.HandleFunc("/api/v1/master/appointments/", func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/recommendations") {
			recommendationsHandler.ServeMasterHTTP(w, r)
			return
		}
		appointmentsHandler.ServeMasterItemHTTP(w, r)
	})

	return requestLogger(withCORS(mux))
}

func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = os.Stdout.WriteString(r.Method + " " + r.URL.Path + "\n")
		next.ServeHTTP(w, r)
	})
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if isAllowedOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func isAllowedOrigin(origin string) bool {
	if origin == "" {
		return false
	}

	return strings.HasPrefix(origin, "http://localhost:") ||
		strings.HasPrefix(origin, "http://127.0.0.1:") ||
		strings.HasPrefix(origin, "https://localhost:") ||
		strings.HasPrefix(origin, "https://127.0.0.1:")
}
