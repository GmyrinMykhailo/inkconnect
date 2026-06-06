package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"net/http"
	"time"

	"inkconnect/internal/config"
	"inkconnect/internal/users"
)

type RegistrationHandler struct {
	templates *template.Template
	service   *users.RegistrationService
}

type registerViewData struct {
	Title      string
	Error      string
	Success    *users.RegistrationResult
	FormValues map[string]string
	Accepted   bool
}

func NewRegistrationHandler(cfg config.Config, service *users.RegistrationService) (*RegistrationHandler, error) {
	tmpl, err := template.ParseFiles(
		cfg.TemplatesDir+"/register.html",
		cfg.TemplatesDir+"/register_success.html",
	)
	if err != nil {
		return nil, fmt.Errorf("parse registration templates: %w", err)
	}

	return &RegistrationHandler{
		templates: tmpl,
		service:   service,
	}, nil
}

func (h *RegistrationHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.renderForm(w, registerViewData{
			Title:      "Регистрация в InkConnect",
			FormValues: map[string]string{},
		})
	case http.MethodPost:
		h.handleFormSubmit(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (h *RegistrationHandler) RegisterJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var payload struct {
		Username          string `json:"username"`
		Email             string `json:"email"`
		Password          string `json:"password"`
		PasswordConfirm   string `json:"password_confirm"`
		Role              string `json:"role"`
		LastName          string `json:"last_name"`
		FirstName         string `json:"first_name"`
		MiddleName        string `json:"middle_name"`
		Phone             string `json:"phone"`
		City              string `json:"city"`
		ShowCityInProfile bool   `json:"show_city_in_profile"`
		Bio               string `json:"bio"`
		StudioName        string `json:"studio_name"`
		AgreementAccepted bool   `json:"agreement_accepted"`
	}

	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, "invalid json payload", http.StatusBadRequest)
		return
	}

	result, err := h.register(r.Context(), users.RegistrationInput{
		Username:          payload.Username,
		Email:             payload.Email,
		Password:          payload.Password,
		PasswordConfirm:   payload.PasswordConfirm,
		Role:              users.Role(payload.Role),
		LastName:          payload.LastName,
		FirstName:         payload.FirstName,
		MiddleName:        payload.MiddleName,
		Phone:             payload.Phone,
		City:              payload.City,
		ShowCityInProfile: payload.ShowCityInProfile,
		Bio:               payload.Bio,
		StudioName:        payload.StudioName,
		AgreementAccepted: payload.AgreementAccepted,
	})
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(result)
}

func (h *RegistrationHandler) handleFormSubmit(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}

	input := users.RegistrationInput{
		Username:          r.FormValue("username"),
		Email:             r.FormValue("email"),
		Password:          r.FormValue("password"),
		PasswordConfirm:   r.FormValue("password_confirm"),
		Role:              users.Role(r.FormValue("role")),
		LastName:          r.FormValue("last_name"),
		FirstName:         r.FormValue("first_name"),
		MiddleName:        r.FormValue("middle_name"),
		Phone:             r.FormValue("phone"),
		City:              r.FormValue("city"),
		ShowCityInProfile: r.FormValue("show_city_in_profile") == "on",
		Bio:               r.FormValue("bio"),
		StudioName:        r.FormValue("studio_name"),
		AgreementAccepted: r.FormValue("agreement_accepted") == "on",
	}

	result, err := h.register(r.Context(), input)
	if err != nil {
		h.renderForm(w, registerViewData{
			Title:    "Регистрация в InkConnect",
			Error:    humanizeRegistrationError(err),
			Accepted: input.AgreementAccepted,
			FormValues: map[string]string{
				"username":             input.Username,
				"email":                input.Email,
				"role":                 string(input.Role),
				"last_name":            input.LastName,
				"first_name":           input.FirstName,
				"middle_name":          input.MiddleName,
				"phone":                input.Phone,
				"city":                 input.City,
				"show_city_in_profile": map[bool]string{true: "on", false: ""}[input.ShowCityInProfile],
				"bio":                  input.Bio,
				"studio_name":          input.StudioName,
			},
		})
		return
	}

	h.renderSuccess(w, registerViewData{
		Title:   "Регистрация завершена",
		Success: &result,
	})
}

func (h *RegistrationHandler) register(ctx context.Context, input users.RegistrationInput) (users.RegistrationResult, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return h.service.Register(ctx, input)
}

func (h *RegistrationHandler) renderForm(w http.ResponseWriter, data registerViewData) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.templates.ExecuteTemplate(w, "register.html", data); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func (h *RegistrationHandler) renderSuccess(w http.ResponseWriter, data registerViewData) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.templates.ExecuteTemplate(w, "register_success.html", data); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func humanizeRegistrationError(err error) string {
	switch {
	case errors.Is(err, users.ErrAgreementRequired):
		return "Нужно принять пользовательское соглашение и согласие на обработку персональных данных."
	case errors.Is(err, users.ErrInvalidRole):
		return "Выберите роль клиента или мастера."
	case errors.Is(err, users.ErrWeakPassword):
		return "Пароль должен содержать минимум 10 символов, буквы, цифры и спецсимвол, без пробелов в начале и конце."
	case errors.Is(err, users.ErrPasswordConfirmWeak):
		return "Подтверждение пароля должно содержать минимум 10 символов, буквы, цифры и спецсимвол, без пробелов в начале и конце."
	case errors.Is(err, users.ErrPasswordMismatch):
		return "Пароль и подтверждение пароля должны совпадать."
	case errors.Is(err, users.ErrUsernameRequired):
		return "Укажите публичный ник."
	case errors.Is(err, users.ErrInvalidUsername):
		return "Ник может содержать только латинские буквы, цифры и символы . _ -"
	case errors.Is(err, users.ErrEmailRequired):
		return "Укажите email."
	case errors.Is(err, users.ErrInvalidEmail):
		return "Введите корректный email в латинице."
	case errors.Is(err, users.ErrLastNameRequired):
		return "Укажите фамилию."
	case errors.Is(err, users.ErrFirstNameRequired):
		return "Укажите имя."
	case errors.Is(err, users.ErrInvalidName):
		return "В полях фамилии, имени и отчества допустимы только русские или английские буквы, пробел и дефис."
	case errors.Is(err, users.ErrNameScriptMismatch):
		return "Все поля ФИО должны быть заполнены в одной раскладке: только кириллица или только латиница."
	case errors.Is(err, users.ErrPhoneRequired):
		return "Укажите телефон."
	case errors.Is(err, users.ErrInvalidPhone):
		return "Телефон должен содержать 10 цифр после +7."
	case errors.Is(err, users.ErrCityRequired):
		return "Укажите город."
	case errors.Is(err, users.ErrInvalidCity):
		return "В поле города допустимы только русские буквы, пробел, запятая и дефис."
	case errors.Is(err, users.ErrBioTooLong):
		return "Краткая информация не должна превышать 150 символов."
	case errors.Is(err, users.ErrFieldTooLong):
		return "Ник, ФИО, город и пароли не должны превышать 128 символов."
	case errors.Is(err, users.ErrUsernameAlreadyExists):
		return "Пользователь с таким ником уже существует."
	case errors.Is(err, users.ErrEmailAlreadyExists):
		return "Пользователь с таким email уже зарегистрирован."
	case errors.Is(err, users.ErrPhoneAlreadyExists):
		return "Пользователь с таким телефоном уже зарегистрирован."
	default:
		return "Не удалось завершить регистрацию. Проверьте данные и попробуйте снова."
	}
}
