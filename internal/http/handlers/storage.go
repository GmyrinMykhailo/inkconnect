package handlers

import (
	"context"
	"net/http"
	"time"

	"inkconnect/internal/platform/storage"
)

type StorageHealthChecker interface {
	Health(context.Context) storage.HealthStatus
}

type StorageHandler struct {
	checker StorageHealthChecker
}

func NewStorageHandler(checker StorageHealthChecker) *StorageHandler {
	return &StorageHandler{checker: checker}
}

func (h *StorageHandler) HealthJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	if h.checker == nil {
		writeJSON(w, storage.HealthStatus{Status: storage.HealthStatusDisabled})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	status := h.checker.Health(ctx)
	httpStatus := http.StatusOK
	if status.Status == storage.HealthStatusError {
		httpStatus = http.StatusServiceUnavailable
	}

	writeJSONStatus(w, httpStatus, status)
}
