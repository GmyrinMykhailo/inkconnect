package appointments

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrAppointmentNotFound = errors.New("appointment not found")
	ErrMasterNotFound      = errors.New("master not found")
	ErrServiceNotFound     = errors.New("service not found")
	ErrSlotUnavailable     = errors.New("slot unavailable")
	ErrInvalidStatus       = errors.New("invalid appointment status")
	ErrInvalidDuration     = errors.New("invalid appointment duration")
)

type Repository interface {
	FindMasterIDByUsername(ctx context.Context, username string) (string, error)
	FindServiceForMaster(ctx context.Context, masterID string, serviceID string) (ServiceSummary, error)
	CreateAppointment(ctx context.Context, input CreateAppointmentInput, masterID string) (string, error)
	FindAppointmentByID(ctx context.Context, appointmentID string) (AppointmentView, error)
	ListClientAppointments(ctx context.Context, clientID string) ([]AppointmentView, error)
	ListMasterAppointments(ctx context.Context, masterID string) ([]AppointmentView, error)
	UpdateMasterAppointmentStatus(ctx context.Context, masterID string, appointmentID string, status string) (AppointmentView, error)
	UpdateMasterAppointmentDuration(ctx context.Context, masterID string, appointmentID string, durationMinutes int) (AppointmentView, error)
	WorkIntervalsForDay(ctx context.Context, masterID string, dayIndex int) ([]scheduleInterval, bool, error)
	BusyWindowsForDate(ctx context.Context, masterID string, date time.Time) ([]busyWindow, error)
	HasOverlapExcluding(ctx context.Context, masterID string, start time.Time, end time.Time, appointmentID string) (bool, error)
}

type PostgresRepository struct {
	db *sql.DB
}

func NewPostgresRepository(db *sql.DB) *PostgresRepository {
	return &PostgresRepository{db: db}
}

func EnsureAppointmentsSchema(ctx context.Context, db *sql.DB) error {
	if _, err := db.ExecContext(
		ctx,
		`ALTER TABLE appointments
		 ADD COLUMN IF NOT EXISTS duration_minutes INTEGER`,
	); err != nil {
		return fmt.Errorf("ensure appointments duration column: %w", err)
	}

	if _, err := db.ExecContext(
		ctx,
		`ALTER TABLE appointments
		 DROP CONSTRAINT IF EXISTS appointments_duration_minutes_chk`,
	); err != nil {
		return fmt.Errorf("drop appointments duration constraint: %w", err)
	}

	if _, err := db.ExecContext(
		ctx,
		`ALTER TABLE appointments
		 ADD CONSTRAINT appointments_duration_minutes_chk
		 CHECK (duration_minutes IS NULL OR duration_minutes > 0)`,
	); err != nil {
		return fmt.Errorf("ensure appointments duration constraint: %w", err)
	}

	return nil
}

func (r *PostgresRepository) FindMasterIDByUsername(ctx context.Context, username string) (string, error) {
	var id string
	err := r.db.QueryRowContext(
		ctx,
		`SELECT id
		 FROM users
		 WHERE lower(username::text) = lower($1)
		   AND role = 'master'
		   AND is_active = TRUE`,
		username,
	).Scan(&id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", ErrMasterNotFound
		}
		return "", fmt.Errorf("find master by username: %w", err)
	}
	return id, nil
}

func (r *PostgresRepository) FindServiceForMaster(ctx context.Context, masterID string, serviceID string) (ServiceSummary, error) {
	var service ServiceSummary
	var durationMinutes sql.NullInt64
	err := r.db.QueryRowContext(
		ctx,
		`SELECT id,
		        title,
		        COALESCE(description, ''),
		        service_type,
		        COALESCE(category, ''),
		        COALESCE(style, ''),
		        duration_minutes,
		        COALESCE(price_min, 0)::int,
		        use_auto_price,
		        from_price
		 FROM services
		 WHERE id = $1
		   AND master_id = $2
		   AND is_active = TRUE`,
		serviceID,
		masterID,
	).Scan(
		&service.ID,
		&service.Name,
		&service.Description,
		&service.Type,
		&service.Category,
		&service.Style,
		&durationMinutes,
		&service.Price,
		&service.UseAutoPrice,
		&service.FromPrice,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ServiceSummary{}, ErrServiceNotFound
		}
		return ServiceSummary{}, fmt.Errorf("find service for master: %w", err)
	}
	if durationMinutes.Valid {
		hours := float64(durationMinutes.Int64) / 60
		service.DurationHours = &hours
	}
	return service, nil
}

func (r *PostgresRepository) CreateAppointment(ctx context.Context, input CreateAppointmentInput, masterID string) (string, error) {
	var id string
	err := r.db.QueryRowContext(
		ctx,
		`INSERT INTO appointments (client_id, master_id, service_id, scheduled_at, duration_minutes, client_note)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 RETURNING id`,
		input.ClientID,
		masterID,
		input.ServiceID,
		input.ScheduledAt,
		input.DurationMinutes,
		input.ClientNote,
	).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("create appointment: %w", err)
	}
	return id, nil
}

func (r *PostgresRepository) FindAppointmentByID(ctx context.Context, appointmentID string) (AppointmentView, error) {
	rows, err := r.db.QueryContext(ctx, appointmentSelectSQL()+` WHERE a.id = $1`, appointmentID)
	if err != nil {
		return AppointmentView{}, fmt.Errorf("find appointment by id: %w", err)
	}
	defer rows.Close()

	if rows.Next() {
		appointment, err := scanAppointment(rows)
		if err != nil {
			return AppointmentView{}, err
		}
		return appointment, nil
	}
	if err := rows.Err(); err != nil {
		return AppointmentView{}, fmt.Errorf("iterate appointment by id: %w", err)
	}
	return AppointmentView{}, ErrAppointmentNotFound
}

func (r *PostgresRepository) ListClientAppointments(ctx context.Context, clientID string) ([]AppointmentView, error) {
	rows, err := r.db.QueryContext(
		ctx,
		appointmentSelectSQL()+` WHERE a.client_id = $1 ORDER BY a.scheduled_at DESC, a.created_at DESC`,
		clientID,
	)
	if err != nil {
		return nil, fmt.Errorf("list client appointments: %w", err)
	}
	defer rows.Close()
	return scanAppointments(rows)
}

func (r *PostgresRepository) ListMasterAppointments(ctx context.Context, masterID string) ([]AppointmentView, error) {
	rows, err := r.db.QueryContext(
		ctx,
		appointmentSelectSQL()+` WHERE a.master_id = $1 ORDER BY a.scheduled_at ASC, a.created_at DESC`,
		masterID,
	)
	if err != nil {
		return nil, fmt.Errorf("list master appointments: %w", err)
	}
	defer rows.Close()
	return scanAppointments(rows)
}

func (r *PostgresRepository) UpdateMasterAppointmentStatus(ctx context.Context, masterID string, appointmentID string, status string) (AppointmentView, error) {
	result, err := r.db.ExecContext(
		ctx,
		`UPDATE appointments
		 SET status = $3::appointment_status,
		     updated_at = NOW()
		 WHERE id = $1
		   AND master_id = $2`,
		appointmentID,
		masterID,
		status,
	)
	if err != nil {
		return AppointmentView{}, fmt.Errorf("update appointment status: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return AppointmentView{}, fmt.Errorf("read appointment status rows affected: %w", err)
	}
	if affected == 0 {
		return AppointmentView{}, ErrAppointmentNotFound
	}
	return r.FindAppointmentByID(ctx, appointmentID)
}

func (r *PostgresRepository) UpdateMasterAppointmentDuration(ctx context.Context, masterID string, appointmentID string, durationMinutes int) (AppointmentView, error) {
	result, err := r.db.ExecContext(
		ctx,
		`UPDATE appointments
		 SET duration_minutes = $3,
		     updated_at = NOW()
		 WHERE id = $1
		   AND master_id = $2`,
		appointmentID,
		masterID,
		durationMinutes,
	)
	if err != nil {
		return AppointmentView{}, fmt.Errorf("update appointment duration: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return AppointmentView{}, fmt.Errorf("read appointment duration rows affected: %w", err)
	}
	if affected == 0 {
		return AppointmentView{}, ErrAppointmentNotFound
	}
	return r.FindAppointmentByID(ctx, appointmentID)
}

func (r *PostgresRepository) WorkIntervalsForDay(ctx context.Context, masterID string, dayIndex int) ([]scheduleInterval, bool, error) {
	var enabled bool
	var raw []byte
	err := r.db.QueryRowContext(
		ctx,
		`SELECT is_enabled, intervals
		 FROM master_work_schedule
		 WHERE master_id = $1 AND day_of_week = $2`,
		masterID,
		dayIndex,
	).Scan(&enabled, &raw)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return defaultScheduleIntervals(dayIndex)
		}
		return nil, false, fmt.Errorf("load work schedule: %w", err)
	}
	if !enabled {
		return nil, false, nil
	}

	var intervals []scheduleInterval
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &intervals); err != nil {
			return nil, false, fmt.Errorf("parse work schedule intervals: %w", err)
		}
	}
	return intervals, true, nil
}

func defaultScheduleIntervals(dayIndex int) ([]scheduleInterval, bool, error) {
	if dayIndex < 0 || dayIndex > 5 {
		return nil, false, nil
	}
	return []scheduleInterval{
		{Type: "work", StartMinute: 9 * 60, EndMinute: 13 * 60},
		{Type: "break", StartMinute: 13 * 60, EndMinute: 14 * 60},
		{Type: "work", StartMinute: 14 * 60, EndMinute: 16 * 60},
		{Type: "work", StartMinute: 18 * 60, EndMinute: 20 * 60},
	}, true, nil
}

func (r *PostgresRepository) BusyWindowsForDate(ctx context.Context, masterID string, date time.Time) ([]busyWindow, error) {
	loc := time.FixedZone("MSK", 3*60*60)
	startLocal := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, loc)
	start := startLocal.UTC()
	end := startLocal.AddDate(0, 0, 1).UTC()
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT EXTRACT(HOUR FROM a.scheduled_at AT TIME ZONE 'Europe/Moscow')::int * 60
		        + EXTRACT(MINUTE FROM a.scheduled_at AT TIME ZONE 'Europe/Moscow')::int,
		        COALESCE(a.duration_minutes, s.duration_minutes, 60)
		 FROM appointments a
		 JOIN services s ON s.id = a.service_id
		 WHERE a.master_id = $1
		   AND a.status IN ('pending', 'confirmed')
		   AND a.scheduled_at >= $2
		   AND a.scheduled_at < $3`,
		masterID,
		start,
		end,
	)
	if err != nil {
		return nil, fmt.Errorf("load busy windows: %w", err)
	}
	defer rows.Close()

	var windows []busyWindow
	for rows.Next() {
		var window busyWindow
		if err := rows.Scan(&window.StartMinute, &window.DurationMinutes); err != nil {
			return nil, fmt.Errorf("scan busy window: %w", err)
		}
		windows = append(windows, window)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate busy windows: %w", err)
	}
	return windows, nil
}

func (r *PostgresRepository) HasOverlapExcluding(ctx context.Context, masterID string, start time.Time, end time.Time, appointmentID string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM appointments a
			JOIN services s ON s.id = a.service_id
			WHERE a.master_id = $1
			  AND a.id <> $4
			  AND a.status IN ('pending', 'confirmed')
			  AND a.scheduled_at < $3
			  AND a.scheduled_at + make_interval(mins => COALESCE(a.duration_minutes, s.duration_minutes, 60)) > $2
		)`,
		masterID,
		start,
		end,
		appointmentID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check appointment overlap: %w", err)
	}
	return exists, nil
}

func appointmentSelectSQL() string {
	return `SELECT a.id,
	              a.status::text,
	              a.scheduled_at,
	              COALESCE(a.client_note, ''),
	              COALESCE(a.master_note, ''),
	              a.created_at,
	              cu.id,
	              cu.username,
	              cu.role::text,
	              CASE WHEN cu.role::text = 'master' OR cmp.user_id IS NOT NULL THEN TRUE ELSE FALSE END,
	              CASE WHEN cu.show_full_name_in_profile THEN NULLIF(trim(CONCAT_WS(' ', cu.last_name, cu.first_name, cu.middle_name)), '') ELSE NULL END,
	              CASE WHEN cu.show_city_in_profile THEN COALESCE(cu.city, '') ELSE '' END,
	              COALESCE('/api/v1/media/' || cam.id::text, COALESCE(cu.avatar_url, '')),
	              mu.id,
	              mu.username,
	              mu.role::text,
	              CASE WHEN mu.role::text = 'master' OR mp.user_id IS NOT NULL THEN TRUE ELSE FALSE END,
	              CASE WHEN NULLIF(trim(COALESCE(mp.studio_name, '')), '') IS NOT NULL THEN trim(mp.studio_name)
	                   WHEN mu.show_full_name_in_profile THEN NULLIF(trim(CONCAT_WS(' ', mu.last_name, mu.first_name, mu.middle_name)), '')
	                   ELSE NULL
	              END,
	              CASE WHEN mu.show_city_in_profile THEN COALESCE(mu.city, '') ELSE '' END,
	              COALESCE('/api/v1/media/' || mam.id::text, COALESCE(mu.avatar_url, '')),
	              s.id,
	              s.title,
	              COALESCE(s.description, ''),
	              s.service_type,
	              COALESCE(s.category, ''),
	              COALESCE(s.style, ''),
	              COALESCE(a.duration_minutes, s.duration_minutes),
	              COALESCE(s.price_min, 0)::int,
	              s.use_auto_price,
	              s.from_price,
	              COALESCE((
	                SELECT cr.status
	                FROM care_recommendations cr
	                WHERE cr.appointment_id = a.id
	                ORDER BY CASE cr.status
	                  WHEN 'approved' THEN 3
	                  WHEN 'sent' THEN 2
	                  WHEN 'draft' THEN 1
	                  ELSE 0
	                END DESC, cr.created_at DESC
	                LIMIT 1
	              ), ''),
	              COALESCE((
	                SELECT COUNT(*)
	                FROM care_recommendations cr
	                WHERE cr.appointment_id = a.id
	              ), 0)::int,
	              COALESCE(cj.id::text, ''),
	              CASE WHEN EXISTS (
	                SELECT 1
	                FROM care_journal_steps cjs
	                WHERE cjs.journal_id = cj.id
	              ) THEN COALESCE((
	                SELECT COUNT(*)
	                FROM care_journal_steps cjs
	                WHERE cjs.journal_id = cj.id
	                  AND cjs.status = 'completed_by_client'
	              ), 0)::int ELSE COALESCE((
	                SELECT COUNT(DISTINCT e.recommendation_id)
	                FROM care_journal_entries e
	                WHERE e.journal_id = cj.id
	                  AND e.entry_type = 'client_confirmation'
	              ), 0)::int END,
	              CASE WHEN EXISTS (
	                SELECT 1
	                FROM care_journal_steps cjs
	                WHERE cjs.journal_id = cj.id
	              ) THEN COALESCE((
	                SELECT COUNT(*)
	                FROM care_journal_steps cjs
	                WHERE cjs.journal_id = cj.id
	              ), 0)::int ELSE COALESCE((
	                SELECT COUNT(*)
	                FROM care_recommendations cr
	                WHERE cr.journal_id = cj.id
	              ), 0)::int END
	       FROM appointments a
	       JOIN users cu ON cu.id = a.client_id
	       JOIN users mu ON mu.id = a.master_id
	       LEFT JOIN master_profiles cmp ON cmp.user_id = cu.id
	       LEFT JOIN master_profiles mp ON mp.user_id = mu.id
	       LEFT JOIN media_objects cam
	         ON cam.id = cu.avatar_media_id
	        AND cam.kind = 'user_avatar'
	        AND cam.deleted_at IS NULL
	       LEFT JOIN media_objects mam
	         ON mam.id = mu.avatar_media_id
	        AND mam.kind = 'user_avatar'
	        AND mam.deleted_at IS NULL
	       LEFT JOIN LATERAL (
	         SELECT cj.*
	         FROM care_journals cj
	         WHERE cj.appointment_id = a.id
	         ORDER BY CASE cj.status
	           WHEN 'active' THEN 0
	           WHEN 'draft' THEN 1
	           WHEN 'awaiting_client_confirmation' THEN 2
	           WHEN 'stopped' THEN 3
	           WHEN 'replaced' THEN 4
	           WHEN 'completed' THEN 5
	           ELSE 6
	         END,
	         cj.version_number DESC,
	         cj.created_at DESC,
	         cj.id DESC
	         LIMIT 1
	       ) cj ON TRUE
	       JOIN services s ON s.id = a.service_id`
}

func scanAppointments(rows *sql.Rows) ([]AppointmentView, error) {
	appointments := []AppointmentView{}
	for rows.Next() {
		appointment, err := scanAppointment(rows)
		if err != nil {
			return nil, err
		}
		appointments = append(appointments, appointment)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate appointments: %w", err)
	}
	return appointments, nil
}

func scanAppointment(rows *sql.Rows) (AppointmentView, error) {
	var appointment AppointmentView
	var clientName sql.NullString
	var masterName sql.NullString
	var durationMinutes sql.NullInt64
	if err := rows.Scan(
		&appointment.ID,
		&appointment.Status,
		&appointment.ScheduledAt,
		&appointment.ClientNote,
		&appointment.MasterNote,
		&appointment.CreatedAt,
		&appointment.Client.ID,
		&appointment.Client.Username,
		&appointment.Client.AccountRole,
		&appointment.Client.IsMaster,
		&clientName,
		&appointment.Client.City,
		&appointment.Client.AvatarURL,
		&appointment.Master.ID,
		&appointment.Master.Username,
		&appointment.Master.AccountRole,
		&appointment.Master.IsMaster,
		&masterName,
		&appointment.Master.City,
		&appointment.Master.AvatarURL,
		&appointment.Service.ID,
		&appointment.Service.Name,
		&appointment.Service.Description,
		&appointment.Service.Type,
		&appointment.Service.Category,
		&appointment.Service.Style,
		&durationMinutes,
		&appointment.Service.Price,
		&appointment.Service.UseAutoPrice,
		&appointment.Service.FromPrice,
		&appointment.RecommendationStatus,
		&appointment.RecommendationStepsCount,
		&appointment.JournalID,
		&appointment.JournalStepsDone,
		&appointment.JournalStepsTotal,
	); err != nil {
		return AppointmentView{}, fmt.Errorf("scan appointment: %w", err)
	}
	appointment.Client.DisplayName = publicDisplayName(appointment.Client.Username, clientName.String)
	appointment.Master.DisplayName = publicDisplayName(appointment.Master.Username, masterName.String)
	if durationMinutes.Valid {
		appointment.DurationMinutes = int(durationMinutes.Int64)
		hours := float64(durationMinutes.Int64) / 60
		appointment.Service.DurationHours = &hours
		end := appointment.ScheduledAt.Add(time.Duration(durationMinutes.Int64) * time.Minute)
		appointment.ScheduledEndAt = &end
	}
	return appointment, nil
}

func publicDisplayName(username string, displayName string) string {
	if strings.TrimSpace(displayName) != "" {
		return strings.TrimSpace(displayName)
	}
	username = strings.TrimSpace(username)
	if username == "" {
		return "@user"
	}
	if strings.HasPrefix(username, "@") {
		return username
	}
	return "@" + username
}
