package catalog

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
)

type ServiceRepository interface {
	GetMasterSettings(ctx context.Context, masterID string) (MasterSettings, error)
	UpdateMasterSettings(ctx context.Context, masterID string, input MasterSettingsInput) (MasterSettings, error)
	ListMasterServices(ctx context.Context, masterID string) ([]MasterService, error)
	HasAnyMasterServices(ctx context.Context, masterID string) (bool, error)
	CreateMasterService(ctx context.Context, masterID string, input ServiceInput) (MasterService, error)
	UpdateMasterService(ctx context.Context, masterID string, serviceID string, input ServiceInput) (MasterService, error)
	DeleteMasterService(ctx context.Context, masterID string, serviceID string) error
	GetMasterSchedule(ctx context.Context, masterID string) (MasterWorkSchedule, error)
	ReplaceMasterSchedule(ctx context.Context, masterID string, schedule MasterWorkSchedule) (MasterWorkSchedule, error)
}

type PostgresServiceRepository struct {
	db *sql.DB
}

func EnsureMasterServicesSchema(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(
		ctx,
		`ALTER TABLE services
		     ADD COLUMN IF NOT EXISTS service_type TEXT NOT NULL DEFAULT 'session';

		 ALTER TABLE services
		     ADD COLUMN IF NOT EXISTS use_auto_price BOOLEAN NOT NULL DEFAULT FALSE;

		 ALTER TABLE services
		     ADD COLUMN IF NOT EXISTS from_price BOOLEAN NOT NULL DEFAULT FALSE;

		 ALTER TABLE services
		     ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

		 ALTER TABLE services
		     DROP CONSTRAINT IF EXISTS services_service_type_chk;

		 ALTER TABLE services
		     ADD CONSTRAINT services_service_type_chk
		         CHECK (service_type IN ('session', 'consultation', 'sketch'));

		 DROP TRIGGER IF EXISTS trg_services_updated_at ON services;
		 CREATE TRIGGER trg_services_updated_at
		 BEFORE UPDATE ON services
		 FOR EACH ROW
		 EXECUTE FUNCTION set_updated_at();

		 ALTER TABLE master_profiles
		     ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'Тату-мастер';

		 ALTER TABLE master_profiles
		     ADD COLUMN IF NOT EXISTS min_session_price INTEGER NOT NULL DEFAULT 5000;

		 ALTER TABLE master_profiles
		     ADD COLUMN IF NOT EXISTS hourly_rate INTEGER NOT NULL DEFAULT 2500;

		 ALTER TABLE master_profiles
		     ADD COLUMN IF NOT EXISTS break_between_clients TEXT NOT NULL DEFAULT '30 минут';

		 CREATE TABLE IF NOT EXISTS master_styles (
		     master_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		     style TEXT NOT NULL,
		     created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		     PRIMARY KEY (master_id, style)
		 );

		 CREATE INDEX IF NOT EXISTS idx_master_styles_style ON master_styles(style);

		 CREATE TABLE IF NOT EXISTS master_work_schedule (
		     master_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		     day_of_week SMALLINT NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
		     is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
		     intervals JSONB NOT NULL DEFAULT '[]'::jsonb,
		     updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		     PRIMARY KEY (master_id, day_of_week)
		 );`,
	)
	if err != nil {
		return fmt.Errorf("ensure master services schema: %w", err)
	}

	return nil
}

func NewPostgresServiceRepository(db *sql.DB) *PostgresServiceRepository {
	return &PostgresServiceRepository{db: db}
}

func (r *PostgresServiceRepository) GetMasterSettings(ctx context.Context, masterID string) (MasterSettings, error) {
	settings, err := r.queryMasterSettings(ctx, masterID)
	if err != nil {
		return MasterSettings{}, err
	}

	styles, err := r.listMasterStyles(ctx, masterID)
	if err != nil {
		return MasterSettings{}, err
	}
	settings.Styles = styles

	return settings, nil
}

func (r *PostgresServiceRepository) UpdateMasterSettings(ctx context.Context, masterID string, input MasterSettingsInput) (MasterSettings, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return MasterSettings{}, fmt.Errorf("begin update master settings transaction: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	_, err = tx.ExecContext(
		ctx,
		`INSERT INTO master_profiles (
		     user_id,
		     category,
		     min_session_price,
		     hourly_rate,
		     break_between_clients
		 )
		 VALUES ($1, $2, $3, $4, $5)
		 ON CONFLICT (user_id) DO UPDATE
		 SET category = EXCLUDED.category,
		     min_session_price = EXCLUDED.min_session_price,
		     hourly_rate = EXCLUDED.hourly_rate,
		     break_between_clients = EXCLUDED.break_between_clients`,
		masterID,
		input.Category,
		input.MinSessionPrice,
		input.HourlyRate,
		input.BreakBetweenClients,
	)
	if err != nil {
		return MasterSettings{}, fmt.Errorf("update master profile settings: %w", err)
	}

	_, err = tx.ExecContext(ctx, `DELETE FROM master_styles WHERE master_id = $1`, masterID)
	if err != nil {
		return MasterSettings{}, fmt.Errorf("delete master styles: %w", err)
	}

	for _, style := range input.Styles {
		_, err = tx.ExecContext(
			ctx,
			`INSERT INTO master_styles (master_id, style)
			 VALUES ($1, $2)
			 ON CONFLICT (master_id, style) DO NOTHING`,
			masterID,
			style,
		)
		if err != nil {
			return MasterSettings{}, fmt.Errorf("insert master style: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return MasterSettings{}, fmt.Errorf("commit update master settings transaction: %w", err)
	}

	return r.GetMasterSettings(ctx, masterID)
}

func (r *PostgresServiceRepository) queryMasterSettings(ctx context.Context, masterID string) (MasterSettings, error) {
	var settings MasterSettings
	err := r.db.QueryRowContext(
		ctx,
		`SELECT COALESCE(category, 'Тату-мастер'),
		        COALESCE(min_session_price, 5000),
		        COALESCE(hourly_rate, 2500),
		        COALESCE(break_between_clients, '30 минут')
		 FROM master_profiles
		 WHERE user_id = $1`,
		masterID,
	).Scan(
		&settings.Category,
		&settings.MinSessionPrice,
		&settings.HourlyRate,
		&settings.BreakBetweenClients,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return DefaultMasterSettings(), nil
		}
		return MasterSettings{}, fmt.Errorf("get master settings: %w", err)
	}

	return settings, nil
}

func (r *PostgresServiceRepository) listMasterStyles(ctx context.Context, masterID string) ([]string, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT style
		 FROM master_styles
		 WHERE master_id = $1
		 ORDER BY created_at, style`,
		masterID,
	)
	if err != nil {
		return nil, fmt.Errorf("list master styles: %w", err)
	}
	defer rows.Close()

	styles := []string{}
	for rows.Next() {
		var style string
		if err := rows.Scan(&style); err != nil {
			return nil, fmt.Errorf("scan master style: %w", err)
		}
		styles = append(styles, style)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate master styles: %w", err)
	}

	return styles, nil
}

func (r *PostgresServiceRepository) ListMasterServices(ctx context.Context, masterID string) ([]MasterService, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id::text,
		        title,
		        COALESCE(description, ''),
		        COALESCE(service_type, 'session'),
		        duration_minutes,
		        COALESCE(price_min, 0)::INT,
		        COALESCE(use_auto_price, FALSE),
		        COALESCE(from_price, FALSE)
		 FROM services
		 WHERE master_id = $1
		   AND is_active = TRUE
		 ORDER BY created_at, id`,
		masterID,
	)
	if err != nil {
		return nil, fmt.Errorf("list master services: %w", err)
	}
	defer rows.Close()

	services := []MasterService{}
	for rows.Next() {
		service, err := scanMasterService(rows)
		if err != nil {
			return nil, err
		}
		services = append(services, service)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate master services: %w", err)
	}

	return services, nil
}

func (r *PostgresServiceRepository) HasAnyMasterServices(ctx context.Context, masterID string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM services
			WHERE master_id = $1
		)`,
		masterID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check master services exist: %w", err)
	}

	return exists, nil
}

func (r *PostgresServiceRepository) CreateMasterService(ctx context.Context, masterID string, input ServiceInput) (MasterService, error) {
	return r.queryService(
		ctx,
		`INSERT INTO services (
		     master_id,
		     kind,
		     title,
		     description,
		     category,
		     service_type,
		     price_min,
		     duration_minutes,
		     use_auto_price,
		     from_price
		 )
		 VALUES ($1, 'tattoo', $2, $3, $4, $4, $5, $6, $7, $8)
		 RETURNING id::text,
		           title,
		           COALESCE(description, ''),
		           COALESCE(service_type, 'session'),
		           duration_minutes,
		           COALESCE(price_min, 0)::INT,
		           COALESCE(use_auto_price, FALSE),
		           COALESCE(from_price, FALSE)`,
		masterID,
		input.Name,
		nullableString(input.Description),
		string(input.Type),
		input.Price,
		durationMinutes(input.DurationHours),
		input.UseAutoPrice,
		input.FromPrice,
	)
}

func (r *PostgresServiceRepository) UpdateMasterService(ctx context.Context, masterID string, serviceID string, input ServiceInput) (MasterService, error) {
	service, err := r.queryService(
		ctx,
		`UPDATE services
		 SET title = $3,
		     description = $4,
		     category = $5,
		     service_type = $5,
		     price_min = $6,
		     duration_minutes = $7,
		     use_auto_price = $8,
		     from_price = $9,
		     updated_at = NOW()
		 WHERE master_id = $1
		   AND id::text = $2
		   AND is_active = TRUE
		 RETURNING id::text,
		           title,
		           COALESCE(description, ''),
		           COALESCE(service_type, 'session'),
		           duration_minutes,
		           COALESCE(price_min, 0)::INT,
		           COALESCE(use_auto_price, FALSE),
		           COALESCE(from_price, FALSE)`,
		masterID,
		serviceID,
		input.Name,
		nullableString(input.Description),
		string(input.Type),
		input.Price,
		durationMinutes(input.DurationHours),
		input.UseAutoPrice,
		input.FromPrice,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return MasterService{}, ErrServiceNotFound
		}
		return MasterService{}, err
	}

	return service, nil
}

func (r *PostgresServiceRepository) DeleteMasterService(ctx context.Context, masterID string, serviceID string) error {
	result, err := r.db.ExecContext(
		ctx,
		`UPDATE services
		 SET is_active = FALSE,
		     updated_at = NOW()
		 WHERE master_id = $1
		   AND id::text = $2
		   AND is_active = TRUE`,
		masterID,
		serviceID,
	)
	if err != nil {
		return fmt.Errorf("delete master service: %w", err)
	}

	affected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("delete master service rows affected: %w", err)
	}
	if affected == 0 {
		return ErrServiceNotFound
	}

	return nil
}

func (r *PostgresServiceRepository) GetMasterSchedule(ctx context.Context, masterID string) (MasterWorkSchedule, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT day_of_week,
		        is_enabled,
		        intervals::text
		 FROM master_work_schedule
		 WHERE master_id = $1
		 ORDER BY day_of_week`,
		masterID,
	)
	if err != nil {
		return MasterWorkSchedule{}, fmt.Errorf("get master schedule: %w", err)
	}
	defer rows.Close()

	days := []WorkScheduleDay{}
	for rows.Next() {
		var day WorkScheduleDay
		var rawIntervals string
		if err := rows.Scan(&day.DayIndex, &day.Enabled, &rawIntervals); err != nil {
			return MasterWorkSchedule{}, fmt.Errorf("scan master schedule day: %w", err)
		}
		if err := json.Unmarshal([]byte(rawIntervals), &day.Intervals); err != nil {
			return MasterWorkSchedule{}, fmt.Errorf("decode master schedule intervals: %w", err)
		}
		if day.Intervals == nil {
			day.Intervals = []WorkScheduleInterval{}
		}
		days = append(days, day)
	}

	if err := rows.Err(); err != nil {
		return MasterWorkSchedule{}, fmt.Errorf("iterate master schedule: %w", err)
	}
	if len(days) == 0 {
		return DefaultMasterWorkSchedule(), nil
	}

	schedule, err := normalizeMasterWorkSchedule(MasterWorkSchedule{Days: days})
	if err != nil {
		return MasterWorkSchedule{}, fmt.Errorf("normalize stored master schedule: %w", err)
	}

	return schedule, nil
}

func (r *PostgresServiceRepository) ReplaceMasterSchedule(ctx context.Context, masterID string, schedule MasterWorkSchedule) (MasterWorkSchedule, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return MasterWorkSchedule{}, fmt.Errorf("begin replace master schedule transaction: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	_, err = tx.ExecContext(ctx, `DELETE FROM master_work_schedule WHERE master_id = $1`, masterID)
	if err != nil {
		return MasterWorkSchedule{}, fmt.Errorf("delete master schedule: %w", err)
	}

	for _, day := range schedule.Days {
		rawIntervals, err := json.Marshal(day.Intervals)
		if err != nil {
			return MasterWorkSchedule{}, fmt.Errorf("encode master schedule intervals: %w", err)
		}
		_, err = tx.ExecContext(
			ctx,
			`INSERT INTO master_work_schedule (
			     master_id,
			     day_of_week,
			     is_enabled,
			     intervals,
			     updated_at
			 )
			 VALUES ($1, $2, $3, $4::jsonb, NOW())`,
			masterID,
			day.DayIndex,
			day.Enabled,
			string(rawIntervals),
		)
		if err != nil {
			return MasterWorkSchedule{}, fmt.Errorf("insert master schedule day: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return MasterWorkSchedule{}, fmt.Errorf("commit replace master schedule transaction: %w", err)
	}

	return r.GetMasterSchedule(ctx, masterID)
}

func (r *PostgresServiceRepository) queryService(ctx context.Context, query string, args ...any) (MasterService, error) {
	row := r.db.QueryRowContext(ctx, query, args...)
	service, err := scanMasterService(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return MasterService{}, err
		}
		return MasterService{}, fmt.Errorf("query master service: %w", err)
	}

	return service, nil
}

type serviceScanner interface {
	Scan(dest ...any) error
}

func scanMasterService(scanner serviceScanner) (MasterService, error) {
	var service MasterService
	var duration sql.NullInt64
	if err := scanner.Scan(
		&service.ID,
		&service.Name,
		&service.Description,
		&service.Type,
		&duration,
		&service.Price,
		&service.UseAutoPrice,
		&service.FromPrice,
	); err != nil {
		return MasterService{}, fmt.Errorf("scan master service: %w", err)
	}

	if duration.Valid {
		hours := float64(duration.Int64) / 60
		service.DurationHours = &hours
	}

	return service, nil
}

func nullableString(value string) any {
	if value == "" {
		return nil
	}
	return value
}

func durationMinutes(hours *float64) any {
	if hours == nil {
		return nil
	}

	minutes := int(math.Round(*hours * 60))
	if minutes <= 0 {
		return nil
	}

	return minutes
}
