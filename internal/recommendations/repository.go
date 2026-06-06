package recommendations

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

type Repository interface {
	FindAppointmentAccess(ctx context.Context, appointmentID string) (AppointmentAccess, error)
	FindPlan(ctx context.Context, appointmentID string) (Plan, error)
	ReplaceDraft(ctx context.Context, appointmentID string, masterID string, steps []Step) (Plan, error)
	MarkSent(ctx context.Context, appointmentID string) (Plan, error)
	MarkApproved(ctx context.Context, appointmentID string) (Plan, error)
}

type PostgresRepository struct {
	db *sql.DB
}

func NewPostgresRepository(db *sql.DB) *PostgresRepository {
	return &PostgresRepository{db: db}
}

func EnsureRecommendationsSchema(ctx context.Context, db *sql.DB) error {
	statements := []string{
		`ALTER TABLE care_recommendations
		 ADD COLUMN IF NOT EXISTS appointment_id UUID REFERENCES appointments(id) ON DELETE CASCADE`,
		`UPDATE care_recommendations cr
		 SET appointment_id = cj.appointment_id
		 FROM care_journals cj
		 WHERE cr.journal_id = cj.id
		   AND cr.appointment_id IS NULL`,
		`ALTER TABLE care_recommendations
		 ALTER COLUMN journal_id DROP NOT NULL`,
		`ALTER TABLE care_recommendations
		 ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'draft'`,
		`ALTER TABLE care_recommendations
		 ADD COLUMN IF NOT EXISTS due_offset_days INTEGER`,
		`ALTER TABLE care_recommendations
		 ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ`,
		`ALTER TABLE care_recommendations
		 ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ`,
		`ALTER TABLE care_recommendations
		 DROP CONSTRAINT IF EXISTS care_recommendations_status_chk`,
		`ALTER TABLE care_recommendations
		 ADD CONSTRAINT care_recommendations_status_chk
		 CHECK (status IN ('draft', 'sent', 'approved'))`,
		`ALTER TABLE care_recommendations
		 DROP CONSTRAINT IF EXISTS care_recommendations_due_offset_days_chk`,
		`ALTER TABLE care_recommendations
		 ADD CONSTRAINT care_recommendations_due_offset_days_chk
		 CHECK (due_offset_days IS NULL OR due_offset_days >= 0)`,
		`ALTER TABLE care_recommendations
		 DROP CONSTRAINT IF EXISTS care_recommendations_journal_id_step_number_key`,
		`ALTER TABLE care_recommendations
		 DROP CONSTRAINT IF EXISTS care_recommendations_appointment_step_key`,
		`ALTER TABLE care_recommendations
		 ADD CONSTRAINT care_recommendations_appointment_step_key
		 UNIQUE (appointment_id, step_number)`,
		`CREATE INDEX IF NOT EXISTS idx_care_recommendations_appointment_id
		 ON care_recommendations(appointment_id)`,
		`CREATE INDEX IF NOT EXISTS idx_care_recommendations_status
		 ON care_recommendations(status)`,
	}

	for _, statement := range statements {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("ensure recommendations schema: %w", err)
		}
	}

	if _, err := db.ExecContext(
		ctx,
		`DO $$
		 BEGIN
		   IF NOT EXISTS (
		     SELECT 1 FROM care_recommendations WHERE appointment_id IS NULL
		   ) THEN
		     ALTER TABLE care_recommendations
		       ALTER COLUMN appointment_id SET NOT NULL;
		   END IF;
		 END $$`,
	); err != nil {
		return fmt.Errorf("ensure recommendations appointment not null: %w", err)
	}

	return nil
}

func (r *PostgresRepository) FindAppointmentAccess(ctx context.Context, appointmentID string) (AppointmentAccess, error) {
	var access AppointmentAccess
	err := r.db.QueryRowContext(
		ctx,
		`SELECT id, client_id, master_id, status::text
		 FROM appointments
		 WHERE id = $1`,
		appointmentID,
	).Scan(&access.ID, &access.ClientID, &access.MasterID, &access.Status)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return AppointmentAccess{}, ErrAppointmentNotFound
		}
		return AppointmentAccess{}, fmt.Errorf("find appointment access: %w", err)
	}
	return access, nil
}

func (r *PostgresRepository) FindPlan(ctx context.Context, appointmentID string) (Plan, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id,
		        COALESCE(journal_id::text, ''),
		        status,
		        step_number,
		        title,
		        description,
		        due_offset_days,
		        due_at,
		        created_by::text,
		        created_at,
		        sent_at,
		        approved_at
		 FROM care_recommendations
		 WHERE appointment_id = $1
		 ORDER BY step_number ASC`,
		appointmentID,
	)
	if err != nil {
		return Plan{}, fmt.Errorf("find recommendations: %w", err)
	}
	defer rows.Close()

	return scanPlan(rows, appointmentID)
}

func (r *PostgresRepository) ReplaceDraft(ctx context.Context, appointmentID string, masterID string, steps []Step) (Plan, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return Plan{}, fmt.Errorf("begin replace recommendations: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	if _, err = tx.ExecContext(ctx, `DELETE FROM care_recommendations WHERE appointment_id = $1`, appointmentID); err != nil {
		return Plan{}, fmt.Errorf("delete previous recommendations: %w", err)
	}

	for _, step := range steps {
		var dueOffset any
		if step.DueOffsetDays != nil {
			dueOffset = *step.DueOffsetDays
		}
		var dueAt any
		if step.DueAt != nil {
			dueAt = *step.DueAt
		}
		if _, err = tx.ExecContext(
			ctx,
			`INSERT INTO care_recommendations (
			   appointment_id, status, step_number, title, description,
			   due_offset_days, due_at, created_by
			 )
			 VALUES ($1, 'draft', $2, $3, $4, $5, $6, $7)`,
			appointmentID,
			step.StepNumber,
			step.Title,
			step.Description,
			dueOffset,
			dueAt,
			masterID,
		); err != nil {
			return Plan{}, fmt.Errorf("insert recommendation step: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return Plan{}, fmt.Errorf("commit replace recommendations: %w", err)
	}

	return r.FindPlan(ctx, appointmentID)
}

func (r *PostgresRepository) MarkSent(ctx context.Context, appointmentID string) (Plan, error) {
	result, err := r.db.ExecContext(
		ctx,
		`UPDATE care_recommendations
		 SET status = CASE WHEN status = 'approved' THEN status ELSE 'sent' END,
		     sent_at = CASE WHEN status = 'approved' THEN sent_at ELSE COALESCE(sent_at, NOW()) END
		 WHERE appointment_id = $1`,
		appointmentID,
	)
	if err != nil {
		return Plan{}, fmt.Errorf("send recommendations: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return Plan{}, fmt.Errorf("read sent recommendations rows: %w", err)
	}
	if affected == 0 {
		return Plan{}, ErrRecommendationsNone
	}
	return r.FindPlan(ctx, appointmentID)
}

func (r *PostgresRepository) MarkApproved(ctx context.Context, appointmentID string) (Plan, error) {
	result, err := r.db.ExecContext(
		ctx,
		`UPDATE care_recommendations
		 SET status = 'approved',
		     approved_at = COALESCE(approved_at, NOW())
		 WHERE appointment_id = $1
		   AND status IN ('sent', 'approved')`,
		appointmentID,
	)
	if err != nil {
		return Plan{}, fmt.Errorf("approve recommendations: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return Plan{}, fmt.Errorf("read approved recommendations rows: %w", err)
	}
	if affected == 0 {
		return Plan{}, ErrRecommendationsDraft
	}
	return r.FindPlan(ctx, appointmentID)
}

func scanPlan(rows *sql.Rows, appointmentID string) (Plan, error) {
	plan := Plan{
		AppointmentID: appointmentID,
		Status:        StatusDraft,
		Steps:         []Step{},
	}

	for rows.Next() {
		var step Step
		var journalID string
		var status string
		var dueOffset sql.NullInt64
		var dueAt sql.NullTime
		var createdBy string
		var createdAt time.Time
		var sentAt sql.NullTime
		var approvedAt sql.NullTime

		if err := rows.Scan(
			&step.ID,
			&journalID,
			&status,
			&step.StepNumber,
			&step.Title,
			&step.Description,
			&dueOffset,
			&dueAt,
			&createdBy,
			&createdAt,
			&sentAt,
			&approvedAt,
		); err != nil {
			return Plan{}, fmt.Errorf("scan recommendations: %w", err)
		}

		if journalID != "" {
			plan.JournalID = journalID
		}
		if recommendationStatusRank(status) > recommendationStatusRank(plan.Status) {
			plan.Status = status
		}
		if dueOffset.Valid {
			value := int(dueOffset.Int64)
			step.DueOffsetDays = &value
		}
		if dueAt.Valid {
			value := dueAt.Time
			step.DueAt = &value
		}
		if plan.CreatedBy == "" {
			plan.CreatedBy = createdBy
			plan.CreatedAt = &createdAt
		}
		if sentAt.Valid {
			value := sentAt.Time
			plan.SentAt = &value
		}
		if approvedAt.Valid {
			value := approvedAt.Time
			plan.ApprovedAt = &value
		}
		plan.Steps = append(plan.Steps, step)
	}

	if err := rows.Err(); err != nil {
		return Plan{}, fmt.Errorf("iterate recommendations: %w", err)
	}

	return plan, nil
}

func recommendationStatusRank(status string) int {
	switch status {
	case StatusApproved:
		return 3
	case StatusSent:
		return 2
	case StatusDraft:
		return 1
	default:
		return 0
	}
}
