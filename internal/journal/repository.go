package journal

import (
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"

	platformcrypto "inkconnect/internal/platform/crypto"
)

var eventHashPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

type Repository interface {
	EnsureSchema(ctx context.Context) error
	EnsureForApprovedAppointment(ctx context.Context, appointmentID string, clientID string) (string, error)
	FindJournal(ctx context.Context, journalID string) (Journal, error)
	ListClientJournals(ctx context.Context, clientID string) ([]Journal, error)
	ListMasterJournals(ctx context.Context, masterID string) ([]Journal, error)
	ListAppointmentJournals(ctx context.Context, appointmentID string) ([]AppointmentJournalSummary, error)
	ListSteps(ctx context.Context, journalID string) ([]Step, error)
	ListProtectedSteps(ctx context.Context, journalID string) ([]JournalStep, error)
	ListEvents(ctx context.Context, journalID string) ([]JournalEventView, error)
	VerifyIntegrity(ctx context.Context, journalID string) (IntegrityReport, error)
	PrepareStepConfirmation(ctx context.Context, journalID string, stepID string, clientID string) (StepConfirmationPrepare, error)
	CommitStepConfirmation(ctx context.Context, journalID string, stepID string, clientID string, request StepConfirmationCommit) error
	ConfirmStep(ctx context.Context, journalID string, stepID string, clientID string) error
	CreateClientUnavailabilityNotice(ctx context.Context, journalID string, clientID string, input ClientUnavailabilityNoticeInput) (JournalEventResult, error)
	CreateClientProblemReport(ctx context.Context, journalID string, clientID string, input ClientProblemReportInput) (JournalEventResult, error)
	CreateDeadlineExtension(ctx context.Context, journalID string, stepID string, masterID string, input DeadlineExtensionInput) (DeadlineExtensionResult, error)
	StopJournal(ctx context.Context, journalID string, masterID string, input JournalStopInput) (JournalStopResult, error)
	CreateReplacementJournal(ctx context.Context, journalID string, masterID string, input ReplacementJournalInput) (ReplacementJournalResult, error)
}

type PostgresRepository struct {
	db            *sql.DB
	signingConfig RepositorySigningConfig
}

type RepositorySigningConfig struct {
	EncryptionKey   string
	EncryptionKeyID string
}

func NewPostgresRepository(db *sql.DB, signingConfig ...RepositorySigningConfig) *PostgresRepository {
	cfg := RepositorySigningConfig{}
	if len(signingConfig) > 0 {
		cfg = signingConfig[0]
	}

	return &PostgresRepository{
		db:            db,
		signingConfig: cfg,
	}
}

func EnsureJournalSchema(ctx context.Context, db *sql.DB, signingConfig ...RepositorySigningConfig) error {
	return NewPostgresRepository(db, signingConfig...).EnsureSchema(ctx)
}

func (r *PostgresRepository) EnsureSchema(ctx context.Context) error {
	statements := []string{
		`ALTER TABLE care_journals
		 ALTER COLUMN integrity_status SET DEFAULT FALSE`,
		`CREATE TABLE IF NOT EXISTS user_signing_keys (
		    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		    public_key TEXT NOT NULL,
		    encrypted_private_key TEXT,
		    private_key_encryption_key_id TEXT,
		    private_key_encrypted_at TIMESTAMPTZ,
		    algorithm TEXT NOT NULL DEFAULT 'ed25519',
		    key_fingerprint TEXT NOT NULL,
		    status TEXT NOT NULL DEFAULT 'active',
		    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		    revoked_at TIMESTAMPTZ,
		    CONSTRAINT user_signing_keys_public_key_chk
		        CHECK (btrim(public_key) <> ''),
		    CONSTRAINT user_signing_keys_algorithm_chk
		        CHECK (algorithm IN ('ed25519')),
		    CONSTRAINT user_signing_keys_fingerprint_chk
		        CHECK (btrim(key_fingerprint) <> ''),
		    CONSTRAINT user_signing_keys_status_chk
		        CHECK (status IN ('active', 'revoked')),
		    CONSTRAINT user_signing_keys_revoked_at_chk
		        CHECK (
		            (status = 'revoked' AND revoked_at IS NOT NULL)
		            OR (status <> 'revoked')
		        )
		)`,
		`ALTER TABLE user_signing_keys
		 ADD COLUMN IF NOT EXISTS encrypted_private_key TEXT`,
		`ALTER TABLE user_signing_keys
		 ADD COLUMN IF NOT EXISTS private_key_encryption_key_id TEXT`,
		`ALTER TABLE user_signing_keys
		 ADD COLUMN IF NOT EXISTS private_key_encrypted_at TIMESTAMPTZ`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS created_by_master_id UUID REFERENCES users(id) ON DELETE RESTRICT`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS root_journal_id UUID REFERENCES care_journals(id) ON DELETE SET NULL`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS parent_journal_id UUID REFERENCES care_journals(id) ON DELETE SET NULL`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS replaced_by_journal_id UUID REFERENCES care_journals(id) ON DELETE SET NULL`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS version_number INTEGER NOT NULL DEFAULT 1`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS stopped_at TIMESTAMPTZ`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS stop_reason TEXT`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS replacement_reason TEXT`,
		`ALTER TABLE care_journals
		 ADD COLUMN IF NOT EXISTS final_hash TEXT`,
		`ALTER TABLE care_journals
		 DROP CONSTRAINT IF EXISTS care_journals_status_chk`,
		`ALTER TABLE care_journals
		 ADD CONSTRAINT care_journals_status_chk
		 CHECK (status IN (
		   'draft',
		   'awaiting_client_confirmation',
		   'active',
		   'completed',
		   'stopped',
		   'replaced'
		 ))`,
		`ALTER TABLE care_journals
		 DROP CONSTRAINT IF EXISTS care_journals_version_number_chk`,
		`ALTER TABLE care_journals
		 ADD CONSTRAINT care_journals_version_number_chk
		 CHECK (version_number > 0)`,
		`ALTER TABLE care_journals
		 DROP CONSTRAINT IF EXISTS care_journals_appointment_id_key`,
		`DROP INDEX IF EXISTS care_journals_appointment_id_key`,
		`CREATE TABLE IF NOT EXISTS care_journal_steps (
		    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		    journal_id UUID NOT NULL REFERENCES care_journals(id) ON DELETE CASCADE,
		    day_number INTEGER NOT NULL,
		    title TEXT NOT NULL,
		    description TEXT NOT NULL,
		    deadline_at TIMESTAMPTZ,
		    status TEXT NOT NULL DEFAULT 'pending',
		    completed_at TIMESTAMPTZ,
		    completed_by_client_id UUID REFERENCES users(id) ON DELETE RESTRICT,
		    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		    CONSTRAINT care_journal_steps_day_number_chk
		        CHECK (day_number > 0),
		    CONSTRAINT care_journal_steps_status_chk
		        CHECK (status IN (
		            'pending',
		            'completed_by_client',
		            'cancelled_due_to_journal_stop'
		        )),
		    CONSTRAINT care_journal_steps_completed_chk
		        CHECK (
		            (status = 'completed_by_client' AND completed_at IS NOT NULL AND completed_by_client_id IS NOT NULL)
		            OR (status <> 'completed_by_client')
		        )
		)`,
		`CREATE TABLE IF NOT EXISTS care_journal_events (
		    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		    journal_id UUID NOT NULL REFERENCES care_journals(id) ON DELETE CASCADE,
		    step_id UUID REFERENCES care_journal_steps(id) ON DELETE SET NULL,
		    event_type TEXT NOT NULL,
		    actor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
		    actor_role TEXT NOT NULL,
		    signing_key_id UUID REFERENCES user_signing_keys(id) ON DELETE SET NULL,
		    payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
		    reason TEXT,
		    previous_hash TEXT,
		    event_hash TEXT,
		    signature TEXT,
		    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		    CONSTRAINT care_journal_events_type_chk
		        CHECK (event_type IN (
		            'journal_created',
		            'journal_activated',
		            'client_confirmed_recommendations',
		            'client_requested_clarification',
		            'step_added',
		            'step_completed_by_client',
		            'client_unavailability_notice_added',
		            'deadline_extended',
		            'client_problem_reported',
		            'journal_stopped',
		            'replacement_journal_created',
		            'journal_completed',
		            'integrity_checked'
		        )),
		    CONSTRAINT care_journal_events_actor_role_chk
		        CHECK (actor_role IN ('client', 'master', 'admin', 'system')),
		    CONSTRAINT care_journal_events_hash_chk
		        CHECK (event_hash IS NULL OR btrim(event_hash) <> ''),
		    CONSTRAINT care_journal_events_signature_chk
		        CHECK (signature IS NULL OR btrim(signature) <> '')
		)`,
		`ALTER TABLE care_journal_events
		 ALTER COLUMN event_hash DROP NOT NULL`,
		`ALTER TABLE care_journal_events
		 DROP CONSTRAINT IF EXISTS care_journal_events_hash_chk`,
		`ALTER TABLE care_journal_events
		 ADD CONSTRAINT care_journal_events_hash_chk
		 CHECK (event_hash IS NULL OR btrim(event_hash) <> '')`,
		`CREATE INDEX IF NOT EXISTS idx_user_signing_keys_user_id_status
		 ON user_signing_keys(user_id, status)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_user_signing_keys_user_id_fingerprint
		 ON user_signing_keys(user_id, key_fingerprint)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_user_signing_keys_fingerprint
		 ON user_signing_keys(key_fingerprint)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journals_appointment_id
		 ON care_journals(appointment_id)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_care_journals_one_open_per_appointment
		 ON care_journals(appointment_id)
		 WHERE status IN ('draft', 'awaiting_client_confirmation', 'active')`,
		`CREATE INDEX IF NOT EXISTS idx_care_journals_status
		 ON care_journals(status)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journals_root_journal_id
		 ON care_journals(root_journal_id)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journals_parent_journal_id
		 ON care_journals(parent_journal_id)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journals_replaced_by_journal_id
		 ON care_journals(replaced_by_journal_id)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_steps_journal_id
		 ON care_journal_steps(journal_id)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_steps_status
		 ON care_journal_steps(status)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_steps_deadline_at
		 ON care_journal_steps(deadline_at)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_steps_completed_by_client_id
		 ON care_journal_steps(completed_by_client_id)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_events_journal_id_created_at
		 ON care_journal_events(journal_id, created_at)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_events_step_id
		 ON care_journal_events(step_id)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_events_actor_id
		 ON care_journal_events(actor_id)`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_events_signing_key_id
		 ON care_journal_events(signing_key_id)`,
		`DROP INDEX IF EXISTS idx_care_journal_events_event_hash`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_care_journal_events_event_hash
		 ON care_journal_events(event_hash)
		 WHERE event_hash IS NOT NULL`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_care_journal_events_step_completed_unique
		 ON care_journal_events(journal_id, step_id)
		 WHERE event_type = 'step_completed_by_client' AND step_id IS NOT NULL`,
		`DROP TRIGGER IF EXISTS trg_care_journal_steps_updated_at ON care_journal_steps`,
		`CREATE TRIGGER trg_care_journal_steps_updated_at
		 BEFORE UPDATE ON care_journal_steps
		 FOR EACH ROW
		 EXECUTE FUNCTION set_updated_at()`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_care_journal_entries_client_confirmation_unique
		 ON care_journal_entries(journal_id, recommendation_id)
		 WHERE entry_type = 'client_confirmation'`,
		`CREATE INDEX IF NOT EXISTS idx_care_journal_entries_recommendation_id
		 ON care_journal_entries(recommendation_id)`,
		`UPDATE care_journal_steps cjs
		 SET deadline_at = COALESCE(
		       (
		         SELECT cr.due_at
		         FROM care_recommendations cr
		         WHERE cr.journal_id = cjs.journal_id
		           AND cr.title = cjs.title
		           AND cr.description = cjs.description
		           AND COALESCE(NULLIF(cr.due_offset_days, 0), cr.step_number) = cjs.day_number
		           AND cr.due_at IS NOT NULL
		         ORDER BY cr.step_number ASC, cr.created_at ASC, cr.id ASC
		         LIMIT 1
		       ),
		       a.scheduled_at + make_interval(days => cjs.day_number)
		     )
		 FROM care_journals cj
		 JOIN appointments a ON a.id = cj.appointment_id
		 WHERE cjs.journal_id = cj.id
		   AND cjs.deadline_at IS NULL
		   AND cjs.day_number > 0`,
	}

	for _, statement := range statements {
		if _, err := r.db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("ensure journal schema: %w", err)
		}
	}
	if err := r.ensureUserSigningKeysFromUsers(ctx); err != nil {
		return err
	}
	if err := r.ensureBackendManagedSigningKeysForUsers(ctx); err != nil {
		return err
	}
	return nil
}

func (r *PostgresRepository) ensureUserSigningKeysFromUsers(ctx context.Context) error {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id::text, public_key, created_at
		 FROM users
		 WHERE public_key IS NOT NULL
		   AND btrim(public_key) <> ''`,
	)
	if err != nil {
		return fmt.Errorf("load users public keys for signing key sync: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var userID string
		var publicKey string
		var createdAt time.Time
		if err = rows.Scan(&userID, &publicKey, &createdAt); err != nil {
			return fmt.Errorf("scan user public key for signing key sync: %w", err)
		}

		rawKey, err := decodeEd25519PublicKey(publicKey)
		if err != nil {
			log.Printf("journal signing key sync: skipping user %s with invalid public_key: %v", userID, err)
			continue
		}
		fingerprint := fingerprintPublicKey(rawKey)

		if _, err = r.db.ExecContext(
			ctx,
			`INSERT INTO user_signing_keys (
			   user_id, public_key, algorithm, key_fingerprint, status, created_at
			 )
			 VALUES ($1, $2, 'ed25519', $3, 'active', $4)
			 ON CONFLICT DO NOTHING`,
			userID,
			strings.TrimSpace(publicKey),
			fingerprint,
			createdAt,
		); err != nil {
			return fmt.Errorf("sync user signing key from public key: %w", err)
		}
	}
	if err = rows.Err(); err != nil {
		return fmt.Errorf("iterate user public keys for signing key sync: %w", err)
	}
	return nil
}

func decodeEd25519PublicKey(publicKey string) ([]byte, error) {
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(publicKey))
	if err != nil {
		return nil, fmt.Errorf("decode base64 public key: %w", err)
	}
	if len(decoded) != ed25519.PublicKeySize {
		return nil, fmt.Errorf("invalid ed25519 public key length: got %d, want %d", len(decoded), ed25519.PublicKeySize)
	}
	return decoded, nil
}

func fingerprintPublicKey(publicKey []byte) string {
	sum := sha256.Sum256(publicKey)
	return hex.EncodeToString(sum[:])
}

func (r *PostgresRepository) ensureBackendManagedSigningKeysForUsers(ctx context.Context) error {
	if strings.TrimSpace(r.signingConfig.EncryptionKey) == "" || strings.TrimSpace(r.signingConfig.EncryptionKeyID) == "" {
		log.Printf("journal signing key sync: backend-managed signing key provisioning skipped because encryption config is missing")
		return nil
	}

	protector, err := r.privateKeyProtector()
	if err != nil {
		return fmt.Errorf("create backend-managed signing key sync protector: %w", err)
	}

	rows, err := r.db.QueryContext(
		ctx,
		`SELECT u.id::text
		 FROM users u
		 WHERE u.is_active = TRUE
		   AND NOT EXISTS (
		     SELECT 1
		     FROM user_signing_keys usk
		     WHERE usk.user_id = u.id
		       AND usk.algorithm = 'ed25519'
		       AND usk.status = 'active'
		       AND usk.encrypted_private_key IS NOT NULL
		       AND btrim(usk.encrypted_private_key) <> ''
		   )
		 ORDER BY u.created_at ASC, u.id ASC`,
	)
	if err != nil {
		return fmt.Errorf("load users missing backend-managed signing key: %w", err)
	}
	var userIDs []string
	for rows.Next() {
		var userID string
		if err = rows.Scan(&userID); err != nil {
			_ = rows.Close()
			return fmt.Errorf("scan user missing backend-managed signing key: %w", err)
		}
		userIDs = append(userIDs, userID)
	}
	if err = rows.Close(); err != nil {
		return fmt.Errorf("close users missing backend-managed signing key rows: %w", err)
	}
	if err = rows.Err(); err != nil {
		return fmt.Errorf("iterate users missing backend-managed signing key: %w", err)
	}

	for _, userID := range userIDs {
		if err = r.provisionBackendManagedSigningKey(ctx, protector, userID); err != nil {
			return err
		}
	}
	if len(userIDs) > 0 {
		log.Printf("journal signing key sync: provisioned backend-managed encrypted signing keys for %d users", len(userIDs))
	}
	return nil
}

func (r *PostgresRepository) provisionBackendManagedSigningKey(ctx context.Context, protector *platformcrypto.PrivateKeyProtector, userID string) error {
	keyPair, err := platformcrypto.GenerateKeyPair()
	if err != nil {
		return fmt.Errorf("generate backend-managed signing key for user %s: %w", userID, err)
	}
	rawPublicKey, err := decodeEd25519PublicKey(keyPair.PublicKey)
	if err != nil {
		return fmt.Errorf("prepare backend-managed signing key for user %s: %w", userID, err)
	}
	fingerprint := fingerprintPublicKey(rawPublicKey)
	encryptedPrivateKey, err := protector.EncryptPrivateKey(keyPair.PrivateKey, userID, fingerprint, SigningKeyAlgorithmEd25519)
	if err != nil {
		return fmt.Errorf("encrypt backend-managed signing key for user %s: %w", userID, err)
	}
	now := time.Now().UTC()

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin backend-managed signing key provisioning: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	if _, err = tx.ExecContext(
		ctx,
		`UPDATE users
		 SET public_key = $2
		 WHERE id = $1`,
		userID,
		strings.TrimSpace(keyPair.PublicKey),
	); err != nil {
		return fmt.Errorf("update user public key for backend-managed signing key: %w", err)
	}

	if _, err = tx.ExecContext(
		ctx,
		`INSERT INTO user_signing_keys (
		   user_id,
		   public_key,
		   algorithm,
		   key_fingerprint,
		   status,
		   encrypted_private_key,
		   private_key_encryption_key_id,
		   private_key_encrypted_at,
		   created_at
		 )
		 VALUES ($1, $2, 'ed25519', $3, 'active', $4, $5, $6, $6)
		 ON CONFLICT (user_id, key_fingerprint) DO UPDATE
		 SET public_key = EXCLUDED.public_key,
		     algorithm = EXCLUDED.algorithm,
		     status = EXCLUDED.status,
		     encrypted_private_key = EXCLUDED.encrypted_private_key,
		     private_key_encryption_key_id = EXCLUDED.private_key_encryption_key_id,
		     private_key_encrypted_at = EXCLUDED.private_key_encrypted_at`,
		userID,
		strings.TrimSpace(keyPair.PublicKey),
		fingerprint,
		encryptedPrivateKey,
		strings.TrimSpace(r.signingConfig.EncryptionKeyID),
		now,
	); err != nil {
		return fmt.Errorf("insert backend-managed signing key: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit backend-managed signing key provisioning: %w", err)
	}
	committed = true
	return nil
}

func (r *PostgresRepository) EnsureForApprovedAppointment(ctx context.Context, appointmentID string, clientID string) (string, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return "", fmt.Errorf("begin ensure journal: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var appointmentClientID string
	var masterID string
	var status string
	err = tx.QueryRowContext(
		ctx,
		`SELECT a.client_id::text,
		        a.master_id::text,
		        a.status::text
		 FROM appointments a
		 WHERE a.id = $1
		 FOR UPDATE OF a`,
		appointmentID,
	).Scan(&appointmentClientID, &masterID, &status)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", ErrAppointmentNotFound
		}
		return "", fmt.Errorf("load appointment for journal: %w", err)
	}
	if appointmentClientID != clientID {
		return "", ErrForbidden
	}
	if status != "confirmed" && status != "completed" {
		return "", ErrNotReady
	}

	var journalID string
	err = tx.QueryRowContext(
		ctx,
		`SELECT id::text
		 FROM care_journals
		 WHERE appointment_id = $1
		   AND status IN ('draft', 'awaiting_client_confirmation', 'active')
		 ORDER BY version_number DESC, created_at DESC, id DESC
		 LIMIT 1`,
		appointmentID,
	).Scan(&journalID)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return "", fmt.Errorf("find open care journal: %w", err)
		}
	} else {
		if err = tx.Commit(); err != nil {
			return "", fmt.Errorf("commit ensure existing open journal: %w", err)
		}
		committed = true
		return journalID, nil
	}

	var recommendationsTotal int
	var recommendationsApproved int
	if err = tx.QueryRowContext(
		ctx,
		`SELECT COUNT(*)::int,
		        COUNT(*) FILTER (WHERE status = 'approved')::int
		 FROM care_recommendations
		 WHERE appointment_id = $1`,
		appointmentID,
	).Scan(&recommendationsTotal, &recommendationsApproved); err != nil {
		return "", fmt.Errorf("count approved recommendations: %w", err)
	}
	if recommendationsTotal == 0 || recommendationsApproved != recommendationsTotal {
		return "", ErrNotReady
	}

	err = tx.QueryRowContext(
		ctx,
		`SELECT id::text
		 FROM care_journals
		 WHERE appointment_id = $1
		 ORDER BY version_number DESC, created_at DESC, id DESC
		 LIMIT 1`,
		appointmentID,
	).Scan(&journalID)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return "", fmt.Errorf("find existing care journal: %w", err)
		}
		err = tx.QueryRowContext(
			ctx,
			`INSERT INTO care_journals (appointment_id, client_id, master_id, integrity_status)
			 VALUES ($1, $2, $3, FALSE)
			 RETURNING id::text`,
			appointmentID,
			clientID,
			masterID,
		).Scan(&journalID)
		if err != nil {
			return "", fmt.Errorf("insert care journal: %w", err)
		}
	}

	var parentJournalID sql.NullString
	if err = tx.QueryRowContext(
		ctx,
		`SELECT parent_journal_id::text
		 FROM care_journals
		 WHERE id = $1`,
		journalID,
	).Scan(&parentJournalID); err != nil {
		return "", fmt.Errorf("load journal parent for recommendation linking: %w", err)
	}
	if !parentJournalID.Valid {
		if _, err = tx.ExecContext(
			ctx,
			`UPDATE care_recommendations
			 SET journal_id = $2
			 WHERE appointment_id = $1
			   AND status = 'approved'`,
			appointmentID,
			journalID,
		); err != nil {
			return "", fmt.Errorf("link recommendations to journal: %w", err)
		}

		if _, err = tx.ExecContext(
			ctx,
			`INSERT INTO care_journal_steps (
			   journal_id, day_number, title, description, deadline_at, status, completed_at, completed_by_client_id
			 )
			 SELECT $2,
			        COALESCE(NULLIF(cr.due_offset_days, 0), cr.step_number),
			        cr.title,
			        cr.description,
			        COALESCE(
			          cr.due_at,
			          a.scheduled_at + make_interval(days => COALESCE(NULLIF(cr.due_offset_days, 0), cr.step_number))
			        ),
			        CASE
			          WHEN confirmation.confirmed_at IS NOT NULL AND confirmation.actor_user_id IS NOT NULL
			          THEN 'completed_by_client'
			          ELSE 'pending'
			        END,
			        confirmation.confirmed_at,
			        confirmation.actor_user_id
			 FROM care_recommendations cr
			 JOIN appointments a ON a.id = cr.appointment_id
			 LEFT JOIN LATERAL (
			   SELECT e.created_at AS confirmed_at,
			          e.actor_user_id
			   FROM care_journal_entries e
			   WHERE e.journal_id = $2
			     AND e.recommendation_id = cr.id
			     AND e.entry_type = 'client_confirmation'
			   ORDER BY e.created_at ASC
			   LIMIT 1
			 ) confirmation ON TRUE
			 WHERE cr.appointment_id = $1
			   AND cr.status = 'approved'
			   AND NOT EXISTS (
			     SELECT 1
			     FROM care_journal_steps existing
			     WHERE existing.journal_id = $2
			   )
			 ORDER BY cr.step_number ASC`,
			appointmentID,
			journalID,
		); err != nil {
			return "", fmt.Errorf("copy recommendations to journal steps: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return "", fmt.Errorf("commit ensure journal: %w", err)
	}
	committed = true

	return journalID, nil
}

func (r *PostgresRepository) FindJournal(ctx context.Context, journalID string) (Journal, error) {
	return scanJournal(
		r.db.QueryRowContext(
			ctx,
			`SELECT id::text,
			        appointment_id::text,
			        client_id::text,
			        master_id::text,
			        integrity_status,
			        last_verified_at,
			        created_at,
			        COALESCE(status, 'active'),
			        root_journal_id::text,
			        parent_journal_id::text,
			        replaced_by_journal_id::text,
			        COALESCE(version_number, 1),
			        activated_at,
			        stopped_at,
			        completed_at,
			        stop_reason,
			        replacement_reason,
			        final_hash
			 FROM care_journals
			 WHERE id = $1`,
			journalID,
		),
	)
}

func (r *PostgresRepository) ListClientJournals(ctx context.Context, clientID string) ([]Journal, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id::text,
		        appointment_id::text,
		        client_id::text,
		        master_id::text,
		        integrity_status,
		        last_verified_at,
		        created_at,
		        COALESCE(status, 'active'),
		        root_journal_id::text,
		        parent_journal_id::text,
		        replaced_by_journal_id::text,
		        COALESCE(version_number, 1),
		        activated_at,
		        stopped_at,
		        completed_at,
		        stop_reason,
		        replacement_reason,
		        final_hash
		 FROM care_journals
		 WHERE client_id = $1
		 ORDER BY created_at DESC`,
		clientID,
	)
	if err != nil {
		return nil, fmt.Errorf("list client journals: %w", err)
	}
	defer rows.Close()

	return scanJournals(rows)
}

func (r *PostgresRepository) ListMasterJournals(ctx context.Context, masterID string) ([]Journal, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id::text,
		        appointment_id::text,
		        client_id::text,
		        master_id::text,
		        integrity_status,
		        last_verified_at,
		        created_at,
		        COALESCE(status, 'active'),
		        root_journal_id::text,
		        parent_journal_id::text,
		        replaced_by_journal_id::text,
		        COALESCE(version_number, 1),
		        activated_at,
		        stopped_at,
		        completed_at,
		        stop_reason,
		        replacement_reason,
		        final_hash
		 FROM care_journals
		 WHERE master_id = $1
		 ORDER BY created_at DESC`,
		masterID,
	)
	if err != nil {
		return nil, fmt.Errorf("list master journals: %w", err)
	}
	defer rows.Close()

	return scanJournals(rows)
}

func (r *PostgresRepository) ListAppointmentJournals(ctx context.Context, appointmentID string) ([]AppointmentJournalSummary, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT cj.id::text,
		        cj.appointment_id::text,
		        COALESCE(cj.status, 'active'),
		        COALESCE(cj.version_number, 1),
		        cj.parent_journal_id::text,
		        COALESCE(cj.root_journal_id::text, cj.id::text),
		        cj.replaced_by_journal_id::text,
		        cj.created_at,
		        cj.stopped_at,
		        cj.completed_at,
		        cj.stop_reason,
		        cj.replacement_reason,
		        cj.final_hash,
		        COUNT(cjs.id)::int,
		        COUNT(cjs.id) FILTER (WHERE cjs.status = 'completed_by_client')::int,
		        COUNT(cjs.id) FILTER (WHERE cjs.status = 'pending')::int,
		        COUNT(cjs.id) FILTER (WHERE cjs.status = 'cancelled_due_to_journal_stop')::int,
		        COALESCE(cj.status, 'active') IN ('draft', 'awaiting_client_confirmation', 'active')
		 FROM care_journals cj
		 LEFT JOIN care_journal_steps cjs ON cjs.journal_id = cj.id
		 WHERE cj.appointment_id = $1
		 GROUP BY cj.id
		 ORDER BY COALESCE(cj.version_number, 1) ASC, cj.created_at ASC, cj.id ASC`,
		appointmentID,
	)
	if err != nil {
		return nil, fmt.Errorf("list appointment journals: %w", err)
	}
	defer rows.Close()

	items := []AppointmentJournalSummary{}
	for rows.Next() {
		var item AppointmentJournalSummary
		var status string
		var parentJournalID sql.NullString
		var replacedByJournalID sql.NullString
		var stoppedAt sql.NullTime
		var completedAt sql.NullTime
		var stopReason sql.NullString
		var replacementReason sql.NullString
		var finalHash sql.NullString
		if err := rows.Scan(
			&item.ID,
			&item.AppointmentID,
			&status,
			&item.VersionNumber,
			&parentJournalID,
			&item.RootJournalID,
			&replacedByJournalID,
			&item.CreatedAt,
			&stoppedAt,
			&completedAt,
			&stopReason,
			&replacementReason,
			&finalHash,
			&item.StepsCount,
			&item.CompletedStepsCount,
			&item.PendingStepsCount,
			&item.CancelledStepsCount,
			&item.IsOpen,
		); err != nil {
			return nil, fmt.Errorf("scan appointment journal summary: %w", err)
		}
		item.Status = JournalStatus(status)
		if parentJournalID.Valid {
			item.ParentJournalID = &parentJournalID.String
		}
		if replacedByJournalID.Valid {
			item.ReplacedByJournalID = &replacedByJournalID.String
		}
		if stoppedAt.Valid {
			value := stoppedAt.Time
			item.StoppedAt = &value
		}
		if completedAt.Valid {
			value := completedAt.Time
			item.CompletedAt = &value
		}
		if stopReason.Valid {
			item.StopReason = &stopReason.String
		}
		if replacementReason.Valid {
			item.ReplacementReason = &replacementReason.String
		}
		if finalHash.Valid {
			item.FinalHash = &finalHash.String
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate appointment journals: %w", err)
	}
	return items, nil
}

func (r *PostgresRepository) ListSteps(ctx context.Context, journalID string) ([]Step, error) {
	protectedSteps, err := r.listStepsFromProtectedSteps(ctx, journalID)
	if err != nil {
		return nil, err
	}
	if len(protectedSteps) > 0 {
		return protectedSteps, nil
	}

	rows, err := r.db.QueryContext(
		ctx,
		`SELECT cr.id::text,
		        cr.step_number,
		        cr.title,
		        cr.description,
		        cr.due_offset_days,
		        COALESCE(
		          cr.due_at,
		          a.scheduled_at + make_interval(days => COALESCE(NULLIF(cr.due_offset_days, 0), cr.step_number))
		        ),
		        confirmation.confirmed_at
		 FROM care_recommendations cr
		 JOIN care_journals cj ON cj.id = cr.journal_id
		 JOIN appointments a ON a.id = cj.appointment_id
		 LEFT JOIN LATERAL (
		   SELECT e.created_at AS confirmed_at
		   FROM care_journal_entries e
		   WHERE e.journal_id = $1
		     AND e.recommendation_id = cr.id
		     AND e.entry_type = 'client_confirmation'
		   ORDER BY e.created_at DESC, e.id DESC
		   LIMIT 1
		 ) confirmation ON TRUE
		 WHERE cr.journal_id = $1
		 ORDER BY cr.step_number ASC`,
		journalID,
	)
	if err != nil {
		return nil, fmt.Errorf("list journal steps: %w", err)
	}
	defer rows.Close()

	var steps []Step
	for rows.Next() {
		var step Step
		var dueOffset sql.NullInt64
		var dueAt sql.NullTime
		var confirmedAt sql.NullTime
		if err := rows.Scan(
			&step.ID,
			&step.StepNumber,
			&step.Title,
			&step.Description,
			&dueOffset,
			&dueAt,
			&confirmedAt,
		); err != nil {
			return nil, fmt.Errorf("scan journal step: %w", err)
		}
		if dueOffset.Valid {
			value := int(dueOffset.Int64)
			step.DueOffsetDays = &value
		}
		step.DayNumber = step.StepNumber
		if step.DueOffsetDays == nil {
			value := step.StepNumber
			step.DueOffsetDays = &value
		}
		if dueAt.Valid {
			value := dueAt.Time
			step.DueAt = &value
			step.DeadlineAt = &value
		}
		if confirmedAt.Valid {
			value := confirmedAt.Time
			step.ConfirmedAt = &value
			step.CompletedAt = &value
		}
		if step.ConfirmedAt != nil {
			step.Status = string(JournalStepStatusCompletedByClient)
		} else {
			step.Status = string(JournalStepStatusPending)
		}
		steps = append(steps, step)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate journal steps: %w", err)
	}
	return steps, nil
}

func (r *PostgresRepository) ListEvents(ctx context.Context, journalID string) ([]JournalEventView, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id::text,
		        journal_id::text,
		        step_id::text,
		        event_type,
		        actor_role,
		        payload_json::text,
		        reason,
		        created_at,
		        event_hash IS NOT NULL AND btrim(event_hash) <> '',
		        signature IS NOT NULL AND btrim(signature) <> ''
		 FROM care_journal_events
		 WHERE journal_id = $1
		 ORDER BY created_at ASC, id ASC`,
		journalID,
	)
	if err != nil {
		return nil, fmt.Errorf("list journal events: %w", err)
	}
	defer rows.Close()

	events := []JournalEventView{}
	for rows.Next() {
		var event JournalEventView
		var stepID sql.NullString
		var payload string
		var reason sql.NullString
		var eventType string
		var actorRole string
		if err := rows.Scan(
			&event.ID,
			&event.JournalID,
			&stepID,
			&eventType,
			&actorRole,
			&payload,
			&reason,
			&event.CreatedAt,
			&event.HasHash,
			&event.HasSignature,
		); err != nil {
			return nil, fmt.Errorf("scan journal event: %w", err)
		}
		if stepID.Valid {
			value := stepID.String
			event.StepID = &value
		}
		if reason.Valid {
			value := reason.String
			event.Reason = &value
		}
		event.EventType = JournalEventType(eventType)
		event.ActorRole = JournalActorRole(actorRole)
		event.PayloadJSON = json.RawMessage(payload)
		events = append(events, event)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate journal events: %w", err)
	}
	return events, nil
}

func (r *PostgresRepository) listStepsFromProtectedSteps(ctx context.Context, journalID string) ([]Step, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT cjs.id::text,
		        cjs.day_number,
		        cjs.title,
		        cjs.description,
		        COALESCE(cjs.deadline_at, a.scheduled_at + make_interval(days => cjs.day_number)),
		        cjs.status,
		        cjs.completed_at
		 FROM care_journal_steps cjs
		 JOIN care_journals cj ON cj.id = cjs.journal_id
		 JOIN appointments a ON a.id = cj.appointment_id
		 WHERE cjs.journal_id = $1
		 ORDER BY cjs.day_number ASC, cjs.created_at ASC, cjs.id ASC`,
		journalID,
	)
	if err != nil {
		return nil, fmt.Errorf("list protected steps as journal steps: %w", err)
	}
	defer rows.Close()

	steps := []Step{}
	for rows.Next() {
		var step Step
		var deadlineAt sql.NullTime
		var completedAt sql.NullTime
		var status string
		if err := rows.Scan(
			&step.ID,
			&step.StepNumber,
			&step.Title,
			&step.Description,
			&deadlineAt,
			&status,
			&completedAt,
		); err != nil {
			return nil, fmt.Errorf("scan protected step as journal step: %w", err)
		}
		step.DayNumber = step.StepNumber
		value := step.StepNumber
		step.DueOffsetDays = &value
		step.Status = status
		if deadlineAt.Valid {
			value := deadlineAt.Time
			step.DueAt = &value
			step.DeadlineAt = &value
		}
		if completedAt.Valid {
			value := completedAt.Time
			step.ConfirmedAt = &value
			step.CompletedAt = &value
		}
		steps = append(steps, step)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate protected steps as journal steps: %w", err)
	}
	return steps, nil
}

func (r *PostgresRepository) ListProtectedSteps(ctx context.Context, journalID string) ([]JournalStep, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id::text,
		        journal_id::text,
		        day_number,
		        title,
		        description,
		        deadline_at,
		        status,
		        completed_at,
		        completed_by_client_id::text,
		        created_at,
		        updated_at
		 FROM care_journal_steps
		 WHERE journal_id = $1
		 ORDER BY day_number ASC, created_at ASC, id ASC`,
		journalID,
	)
	if err != nil {
		return nil, fmt.Errorf("list protected journal steps: %w", err)
	}
	defer rows.Close()

	var steps []JournalStep
	for rows.Next() {
		var step JournalStep
		var deadlineAt sql.NullTime
		var completedAt sql.NullTime
		var completedByClientID sql.NullString
		var status string
		if err := rows.Scan(
			&step.ID,
			&step.JournalID,
			&step.DayNumber,
			&step.Title,
			&step.Description,
			&deadlineAt,
			&status,
			&completedAt,
			&completedByClientID,
			&step.CreatedAt,
			&step.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan protected journal step: %w", err)
		}
		if deadlineAt.Valid {
			value := deadlineAt.Time
			step.DeadlineAt = &value
		}
		step.Status = JournalStepStatus(status)
		if completedAt.Valid {
			value := completedAt.Time
			step.CompletedAt = &value
		}
		if completedByClientID.Valid {
			value := completedByClientID.String
			step.CompletedByClientID = &value
		}
		steps = append(steps, step)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate protected journal steps: %w", err)
	}
	if steps == nil {
		steps = []JournalStep{}
	}
	return steps, nil
}

func (r *PostgresRepository) VerifyIntegrity(ctx context.Context, journalID string) (IntegrityReport, error) {
	var finalHash sql.NullString
	err := r.db.QueryRowContext(
		ctx,
		`SELECT final_hash
		 FROM care_journals
		 WHERE id = $1`,
		journalID,
	).Scan(&finalHash)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return IntegrityReport{}, ErrJournalNotFound
		}
		return IntegrityReport{}, fmt.Errorf("load journal final hash: %w", err)
	}

	events, err := r.listIntegrityEvents(ctx, journalID)
	if err != nil {
		return IntegrityReport{}, err
	}
	report := IntegrityReport{
		JournalID:                  journalID,
		Status:                     IntegrityStatusValid,
		Valid:                      true,
		EventsCount:                len(events),
		JournalFinalHash:           nullStringPointer(finalHash),
		FinalHashMatches:           true,
		Issues:                     []string{},
		SignatureVerificationScope: "enabled",
	}

	var previousHash *string
	for _, event := range events {
		if !event.EventHash.Valid {
			report.UnhashedEventsCount++
			report.HasLegacyUnhashedEvents = true
			continue
		}

		report.HashedEventsCount++
		expectedPreviousHash := ""
		actualPreviousHash := ""
		if previousHash != nil {
			expectedPreviousHash = *previousHash
		}
		if event.PreviousHash.Valid {
			actualPreviousHash = event.PreviousHash.String
		}
		if expectedPreviousHash != actualPreviousHash {
			report.addIntegrityIssue(event.ID, "broken previous_hash chain")
		}

		calculatedHash, err := hashJournalEvent(canonicalJournalEventPayload{
			EventType:    JournalEventType(event.EventType),
			JournalID:    event.JournalID,
			StepID:       event.StepID.String,
			ActorID:      event.ActorID,
			ActorRole:    JournalActorRole(event.ActorRole),
			PayloadJSON:  event.PayloadJSON,
			PreviousHash: nullStringPointer(event.PreviousHash),
			CreatedAt:    event.CreatedAt,
		})
		if err != nil {
			report.addIntegrityIssue(event.ID, "failed to recalculate event hash")
		} else if calculatedHash != event.EventHash.String {
			report.addIntegrityIssue(event.ID, "event_hash mismatch")
		}

		r.verifyIntegrityEventSignature(ctx, &report, event)

		currentHash := event.EventHash.String
		previousHash = &currentHash
		report.LastHash = &currentHash
	}

	if !stringPointersEqual(report.LastHash, report.JournalFinalHash) {
		report.FinalHashMatches = false
		report.addIntegrityIssue("", "journal final_hash does not match last event_hash")
	}

	if len(report.Issues) > 0 {
		report.Valid = false
		report.Status = IntegrityStatusInvalid
		return report, nil
	}
	if report.HasLegacyUnhashedEvents || report.UnsignedHashedEventsCount > 0 {
		report.Status = IntegrityStatusPartial
	}
	return report, nil
}

type integrityEventRecord struct {
	ID           string
	JournalID    string
	StepID       sql.NullString
	EventType    string
	ActorID      string
	ActorRole    string
	PayloadJSON  json.RawMessage
	PreviousHash sql.NullString
	EventHash    sql.NullString
	SigningKeyID sql.NullString
	Signature    sql.NullString
	CreatedAt    time.Time
}

func (r *PostgresRepository) verifyIntegrityEventSignature(ctx context.Context, report *IntegrityReport, event integrityEventRecord) {
	hasSigningKey := event.SigningKeyID.Valid && strings.TrimSpace(event.SigningKeyID.String) != ""
	hasSignature := event.Signature.Valid && strings.TrimSpace(event.Signature.String) != ""
	if !hasSigningKey && !hasSignature {
		report.UnsignedHashedEventsCount++
		return
	}
	if !hasSigningKey || !hasSignature {
		report.InvalidSignaturesCount++
		report.addIntegrityIssue(event.ID, "incomplete signature metadata")
		return
	}

	report.SignedEventsCount++
	key, err := r.signingKeyForIntegrity(ctx, event.SigningKeyID.String)
	if err != nil {
		report.InvalidSignaturesCount++
		report.addIntegrityIssue(event.ID, "signing key not found")
		return
	}
	if key.UserID != event.ActorID {
		report.InvalidSignaturesCount++
		report.addIntegrityIssue(event.ID, "signing key does not belong to event actor")
		return
	}
	if key.Status != SigningKeyStatusActive {
		report.InvalidSignaturesCount++
		report.addIntegrityIssue(event.ID, "signing key is not active")
		return
	}
	if key.Algorithm != SigningKeyAlgorithmEd25519 {
		report.InvalidSignaturesCount++
		report.addIntegrityIssue(event.ID, "unsupported signature algorithm")
		return
	}
	if err := verifyEd25519Signature(key.PublicKey, event.EventHash.String, event.Signature.String); err != nil {
		report.InvalidSignaturesCount++
		report.addIntegrityIssue(event.ID, "signature verification failed")
		return
	}
	report.ValidSignaturesCount++
}

func (r *PostgresRepository) signingKeyForIntegrity(ctx context.Context, signingKeyID string) (SigningKey, error) {
	var key SigningKey
	var algorithm string
	var status string
	var revokedAt sql.NullTime
	err := r.db.QueryRowContext(
		ctx,
		`SELECT id::text,
		        user_id::text,
		        public_key,
		        algorithm,
		        key_fingerprint,
		        status,
		        created_at,
		        revoked_at
		 FROM user_signing_keys
		 WHERE id = $1
		 LIMIT 1`,
		signingKeyID,
	).Scan(
		&key.ID,
		&key.UserID,
		&key.PublicKey,
		&algorithm,
		&key.KeyFingerprint,
		&status,
		&key.CreatedAt,
		&revokedAt,
	)
	if err != nil {
		return SigningKey{}, err
	}
	if revokedAt.Valid {
		key.RevokedAt = &revokedAt.Time
	}
	key.Algorithm = algorithm
	key.Status = SigningKeyStatus(status)
	return key, nil
}

func (r *PostgresRepository) listIntegrityEvents(ctx context.Context, journalID string) ([]integrityEventRecord, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id::text,
		        journal_id::text,
		        step_id::text,
		        event_type,
		        actor_id::text,
		        actor_role,
		        payload_json::text,
		        previous_hash,
		        event_hash,
		        signing_key_id::text,
		        signature,
		        created_at
		 FROM care_journal_events
		 WHERE journal_id = $1
		 ORDER BY created_at ASC, id ASC`,
		journalID,
	)
	if err != nil {
		return nil, fmt.Errorf("list journal events for integrity: %w", err)
	}
	defer rows.Close()

	var events []integrityEventRecord
	for rows.Next() {
		var event integrityEventRecord
		var payload string
		if err := rows.Scan(
			&event.ID,
			&event.JournalID,
			&event.StepID,
			&event.EventType,
			&event.ActorID,
			&event.ActorRole,
			&payload,
			&event.PreviousHash,
			&event.EventHash,
			&event.SigningKeyID,
			&event.Signature,
			&event.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan journal event for integrity: %w", err)
		}
		event.PayloadJSON = json.RawMessage(payload)
		events = append(events, event)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate journal events for integrity: %w", err)
	}
	if events == nil {
		events = []integrityEventRecord{}
	}
	return events, nil
}

func (r *IntegrityReport) addIntegrityIssue(eventID string, issue string) {
	if eventID != "" && r.FirstInvalidEventID == nil {
		r.FirstInvalidEventID = &eventID
	}
	r.Issues = append(r.Issues, issue)
}

func stringPointersEqual(left *string, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

func nullStringPointer(value sql.NullString) *string {
	if !value.Valid {
		return nil
	}
	return &value.String
}

func (r *PostgresRepository) ConfirmStep(ctx context.Context, journalID string, stepID string, clientID string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin confirm journal step: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var journalClientID string
	var journalStatus string
	err = tx.QueryRowContext(
		ctx,
		`SELECT client_id::text,
		        COALESCE(status, 'active')
		 FROM care_journals
		 WHERE id = $1
		 FOR UPDATE`,
		journalID,
	).Scan(&journalClientID, &journalStatus)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrJournalNotFound
		}
		return fmt.Errorf("load journal for step confirmation: %w", err)
	}
	if journalClientID != clientID {
		return ErrForbidden
	}
	if !journalStatusAllowsStepConfirmation(journalStatus) {
		return ErrNotReady
	}

	if err = r.ensureProtectedStepsForJournal(ctx, tx, journalID); err != nil {
		return err
	}

	target, err := r.resolveStepConfirmationTarget(ctx, tx, journalID, stepID)
	if err != nil {
		return err
	}

	createdAt := time.Now().UTC().Truncate(time.Microsecond)
	if err = validateProtectedStepConfirmation(target, createdAt); err != nil {
		return err
	}
	if target.Status != JournalStepStatusCompletedByClient {
		preparedEvent, err := r.prepareStepCompletedEventForConfirm(ctx, tx, journalID, target, clientID, createdAt)
		if err != nil {
			return err
		}
		result, err := tx.ExecContext(
			ctx,
			`UPDATE care_journal_steps
			 SET status = 'completed_by_client',
			     completed_at = $2,
			     completed_by_client_id = $3
			 WHERE id = $1
			   AND status = 'pending'`,
			target.ProtectedStepID,
			createdAt,
			clientID,
		)
		if err != nil {
			return fmt.Errorf("complete protected journal step: %w", err)
		}
		rowsAffected, err := result.RowsAffected()
		if err != nil {
			return fmt.Errorf("read protected step completion rows: %w", err)
		}
		if rowsAffected == 0 {
			return ErrNotReady
		}
		if err = r.appendPreparedStepCompletedEvent(ctx, tx, journalID, target, clientID, createdAt, preparedEvent); err != nil {
			return err
		}
	}

	if target.RecommendationID != "" {
		if err = r.insertLegacyStepConfirmationEntry(ctx, tx, journalID, target, clientID, createdAt); err != nil {
			return err
		}
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit step confirmation: %w", err)
	}
	committed = true
	return nil
}

func (r *PostgresRepository) PrepareStepConfirmation(ctx context.Context, journalID string, stepID string, clientID string) (StepConfirmationPrepare, error) {
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return StepConfirmationPrepare{}, fmt.Errorf("begin prepare journal step confirmation: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	var journalClientID string
	var journalStatus string
	err = tx.QueryRowContext(
		ctx,
		`SELECT client_id::text,
		        COALESCE(status, 'active')
		 FROM care_journals
		 WHERE id = $1`,
		journalID,
	).Scan(&journalClientID, &journalStatus)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return StepConfirmationPrepare{}, ErrJournalNotFound
		}
		return StepConfirmationPrepare{}, fmt.Errorf("load journal for step confirmation prepare: %w", err)
	}
	if journalClientID != clientID {
		return StepConfirmationPrepare{}, ErrForbidden
	}
	if !journalStatusAllowsStepConfirmation(journalStatus) {
		return StepConfirmationPrepare{}, ErrNotReady
	}

	target, err := r.resolveStepConfirmationTargetReadOnly(ctx, tx, journalID, stepID)
	if err != nil {
		return StepConfirmationPrepare{}, err
	}

	completedAt := time.Now().UTC().Truncate(time.Microsecond)
	if err = validateProtectedStepPreparation(target, completedAt); err != nil {
		return StepConfirmationPrepare{}, err
	}

	signingKey, err := r.activeSigningKey(ctx, tx, clientID)
	if err != nil {
		return StepConfirmationPrepare{}, err
	}

	var deadlineAt *time.Time
	if target.DeadlineAt.Valid {
		value := target.DeadlineAt.Time
		deadlineAt = &value
	}
	payload := stepCompletedEventPayload{
		JournalID:              journalID,
		StepID:                 target.ProtectedStepID,
		LegacyRecommendationID: target.RecommendationID,
		CompletedAt:            completedAt,
		CompletedByClientID:    clientID,
		DeadlineAt:             deadlineAt,
		EventType:              JournalEventTypeStepCompletedByClient,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return StepConfirmationPrepare{}, fmt.Errorf("marshal protected step completion prepare payload: %w", err)
	}

	previousHash, err := r.lastJournalEventHash(ctx, tx, journalID)
	if err != nil {
		return StepConfirmationPrepare{}, err
	}
	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:    JournalEventTypeStepCompletedByClient,
		JournalID:    journalID,
		StepID:       target.ProtectedStepID,
		ActorID:      clientID,
		ActorRole:    JournalActorRoleClient,
		PayloadJSON:  json.RawMessage(payloadBytes),
		PreviousHash: previousHash,
		CreatedAt:    completedAt,
	})
	if err != nil {
		return StepConfirmationPrepare{}, fmt.Errorf("hash protected journal event prepare: %w", err)
	}

	return StepConfirmationPrepare{
		JournalID:              journalID,
		StepID:                 target.ProtectedStepID,
		LegacyRecommendationID: target.RecommendationID,
		EventType:              JournalEventTypeStepCompletedByClient,
		ActorID:                clientID,
		ActorRole:              JournalActorRoleClient,
		SigningKeyID:           signingKey.ID,
		KeyFingerprint:         signingKey.KeyFingerprint,
		PreviousHash:           previousHash,
		EventHashToSign:        eventHash,
		CompletedAt:            completedAt,
		DeadlineAt:             deadlineAt,
		SignatureAlgorithm:     SigningKeyAlgorithmEd25519,
		SignatureInput:         "lowercase_hex_event_hash",
	}, nil
}

func (r *PostgresRepository) CommitStepConfirmation(ctx context.Context, journalID string, stepID string, clientID string, request StepConfirmationCommit) error {
	if err := validateStepConfirmationCommitRequest(request); err != nil {
		return err
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin signed journal step confirmation: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var journalClientID string
	var journalStatus string
	err = tx.QueryRowContext(
		ctx,
		`SELECT client_id::text,
		        COALESCE(status, 'active')
		 FROM care_journals
		 WHERE id = $1
		 FOR UPDATE`,
		journalID,
	).Scan(&journalClientID, &journalStatus)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrJournalNotFound
		}
		return fmt.Errorf("load journal for signed step confirmation: %w", err)
	}
	if journalClientID != clientID {
		return ErrForbidden
	}
	if !journalStatusAllowsStepConfirmation(journalStatus) {
		return ErrNotReady
	}

	if err = r.ensureProtectedStepsForJournal(ctx, tx, journalID); err != nil {
		return err
	}

	target, err := r.resolveStepConfirmationTarget(ctx, tx, journalID, stepID)
	if err != nil {
		return err
	}

	if target.Status == JournalStepStatusCompletedByClient {
		ok, err := r.signedStepCompletionAlreadyExists(ctx, tx, journalID, target.ProtectedStepID, request)
		if err != nil {
			return err
		}
		if ok {
			if err = tx.Commit(); err != nil {
				return fmt.Errorf("commit idempotent signed step confirmation: %w", err)
			}
			committed = true
			return nil
		}
		return ErrNotReady
	}
	if err = validateProtectedStepPreparation(target, time.Now().UTC().Truncate(time.Microsecond)); err != nil {
		return err
	}

	completedAt := request.CompletedAt.UTC().Truncate(time.Microsecond)
	payloadBytes, err := stepCompletedPayloadBytes(journalID, target, clientID, completedAt)
	if err != nil {
		return err
	}

	previousHash, err := r.lastJournalEventHash(ctx, tx, journalID)
	if err != nil {
		return err
	}
	if !stringPointersEqual(previousHash, normalizeOptionalHash(request.PreviousHash)) {
		return ErrNotReady
	}

	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:    JournalEventTypeStepCompletedByClient,
		JournalID:    journalID,
		StepID:       target.ProtectedStepID,
		ActorID:      clientID,
		ActorRole:    JournalActorRoleClient,
		PayloadJSON:  json.RawMessage(payloadBytes),
		PreviousHash: previousHash,
		CreatedAt:    completedAt,
	})
	if err != nil {
		return fmt.Errorf("hash signed protected journal event: %w", err)
	}
	if eventHash != strings.TrimSpace(request.EventHashToSign) {
		return ErrNotReady
	}

	signingKey, err := r.activeSigningKeyByID(ctx, tx, strings.TrimSpace(request.SigningKeyID), clientID)
	if err != nil {
		return err
	}
	if err = verifyEd25519Signature(signingKey.PublicKey, request.EventHashToSign, request.Signature); err != nil {
		return err
	}

	result, err := tx.ExecContext(
		ctx,
		`UPDATE care_journal_steps
		 SET status = 'completed_by_client',
		     completed_at = $2,
		     completed_by_client_id = $3
		 WHERE id = $1
		   AND status = 'pending'`,
		target.ProtectedStepID,
		completedAt,
		clientID,
	)
	if err != nil {
		return fmt.Errorf("complete signed protected journal step: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("read signed protected step completion rows: %w", err)
	}
	if rowsAffected == 0 {
		return ErrNotReady
	}

	if err = r.appendSignedStepCompletedEvent(ctx, tx, journalID, target, clientID, completedAt, payloadBytes, previousHash, signingKey.ID, request.Signature, eventHash); err != nil {
		return err
	}
	if err = r.insertLegacyStepConfirmationEntry(ctx, tx, journalID, target, clientID, completedAt); err != nil {
		return err
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit signed step confirmation: %w", err)
	}
	committed = true
	return nil
}

type clientUnavailabilityNoticePayload struct {
	JournalID        string           `json:"journal_id"`
	UnavailableFrom  time.Time        `json:"unavailable_from"`
	UnavailableUntil time.Time        `json:"unavailable_until"`
	Reason           string           `json:"reason,omitempty"`
	Comment          string           `json:"comment,omitempty"`
	EventType        JournalEventType `json:"event_type"`
	CreatedAt        time.Time        `json:"created_at"`
}

func (r *PostgresRepository) CreateClientUnavailabilityNotice(ctx context.Context, journalID string, clientID string, input ClientUnavailabilityNoticeInput) (JournalEventResult, error) {
	normalized, err := normalizeClientUnavailabilityNoticeInput(input)
	if err != nil {
		return JournalEventResult{}, err
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return JournalEventResult{}, fmt.Errorf("begin client unavailability notice: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var journalClientID string
	var journalStatus string
	err = tx.QueryRowContext(
		ctx,
		`SELECT client_id::text,
		        COALESCE(status, 'active')
		 FROM care_journals
		 WHERE id = $1
		 FOR UPDATE`,
		journalID,
	).Scan(&journalClientID, &journalStatus)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return JournalEventResult{}, ErrJournalNotFound
		}
		return JournalEventResult{}, fmt.Errorf("load journal for client unavailability notice: %w", err)
	}
	if journalClientID != clientID {
		return JournalEventResult{}, ErrForbidden
	}
	if !journalStatusAllowsClientProtectedEvent(journalStatus) {
		return JournalEventResult{}, ErrNotReady
	}

	createdAt := time.Now().UTC().Truncate(time.Microsecond)
	payload := clientUnavailabilityNoticePayload{
		JournalID:        journalID,
		UnavailableFrom:  normalized.UnavailableFrom,
		UnavailableUntil: normalized.UnavailableUntil,
		Reason:           normalized.Reason,
		Comment:          normalized.Comment,
		EventType:        JournalEventTypeClientUnavailabilityNoticeAdded,
		CreatedAt:        createdAt,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return JournalEventResult{}, fmt.Errorf("marshal client unavailability notice payload: %w", err)
	}

	previousHash, err := r.lastJournalEventHash(ctx, tx, journalID)
	if err != nil {
		return JournalEventResult{}, err
	}
	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:    JournalEventTypeClientUnavailabilityNoticeAdded,
		JournalID:    journalID,
		ActorID:      clientID,
		ActorRole:    JournalActorRoleClient,
		PayloadJSON:  json.RawMessage(payloadBytes),
		PreviousHash: previousHash,
		CreatedAt:    createdAt,
	})
	if err != nil {
		return JournalEventResult{}, fmt.Errorf("hash client unavailability notice event: %w", err)
	}

	var signingKeyID *string
	var signatureBase64 *string
	signingKey, found, err := r.activeBackendManagedSigningKey(ctx, tx, clientID)
	if err != nil {
		return JournalEventResult{}, err
	}
	if found {
		signature, err := r.signBackendManagedJournalEvent(signingKey, eventHash)
		if err != nil {
			return JournalEventResult{}, err
		}
		signingKeyID = &signingKey.ID
		signatureBase64 = &signature
	} else {
		log.Printf("journal backend-managed signing: legacy unsigned unavailability notice fallback for user %s because encrypted private key is missing", clientID)
	}

	var eventID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_events (
		   journal_id, step_id, event_type, actor_id, actor_role,
		   payload_json, reason, previous_hash, event_hash, signing_key_id, signature, created_at
		 )
		 VALUES (
		   $1, NULL, 'client_unavailability_notice_added', $2, 'client',
		   $3::jsonb, $4, $5, $6, $7, $8, $9
		 )
		 RETURNING id::text`,
		journalID,
		clientID,
		string(payloadBytes),
		nullableStringValue(emptyStringAsNil(normalized.Reason)),
		nullableStringValue(previousHash),
		eventHash,
		nullableStringValue(signingKeyID),
		nullableStringValue(signatureBase64),
		createdAt,
	).Scan(&eventID)
	if err != nil {
		return JournalEventResult{}, fmt.Errorf("append client unavailability notice event: %w", err)
	}

	if _, err = tx.ExecContext(
		ctx,
		`UPDATE care_journals
		 SET final_hash = $2
		 WHERE id = $1`,
		journalID,
		eventHash,
	); err != nil {
		return JournalEventResult{}, fmt.Errorf("update journal final hash for unavailability notice: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return JournalEventResult{}, fmt.Errorf("commit client unavailability notice: %w", err)
	}
	committed = true
	return JournalEventResult{
		EventID:   eventID,
		JournalID: journalID,
		EventType: JournalEventTypeClientUnavailabilityNoticeAdded,
		CreatedAt: createdAt,
		Signed:    signingKeyID != nil && signatureBase64 != nil,
	}, nil
}

type clientProblemReportPayload struct {
	JournalID string           `json:"journal_id"`
	Reason    string           `json:"reason"`
	Comment   string           `json:"comment,omitempty"`
	EventType JournalEventType `json:"event_type"`
	CreatedAt time.Time        `json:"created_at"`
}

func (r *PostgresRepository) CreateClientProblemReport(ctx context.Context, journalID string, clientID string, input ClientProblemReportInput) (JournalEventResult, error) {
	normalized, err := normalizeClientProblemReportInput(input)
	if err != nil {
		return JournalEventResult{}, err
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return JournalEventResult{}, fmt.Errorf("begin client problem report: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var journalClientID string
	var journalStatus string
	err = tx.QueryRowContext(
		ctx,
		`SELECT client_id::text,
		        COALESCE(status, 'active')
		 FROM care_journals
		 WHERE id = $1
		 FOR UPDATE`,
		journalID,
	).Scan(&journalClientID, &journalStatus)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return JournalEventResult{}, ErrJournalNotFound
		}
		return JournalEventResult{}, fmt.Errorf("load journal for client problem report: %w", err)
	}
	if journalClientID != clientID {
		return JournalEventResult{}, ErrForbidden
	}
	if !journalStatusAllowsClientProtectedEvent(journalStatus) {
		return JournalEventResult{}, ErrNotReady
	}

	createdAt := time.Now().UTC().Truncate(time.Microsecond)
	payload := clientProblemReportPayload{
		JournalID: journalID,
		Reason:    normalized.Reason,
		Comment:   normalized.Comment,
		EventType: JournalEventTypeClientProblemReported,
		CreatedAt: createdAt,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return JournalEventResult{}, fmt.Errorf("marshal client problem report payload: %w", err)
	}

	previousHash, err := r.lastJournalEventHash(ctx, tx, journalID)
	if err != nil {
		return JournalEventResult{}, err
	}
	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:    JournalEventTypeClientProblemReported,
		JournalID:    journalID,
		ActorID:      clientID,
		ActorRole:    JournalActorRoleClient,
		PayloadJSON:  json.RawMessage(payloadBytes),
		PreviousHash: previousHash,
		CreatedAt:    createdAt,
	})
	if err != nil {
		return JournalEventResult{}, fmt.Errorf("hash client problem report event: %w", err)
	}

	var signingKeyID *string
	var signatureBase64 *string
	signingKey, found, err := r.activeBackendManagedSigningKey(ctx, tx, clientID)
	if err != nil {
		return JournalEventResult{}, err
	}
	if found {
		signature, err := r.signBackendManagedJournalEvent(signingKey, eventHash)
		if err != nil {
			return JournalEventResult{}, err
		}
		signingKeyID = &signingKey.ID
		signatureBase64 = &signature
	} else {
		log.Printf("journal backend-managed signing: legacy unsigned client problem report fallback for user %s because encrypted private key is missing", clientID)
	}

	var eventID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_events (
		   journal_id, step_id, event_type, actor_id, actor_role,
		   payload_json, reason, previous_hash, event_hash, signing_key_id, signature, created_at
		 )
		 VALUES (
		   $1, NULL, 'client_problem_reported', $2, 'client',
		   $3::jsonb, $4, $5, $6, $7, $8, $9
		 )
		 RETURNING id::text`,
		journalID,
		clientID,
		string(payloadBytes),
		nullableStringValue(emptyStringAsNil(normalized.Reason)),
		nullableStringValue(previousHash),
		eventHash,
		nullableStringValue(signingKeyID),
		nullableStringValue(signatureBase64),
		createdAt,
	).Scan(&eventID)
	if err != nil {
		return JournalEventResult{}, fmt.Errorf("append client problem report event: %w", err)
	}

	if _, err = tx.ExecContext(
		ctx,
		`UPDATE care_journals
		 SET final_hash = $2
		 WHERE id = $1`,
		journalID,
		eventHash,
	); err != nil {
		return JournalEventResult{}, fmt.Errorf("update journal final hash for client problem report: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return JournalEventResult{}, fmt.Errorf("commit client problem report: %w", err)
	}
	committed = true
	return JournalEventResult{
		EventID:   eventID,
		JournalID: journalID,
		EventType: JournalEventTypeClientProblemReported,
		CreatedAt: createdAt,
		Signed:    signingKeyID != nil && signatureBase64 != nil,
	}, nil
}

type deadlineExtensionPayload struct {
	JournalID                 string           `json:"journal_id"`
	StepID                    string           `json:"step_id"`
	OldDeadlineAt             *time.Time       `json:"old_deadline_at"`
	NewDeadlineAt             time.Time        `json:"new_deadline_at"`
	Reason                    string           `json:"reason"`
	LinkedClientNoticeEventID *string          `json:"linked_client_notice_event_id,omitempty"`
	EventType                 JournalEventType `json:"event_type"`
	CreatedAt                 time.Time        `json:"created_at"`
}

func (r *PostgresRepository) CreateDeadlineExtension(ctx context.Context, journalID string, stepID string, masterID string, input DeadlineExtensionInput) (DeadlineExtensionResult, error) {
	normalized, err := normalizeDeadlineExtensionInput(input)
	if err != nil {
		return DeadlineExtensionResult{}, err
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return DeadlineExtensionResult{}, fmt.Errorf("begin deadline extension: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var journalMasterID string
	var journalStatus string
	err = tx.QueryRowContext(
		ctx,
		`SELECT master_id::text,
		        COALESCE(status, 'active')
		 FROM care_journals
		 WHERE id = $1
		 FOR UPDATE`,
		journalID,
	).Scan(&journalMasterID, &journalStatus)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return DeadlineExtensionResult{}, ErrJournalNotFound
		}
		return DeadlineExtensionResult{}, fmt.Errorf("load journal for deadline extension: %w", err)
	}
	if journalMasterID != masterID {
		return DeadlineExtensionResult{}, ErrForbidden
	}
	if !journalStatusAllowsClientProtectedEvent(journalStatus) {
		return DeadlineExtensionResult{}, ErrNotReady
	}

	if err = r.ensureProtectedStepsForJournal(ctx, tx, journalID); err != nil {
		return DeadlineExtensionResult{}, err
	}

	target, err := r.resolveStepConfirmationTarget(ctx, tx, journalID, stepID)
	if err != nil {
		return DeadlineExtensionResult{}, err
	}
	oldDeadlineAt, err := validateDeadlineExtensionTarget(target, normalized.NewDeadlineAt)
	if err != nil {
		return DeadlineExtensionResult{}, err
	}
	if normalized.LinkedClientNoticeEventID != nil {
		if err = r.validateLinkedClientMessageEvent(ctx, tx, journalID, *normalized.LinkedClientNoticeEventID); err != nil {
			return DeadlineExtensionResult{}, err
		}
	}

	createdAt := time.Now().UTC().Truncate(time.Microsecond)
	payload := deadlineExtensionPayload{
		JournalID:                 journalID,
		StepID:                    target.ProtectedStepID,
		OldDeadlineAt:             oldDeadlineAt,
		NewDeadlineAt:             normalized.NewDeadlineAt,
		Reason:                    normalized.Reason,
		LinkedClientNoticeEventID: normalized.LinkedClientNoticeEventID,
		EventType:                 JournalEventTypeDeadlineExtended,
		CreatedAt:                 createdAt,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return DeadlineExtensionResult{}, fmt.Errorf("marshal deadline extension payload: %w", err)
	}

	previousHash, err := r.lastJournalEventHash(ctx, tx, journalID)
	if err != nil {
		return DeadlineExtensionResult{}, err
	}
	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:    JournalEventTypeDeadlineExtended,
		JournalID:    journalID,
		StepID:       target.ProtectedStepID,
		ActorID:      masterID,
		ActorRole:    JournalActorRoleMaster,
		PayloadJSON:  json.RawMessage(payloadBytes),
		PreviousHash: previousHash,
		CreatedAt:    createdAt,
	})
	if err != nil {
		return DeadlineExtensionResult{}, fmt.Errorf("hash deadline extension event: %w", err)
	}

	var signingKeyID *string
	var signatureBase64 *string
	signingKey, found, err := r.activeBackendManagedSigningKey(ctx, tx, masterID)
	if err != nil {
		return DeadlineExtensionResult{}, err
	}
	if found {
		signature, err := r.signBackendManagedJournalEvent(signingKey, eventHash)
		if err != nil {
			return DeadlineExtensionResult{}, err
		}
		signingKeyID = &signingKey.ID
		signatureBase64 = &signature
	} else {
		log.Printf("journal backend-managed signing: legacy unsigned deadline extension fallback for user %s because encrypted private key is missing", masterID)
	}

	result, err := tx.ExecContext(
		ctx,
		`UPDATE care_journal_steps
		 SET deadline_at = $2
		 WHERE id = $1
		   AND status = 'pending'`,
		target.ProtectedStepID,
		normalized.NewDeadlineAt,
	)
	if err != nil {
		return DeadlineExtensionResult{}, fmt.Errorf("update protected step deadline: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return DeadlineExtensionResult{}, fmt.Errorf("read deadline extension rows: %w", err)
	}
	if rowsAffected == 0 {
		return DeadlineExtensionResult{}, ErrNotReady
	}

	var eventID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_events (
		   journal_id, step_id, event_type, actor_id, actor_role,
		   payload_json, reason, previous_hash, event_hash, signing_key_id, signature, created_at
		 )
		 VALUES (
		   $1, $2, 'deadline_extended', $3, 'master',
		   $4::jsonb, $5, $6, $7, $8, $9, $10
		 )
		 RETURNING id::text`,
		journalID,
		target.ProtectedStepID,
		masterID,
		string(payloadBytes),
		normalized.Reason,
		nullableStringValue(previousHash),
		eventHash,
		nullableStringValue(signingKeyID),
		nullableStringValue(signatureBase64),
		createdAt,
	).Scan(&eventID)
	if err != nil {
		return DeadlineExtensionResult{}, fmt.Errorf("append deadline extension event: %w", err)
	}

	if _, err = tx.ExecContext(
		ctx,
		`UPDATE care_journals
		 SET final_hash = $2
		 WHERE id = $1`,
		journalID,
		eventHash,
	); err != nil {
		return DeadlineExtensionResult{}, fmt.Errorf("update journal final hash for deadline extension: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return DeadlineExtensionResult{}, fmt.Errorf("commit deadline extension: %w", err)
	}
	committed = true
	return DeadlineExtensionResult{
		EventID:                   eventID,
		JournalID:                 journalID,
		StepID:                    target.ProtectedStepID,
		EventType:                 JournalEventTypeDeadlineExtended,
		OldDeadlineAt:             oldDeadlineAt,
		NewDeadlineAt:             normalized.NewDeadlineAt,
		LinkedClientNoticeEventID: normalized.LinkedClientNoticeEventID,
		CreatedAt:                 createdAt,
		Signed:                    signingKeyID != nil && signatureBase64 != nil,
	}, nil
}

type journalStopPayload struct {
	JournalID                 string           `json:"journal_id"`
	Reason                    string           `json:"reason"`
	StopCategory              string           `json:"stop_category"`
	LinkedClientNoticeEventID *string          `json:"linked_client_notice_event_id,omitempty"`
	StoppedAt                 time.Time        `json:"stopped_at"`
	EventType                 JournalEventType `json:"event_type"`
}

func (r *PostgresRepository) StopJournal(ctx context.Context, journalID string, masterID string, input JournalStopInput) (JournalStopResult, error) {
	normalized, err := normalizeJournalStopInput(input)
	if err != nil {
		return JournalStopResult{}, err
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return JournalStopResult{}, fmt.Errorf("begin journal stop: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var journalMasterID string
	var journalStatus string
	err = tx.QueryRowContext(
		ctx,
		`SELECT master_id::text,
		        COALESCE(status, 'active')
		 FROM care_journals
		 WHERE id = $1
		 FOR UPDATE`,
		journalID,
	).Scan(&journalMasterID, &journalStatus)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return JournalStopResult{}, ErrJournalNotFound
		}
		return JournalStopResult{}, fmt.Errorf("load journal for stop: %w", err)
	}
	if journalMasterID != masterID {
		return JournalStopResult{}, ErrForbidden
	}
	if !journalStatusAllowsClientProtectedEvent(journalStatus) {
		return JournalStopResult{}, ErrNotReady
	}
	if normalized.LinkedClientNoticeEventID != nil {
		if err = r.validateLinkedClientMessageEvent(ctx, tx, journalID, *normalized.LinkedClientNoticeEventID); err != nil {
			if errors.Is(err, ErrInvalidDeadline) {
				return JournalStopResult{}, ErrInvalidStop
			}
			return JournalStopResult{}, err
		}
	}

	stoppedAt := time.Now().UTC().Truncate(time.Microsecond)
	payload := journalStopPayload{
		JournalID:                 journalID,
		Reason:                    normalized.Reason,
		StopCategory:              normalized.StopCategory,
		LinkedClientNoticeEventID: normalized.LinkedClientNoticeEventID,
		StoppedAt:                 stoppedAt,
		EventType:                 JournalEventTypeJournalStopped,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return JournalStopResult{}, fmt.Errorf("marshal journal stop payload: %w", err)
	}

	previousHash, err := r.lastJournalEventHash(ctx, tx, journalID)
	if err != nil {
		return JournalStopResult{}, err
	}
	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:    JournalEventTypeJournalStopped,
		JournalID:    journalID,
		ActorID:      masterID,
		ActorRole:    JournalActorRoleMaster,
		PayloadJSON:  json.RawMessage(payloadBytes),
		PreviousHash: previousHash,
		CreatedAt:    stoppedAt,
	})
	if err != nil {
		return JournalStopResult{}, fmt.Errorf("hash journal stop event: %w", err)
	}

	var signingKeyID *string
	var signatureBase64 *string
	signingKey, found, err := r.activeBackendManagedSigningKey(ctx, tx, masterID)
	if err != nil {
		return JournalStopResult{}, err
	}
	if found {
		signature, err := r.signBackendManagedJournalEvent(signingKey, eventHash)
		if err != nil {
			return JournalStopResult{}, err
		}
		signingKeyID = &signingKey.ID
		signatureBase64 = &signature
	} else {
		log.Printf("journal backend-managed signing: legacy unsigned journal stop fallback for user %s because encrypted private key is missing", masterID)
	}

	result, err := tx.ExecContext(
		ctx,
		`UPDATE care_journals
		 SET status = 'stopped',
		     stopped_at = $2,
		     stop_reason = $3
		 WHERE id = $1
		   AND status = 'active'`,
		journalID,
		stoppedAt,
		normalized.Reason,
	)
	if err != nil {
		return JournalStopResult{}, fmt.Errorf("mark journal stopped: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return JournalStopResult{}, fmt.Errorf("read journal stop rows: %w", err)
	}
	if rowsAffected == 0 {
		return JournalStopResult{}, ErrNotReady
	}

	cancelResult, err := tx.ExecContext(
		ctx,
		`UPDATE care_journal_steps
		 SET status = 'cancelled_due_to_journal_stop'
		 WHERE journal_id = $1
		   AND status = 'pending'`,
		journalID,
	)
	if err != nil {
		return JournalStopResult{}, fmt.Errorf("cancel pending journal steps: %w", err)
	}
	cancelledSteps, err := cancelResult.RowsAffected()
	if err != nil {
		return JournalStopResult{}, fmt.Errorf("read cancelled journal step rows: %w", err)
	}

	var eventID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_events (
		   journal_id, step_id, event_type, actor_id, actor_role,
		   payload_json, reason, previous_hash, event_hash, signing_key_id, signature, created_at
		 )
		 VALUES (
		   $1, NULL, 'journal_stopped', $2, 'master',
		   $3::jsonb, $4, $5, $6, $7, $8, $9
		 )
		 RETURNING id::text`,
		journalID,
		masterID,
		string(payloadBytes),
		normalized.Reason,
		nullableStringValue(previousHash),
		eventHash,
		nullableStringValue(signingKeyID),
		nullableStringValue(signatureBase64),
		stoppedAt,
	).Scan(&eventID)
	if err != nil {
		return JournalStopResult{}, fmt.Errorf("append journal stop event: %w", err)
	}

	if _, err = tx.ExecContext(
		ctx,
		`UPDATE care_journals
		 SET final_hash = $2
		 WHERE id = $1`,
		journalID,
		eventHash,
	); err != nil {
		return JournalStopResult{}, fmt.Errorf("update journal final hash for stop: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return JournalStopResult{}, fmt.Errorf("commit journal stop: %w", err)
	}
	committed = true
	return JournalStopResult{
		JournalID:           journalID,
		Status:              JournalStatusStopped,
		EventID:             eventID,
		StoppedAt:           stoppedAt,
		Signed:              signingKeyID != nil && signatureBase64 != nil,
		CancelledStepsCount: cancelledSteps,
	}, nil
}

type replacementJournalCreatedPayload struct {
	JournalID       string           `json:"journal_id"`
	AppointmentID   string           `json:"appointment_id"`
	ParentJournalID string           `json:"parent_journal_id"`
	RootJournalID   string           `json:"root_journal_id"`
	ParentFinalHash string           `json:"parent_final_hash"`
	Reason          string           `json:"reason"`
	VersionNumber   int              `json:"version_number"`
	EventType       JournalEventType `json:"event_type"`
	CreatedAt       time.Time        `json:"created_at"`
}

func (r *PostgresRepository) CreateReplacementJournal(ctx context.Context, parentJournalID string, masterID string, input ReplacementJournalInput) (ReplacementJournalResult, error) {
	normalized, err := normalizeReplacementJournalInput(input)
	if err != nil {
		return ReplacementJournalResult{}, err
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("begin replacement journal: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var appointmentID string
	var parentClientID string
	var parentMasterID string
	var parentStatus string
	var parentRootJournalID sql.NullString
	var replacedByJournalID sql.NullString
	var parentFinalHash sql.NullString
	err = tx.QueryRowContext(
		ctx,
		`SELECT appointment_id::text,
		        client_id::text,
		        master_id::text,
		        COALESCE(status, 'active'),
		        root_journal_id::text,
		        replaced_by_journal_id::text,
		        final_hash
		 FROM care_journals
		 WHERE id = $1
		 FOR UPDATE`,
		parentJournalID,
	).Scan(
		&appointmentID,
		&parentClientID,
		&parentMasterID,
		&parentStatus,
		&parentRootJournalID,
		&replacedByJournalID,
		&parentFinalHash,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ReplacementJournalResult{}, ErrJournalNotFound
		}
		return ReplacementJournalResult{}, fmt.Errorf("load parent journal for replacement: %w", err)
	}
	if parentMasterID != masterID {
		return ReplacementJournalResult{}, ErrForbidden
	}
	if JournalStatus(parentStatus) != JournalStatusStopped || replacedByJournalID.Valid {
		return ReplacementJournalResult{}, ErrNotReady
	}
	if !parentFinalHash.Valid || strings.TrimSpace(parentFinalHash.String) == "" {
		return ReplacementJournalResult{}, ErrNotReady
	}

	var hasOpenJournal bool
	err = tx.QueryRowContext(
		ctx,
		`SELECT EXISTS (
		   SELECT 1
		   FROM care_journals
		   WHERE appointment_id = $1
		     AND status IN ('draft', 'awaiting_client_confirmation', 'active')
		 )`,
		appointmentID,
	).Scan(&hasOpenJournal)
	if err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("check open replacement journal: %w", err)
	}
	if hasOpenJournal {
		return ReplacementJournalResult{}, ErrNotReady
	}

	rootJournalID := parentJournalID
	if parentRootJournalID.Valid && strings.TrimSpace(parentRootJournalID.String) != "" {
		rootJournalID = parentRootJournalID.String
	}

	var versionNumber int
	if err = tx.QueryRowContext(
		ctx,
		`SELECT COALESCE(MAX(version_number), 0) + 1
		 FROM care_journals
		 WHERE appointment_id = $1`,
		appointmentID,
	).Scan(&versionNumber); err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("calculate replacement journal version: %w", err)
	}

	createdAt := time.Now().UTC().Truncate(time.Microsecond)
	var newJournalID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journals (
		   appointment_id, client_id, master_id, created_by_master_id,
		   integrity_status, status, root_journal_id, parent_journal_id,
		   version_number, activated_at, replacement_reason
		 )
		 VALUES (
		   $1, $2, $3, $4,
		   FALSE, 'active', $5, $6,
		   $7, $8, $9
		 )
		 RETURNING id::text`,
		appointmentID,
		parentClientID,
		parentMasterID,
		masterID,
		rootJournalID,
		parentJournalID,
		versionNumber,
		createdAt,
		normalized.Reason,
	).Scan(&newJournalID)
	if err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("insert replacement journal: %w", err)
	}

	result, err := tx.ExecContext(
		ctx,
		`UPDATE care_journals
		 SET status = 'replaced',
		     replaced_by_journal_id = $2,
		     replacement_reason = $3
		 WHERE id = $1
		   AND status = 'stopped'
		   AND replaced_by_journal_id IS NULL`,
		parentJournalID,
		newJournalID,
		normalized.Reason,
	)
	if err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("mark parent journal replaced: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("read parent replacement rows: %w", err)
	}
	if rowsAffected == 0 {
		return ReplacementJournalResult{}, ErrNotReady
	}

	for _, step := range normalized.Steps {
		_, err = tx.ExecContext(
			ctx,
			`INSERT INTO care_journal_steps (
			   journal_id, day_number, title, description, deadline_at, status
			 )
			 VALUES ($1, $2, $3, $4, $5, 'pending')`,
			newJournalID,
			step.DayNumber,
			step.Title,
			step.Description,
			nullableTimeValue(step.DeadlineAt),
		)
		if err != nil {
			return ReplacementJournalResult{}, fmt.Errorf("insert replacement journal step: %w", err)
		}
	}

	payload := replacementJournalCreatedPayload{
		JournalID:       newJournalID,
		AppointmentID:   appointmentID,
		ParentJournalID: parentJournalID,
		RootJournalID:   rootJournalID,
		ParentFinalHash: strings.TrimSpace(parentFinalHash.String),
		Reason:          normalized.Reason,
		VersionNumber:   versionNumber,
		EventType:       JournalEventTypeReplacementJournalCreated,
		CreatedAt:       createdAt,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("marshal replacement journal payload: %w", err)
	}
	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:   JournalEventTypeReplacementJournalCreated,
		JournalID:   newJournalID,
		ActorID:     masterID,
		ActorRole:   JournalActorRoleMaster,
		PayloadJSON: json.RawMessage(payloadBytes),
		CreatedAt:   createdAt,
	})
	if err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("hash replacement journal event: %w", err)
	}

	var signingKeyID *string
	var signatureBase64 *string
	signingKey, found, err := r.activeBackendManagedSigningKey(ctx, tx, masterID)
	if err != nil {
		return ReplacementJournalResult{}, err
	}
	if found {
		signature, err := r.signBackendManagedJournalEvent(signingKey, eventHash)
		if err != nil {
			return ReplacementJournalResult{}, err
		}
		signingKeyID = &signingKey.ID
		signatureBase64 = &signature
	} else {
		log.Printf("journal backend-managed signing: legacy unsigned replacement journal fallback for user %s because encrypted private key is missing", masterID)
	}

	var eventID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_events (
		   journal_id, step_id, event_type, actor_id, actor_role,
		   payload_json, reason, previous_hash, event_hash, signing_key_id, signature, created_at
		 )
		 VALUES (
		   $1, NULL, 'replacement_journal_created', $2, 'master',
		   $3::jsonb, $4, NULL, $5, $6, $7, $8
		 )
		 RETURNING id::text`,
		newJournalID,
		masterID,
		string(payloadBytes),
		normalized.Reason,
		eventHash,
		nullableStringValue(signingKeyID),
		nullableStringValue(signatureBase64),
		createdAt,
	).Scan(&eventID)
	if err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("append replacement journal event: %w", err)
	}

	if _, err = tx.ExecContext(
		ctx,
		`UPDATE care_journals
		 SET final_hash = $2
		 WHERE id = $1`,
		newJournalID,
		eventHash,
	); err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("update replacement journal final hash: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return ReplacementJournalResult{}, fmt.Errorf("commit replacement journal: %w", err)
	}
	committed = true
	return ReplacementJournalResult{
		ParentJournalID: parentJournalID,
		NewJournalID:    newJournalID,
		RootJournalID:   rootJournalID,
		AppointmentID:   appointmentID,
		VersionNumber:   versionNumber,
		StepsCreated:    len(normalized.Steps),
		EventID:         eventID,
		ParentFinalHash: strings.TrimSpace(parentFinalHash.String),
		CreatedAt:       createdAt,
		Signed:          signingKeyID != nil && signatureBase64 != nil,
	}, nil
}

func (r *PostgresRepository) activeSigningKey(ctx context.Context, tx *sql.Tx, userID string) (SigningKey, error) {
	var key SigningKey
	var algorithm string
	var status string
	var revokedAt sql.NullTime
	err := tx.QueryRowContext(
		ctx,
		`SELECT id::text,
		        user_id::text,
		        public_key,
		        algorithm,
		        key_fingerprint,
		        status,
		        created_at,
		        revoked_at
		 FROM user_signing_keys
		 WHERE user_id = $1
		   AND algorithm = 'ed25519'
		   AND status = 'active'
		 ORDER BY created_at DESC, id DESC
		 LIMIT 1`,
		userID,
	).Scan(
		&key.ID,
		&key.UserID,
		&key.PublicKey,
		&algorithm,
		&key.KeyFingerprint,
		&status,
		&key.CreatedAt,
		&revokedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return SigningKey{}, ErrSigningKeyNotFound
		}
		return SigningKey{}, fmt.Errorf("load active signing key: %w", err)
	}
	if revokedAt.Valid {
		key.RevokedAt = &revokedAt.Time
	}
	key.Algorithm = algorithm
	key.Status = SigningKeyStatus(status)
	return key, nil
}

type backendManagedSigningKey struct {
	SigningKey
	EncryptedPrivateKey string
}

func (r *PostgresRepository) activeBackendManagedSigningKey(ctx context.Context, tx *sql.Tx, userID string) (backendManagedSigningKey, bool, error) {
	var key backendManagedSigningKey
	var algorithm string
	var status string
	var revokedAt sql.NullTime
	err := tx.QueryRowContext(
		ctx,
		`SELECT id::text,
		        user_id::text,
		        public_key,
		        algorithm,
		        key_fingerprint,
		        status,
		        created_at,
		        revoked_at,
		        encrypted_private_key
		 FROM user_signing_keys
		 WHERE user_id = $1
		   AND algorithm = 'ed25519'
		   AND status = 'active'
		   AND encrypted_private_key IS NOT NULL
		   AND btrim(encrypted_private_key) <> ''
		 ORDER BY private_key_encrypted_at DESC NULLS LAST, created_at DESC, id DESC
		 LIMIT 1`,
		userID,
	).Scan(
		&key.ID,
		&key.UserID,
		&key.PublicKey,
		&algorithm,
		&key.KeyFingerprint,
		&status,
		&key.CreatedAt,
		&revokedAt,
		&key.EncryptedPrivateKey,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return backendManagedSigningKey{}, false, nil
		}
		return backendManagedSigningKey{}, false, fmt.Errorf("load active backend-managed signing key: %w", err)
	}
	if revokedAt.Valid {
		key.RevokedAt = &revokedAt.Time
	}
	key.Algorithm = algorithm
	key.Status = SigningKeyStatus(status)
	return key, true, nil
}

func (r *PostgresRepository) signBackendManagedJournalEvent(key backendManagedSigningKey, eventHash string) (string, error) {
	protector, err := r.privateKeyProtector()
	if err != nil {
		return "", err
	}

	privateKeyBase64, err := protector.DecryptPrivateKey(key.EncryptedPrivateKey, key.UserID, key.KeyFingerprint, key.Algorithm)
	if err != nil {
		return "", fmt.Errorf("decrypt backend-managed journal signing key: %w", err)
	}
	rawPrivateKey, err := base64.StdEncoding.DecodeString(strings.TrimSpace(privateKeyBase64))
	if err != nil {
		return "", fmt.Errorf("decode backend-managed journal private key: %w", err)
	}
	if len(rawPrivateKey) != ed25519.PrivateKeySize {
		return "", fmt.Errorf("invalid backend-managed journal private key length: got %d, want %d", len(rawPrivateKey), ed25519.PrivateKeySize)
	}

	signature := ed25519.Sign(ed25519.PrivateKey(rawPrivateKey), []byte(strings.TrimSpace(eventHash)))
	return base64.StdEncoding.EncodeToString(signature), nil
}

func (r *PostgresRepository) privateKeyProtector() (*platformcrypto.PrivateKeyProtector, error) {
	protector, err := platformcrypto.NewPrivateKeyProtector(r.signingConfig.EncryptionKey, r.signingConfig.EncryptionKeyID)
	if err != nil {
		return nil, fmt.Errorf("create backend-managed journal private key protector: %w", err)
	}
	return protector, nil
}

func (r *PostgresRepository) activeSigningKeyByID(ctx context.Context, tx *sql.Tx, signingKeyID string, userID string) (SigningKey, error) {
	var key SigningKey
	var algorithm string
	var status string
	var revokedAt sql.NullTime
	err := tx.QueryRowContext(
		ctx,
		`SELECT id::text,
		        user_id::text,
		        public_key,
		        algorithm,
		        key_fingerprint,
		        status,
		        created_at,
		        revoked_at
		 FROM user_signing_keys
		 WHERE id = $1
		   AND user_id = $2
		   AND algorithm = 'ed25519'
		   AND status = 'active'
		 LIMIT 1`,
		signingKeyID,
		userID,
	).Scan(
		&key.ID,
		&key.UserID,
		&key.PublicKey,
		&algorithm,
		&key.KeyFingerprint,
		&status,
		&key.CreatedAt,
		&revokedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return SigningKey{}, ErrSigningKeyNotFound
		}
		return SigningKey{}, fmt.Errorf("load active signing key by id: %w", err)
	}
	if revokedAt.Valid {
		key.RevokedAt = &revokedAt.Time
	}
	key.Algorithm = algorithm
	key.Status = SigningKeyStatus(status)
	return key, nil
}

type stepConfirmationTarget struct {
	ProtectedStepID  string
	RecommendationID string
	StepNumber       int
	Status           JournalStepStatus
	DeadlineAt       sql.NullTime
}

type stepCompletedEventPayload struct {
	JournalID              string           `json:"journal_id"`
	StepID                 string           `json:"step_id"`
	LegacyRecommendationID string           `json:"legacy_recommendation_id,omitempty"`
	CompletedAt            time.Time        `json:"completed_at"`
	CompletedByClientID    string           `json:"completed_by_client_id"`
	DeadlineAt             *time.Time       `json:"deadline_at,omitempty"`
	EventType              JournalEventType `json:"event_type"`
}

type canonicalJournalEventPayload struct {
	EventType    JournalEventType `json:"event_type"`
	JournalID    string           `json:"journal_id"`
	StepID       string           `json:"step_id,omitempty"`
	ActorID      string           `json:"actor_id"`
	ActorRole    JournalActorRole `json:"actor_role"`
	PayloadJSON  json.RawMessage  `json:"payload_json"`
	PreviousHash *string          `json:"previous_hash"`
	CreatedAt    time.Time        `json:"created_at"`
}

type preparedStepCompletedEvent struct {
	PayloadBytes    []byte
	PreviousHash    *string
	EventHash       string
	SigningKeyID    *string
	SignatureBase64 *string
}

func (r *PostgresRepository) prepareStepCompletedEventForConfirm(
	ctx context.Context,
	tx *sql.Tx,
	journalID string,
	target stepConfirmationTarget,
	clientID string,
	completedAt time.Time,
) (preparedStepCompletedEvent, error) {
	payloadBytes, err := stepCompletedPayloadBytes(journalID, target, clientID, completedAt)
	if err != nil {
		return preparedStepCompletedEvent{}, err
	}

	previousHash, err := r.lastJournalEventHash(ctx, tx, journalID)
	if err != nil {
		return preparedStepCompletedEvent{}, err
	}
	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:    JournalEventTypeStepCompletedByClient,
		JournalID:    journalID,
		StepID:       target.ProtectedStepID,
		ActorID:      clientID,
		ActorRole:    JournalActorRoleClient,
		PayloadJSON:  json.RawMessage(payloadBytes),
		PreviousHash: previousHash,
		CreatedAt:    completedAt,
	})
	if err != nil {
		return preparedStepCompletedEvent{}, fmt.Errorf("hash backend-managed protected journal event: %w", err)
	}

	prepared := preparedStepCompletedEvent{
		PayloadBytes: payloadBytes,
		PreviousHash: previousHash,
		EventHash:    eventHash,
	}

	signingKey, found, err := r.activeBackendManagedSigningKey(ctx, tx, clientID)
	if err != nil {
		return preparedStepCompletedEvent{}, err
	}
	if !found {
		log.Printf("journal backend-managed signing: legacy unsigned event fallback for user %s because encrypted private key is missing", clientID)
		return prepared, nil
	}

	signature, err := r.signBackendManagedJournalEvent(signingKey, eventHash)
	if err != nil {
		return preparedStepCompletedEvent{}, err
	}
	prepared.SigningKeyID = &signingKey.ID
	prepared.SignatureBase64 = &signature
	return prepared, nil
}

func (r *PostgresRepository) appendPreparedStepCompletedEvent(
	ctx context.Context,
	tx *sql.Tx,
	journalID string,
	target stepConfirmationTarget,
	clientID string,
	completedAt time.Time,
	prepared preparedStepCompletedEvent,
) error {
	var insertedHash string
	err := tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_events (
		   journal_id, step_id, event_type, actor_id, actor_role,
		   payload_json, reason, previous_hash, event_hash, signing_key_id, signature, created_at
		 )
		 VALUES (
		   $1, $2, 'step_completed_by_client', $3, 'client',
		   $4::jsonb, NULL, $5, $6, $7, $8, $9
		 )
		 ON CONFLICT (journal_id, step_id)
		   WHERE event_type = 'step_completed_by_client' AND step_id IS NOT NULL
		 DO NOTHING
		 RETURNING event_hash`,
		journalID,
		target.ProtectedStepID,
		clientID,
		string(prepared.PayloadBytes),
		nullableStringValue(prepared.PreviousHash),
		prepared.EventHash,
		nullableStringValue(prepared.SigningKeyID),
		nullableStringValue(prepared.SignatureBase64),
		completedAt,
	).Scan(&insertedHash)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("append backend-managed protected journal event: %w", err)
	}
	if insertedHash != "" {
		if _, err = tx.ExecContext(
			ctx,
			`UPDATE care_journals
			 SET final_hash = $2
			 WHERE id = $1`,
			journalID,
			insertedHash,
		); err != nil {
			return fmt.Errorf("update journal final hash for backend-managed event: %w", err)
		}
	}
	return nil
}

func (r *PostgresRepository) appendStepCompletedEvent(
	ctx context.Context,
	tx *sql.Tx,
	journalID string,
	target stepConfirmationTarget,
	clientID string,
	completedAt time.Time,
) error {
	var deadlineAt *time.Time
	if target.DeadlineAt.Valid {
		value := target.DeadlineAt.Time
		deadlineAt = &value
	}
	payload := stepCompletedEventPayload{
		JournalID:              journalID,
		StepID:                 target.ProtectedStepID,
		LegacyRecommendationID: target.RecommendationID,
		CompletedAt:            completedAt,
		CompletedByClientID:    clientID,
		DeadlineAt:             deadlineAt,
		EventType:              JournalEventTypeStepCompletedByClient,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal protected step completion event payload: %w", err)
	}

	previousHash, err := r.lastJournalEventHash(ctx, tx, journalID)
	if err != nil {
		return err
	}
	eventHash, err := hashJournalEvent(canonicalJournalEventPayload{
		EventType:    JournalEventTypeStepCompletedByClient,
		JournalID:    journalID,
		StepID:       target.ProtectedStepID,
		ActorID:      clientID,
		ActorRole:    JournalActorRoleClient,
		PayloadJSON:  json.RawMessage(payloadBytes),
		PreviousHash: previousHash,
		CreatedAt:    completedAt,
	})
	if err != nil {
		return fmt.Errorf("hash protected journal event: %w", err)
	}

	var insertedHash string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_events (
		   journal_id, step_id, event_type, actor_id, actor_role,
		   payload_json, reason, previous_hash, event_hash, signing_key_id, signature, created_at
		 )
		 VALUES (
		   $1, $2, 'step_completed_by_client', $3, 'client',
		   $4::jsonb, NULL, $5, $6, NULL, NULL, $7
		 )
		 ON CONFLICT (journal_id, step_id)
		   WHERE event_type = 'step_completed_by_client' AND step_id IS NOT NULL
		 DO NOTHING
		 RETURNING event_hash`,
		journalID,
		target.ProtectedStepID,
		clientID,
		string(payloadBytes),
		nullableStringValue(previousHash),
		eventHash,
		completedAt,
	).Scan(&insertedHash)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("append protected journal event: %w", err)
	}
	if insertedHash != "" {
		if _, err = tx.ExecContext(
			ctx,
			`UPDATE care_journals
			 SET final_hash = $2
			 WHERE id = $1`,
			journalID,
			insertedHash,
		); err != nil {
			return fmt.Errorf("update journal final hash: %w", err)
		}
	}

	return nil
}

func (r *PostgresRepository) appendSignedStepCompletedEvent(
	ctx context.Context,
	tx *sql.Tx,
	journalID string,
	target stepConfirmationTarget,
	clientID string,
	completedAt time.Time,
	payloadBytes []byte,
	previousHash *string,
	signingKeyID string,
	signature string,
	eventHash string,
) error {
	var insertedHash string
	err := tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_events (
		   journal_id, step_id, event_type, actor_id, actor_role,
		   payload_json, reason, previous_hash, event_hash, signing_key_id, signature, created_at
		 )
		 VALUES (
		   $1, $2, 'step_completed_by_client', $3, 'client',
		   $4::jsonb, NULL, $5, $6, $7, $8, $9
		 )
		 ON CONFLICT (journal_id, step_id)
		   WHERE event_type = 'step_completed_by_client' AND step_id IS NOT NULL
		 DO NOTHING
		 RETURNING event_hash`,
		journalID,
		target.ProtectedStepID,
		clientID,
		string(payloadBytes),
		nullableStringValue(previousHash),
		eventHash,
		signingKeyID,
		strings.TrimSpace(signature),
		completedAt,
	).Scan(&insertedHash)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotReady
		}
		return fmt.Errorf("append signed protected journal event: %w", err)
	}
	if _, err = tx.ExecContext(
		ctx,
		`UPDATE care_journals
		 SET final_hash = $2
		 WHERE id = $1`,
		journalID,
		insertedHash,
	); err != nil {
		return fmt.Errorf("update journal final hash for signed event: %w", err)
	}
	return nil
}

func (r *PostgresRepository) insertLegacyStepConfirmationEntry(
	ctx context.Context,
	tx *sql.Tx,
	journalID string,
	target stepConfirmationTarget,
	clientID string,
	confirmedAt time.Time,
) error {
	if strings.TrimSpace(target.RecommendationID) == "" {
		return nil
	}

	var previousEntryID sql.NullString
	var previousHash sql.NullString
	err := tx.QueryRowContext(
		ctx,
		`SELECT id::text, entry_hash
		 FROM care_journal_entries
		 WHERE journal_id = $1
		 ORDER BY created_at DESC, id DESC
		 LIMIT 1`,
		journalID,
	).Scan(&previousEntryID, &previousHash)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("load previous journal entry: %w", err)
	}

	payload := confirmationPayload{
		JournalID:         journalID,
		RecommendationID:  target.RecommendationID,
		StepNumber:        target.StepNumber,
		ConfirmedByUserID: clientID,
		ConfirmedAt:       confirmedAt,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal confirmation payload: %w", err)
	}

	var previousEntry any
	var previousHashValue any
	if previousEntryID.Valid && previousHash.Valid {
		previousEntry = previousEntryID.String
		previousHashValue = previousHash.String
	}

	entryHash := confirmationHash(payloadBytes, previousHash.String)
	var insertedHash string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO care_journal_entries (
		   journal_id, recommendation_id, entry_type, actor_user_id,
		   previous_entry_id, previous_hash, entry_hash, payload, created_at
		 )
		 VALUES ($1, $2, 'client_confirmation', $3, $4, $5, $6, $7::jsonb, $8)
		 ON CONFLICT (journal_id, recommendation_id)
		   WHERE entry_type = 'client_confirmation'
		 DO NOTHING
		 RETURNING entry_hash`,
		journalID,
		target.RecommendationID,
		clientID,
		previousEntry,
		previousHashValue,
		entryHash,
		string(payloadBytes),
		confirmedAt,
	).Scan(&insertedHash)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("insert step confirmation: %w", err)
	}
	if insertedHash != "" {
		if _, err = tx.ExecContext(
			ctx,
			`UPDATE care_journals
			 SET latest_hash = $2
			 WHERE id = $1`,
			journalID,
			insertedHash,
		); err != nil {
			return fmt.Errorf("update journal latest hash: %w", err)
		}
	}
	return nil
}

func (r *PostgresRepository) signedStepCompletionAlreadyExists(ctx context.Context, tx *sql.Tx, journalID string, protectedStepID string, request StepConfirmationCommit) (bool, error) {
	var eventHash sql.NullString
	var signature sql.NullString
	var signingKeyID sql.NullString
	err := tx.QueryRowContext(
		ctx,
		`SELECT event_hash,
		        signature,
		        signing_key_id::text
		 FROM care_journal_events
		 WHERE journal_id = $1
		   AND step_id = $2
		   AND event_type = 'step_completed_by_client'`,
		journalID,
		protectedStepID,
	).Scan(&eventHash, &signature, &signingKeyID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, fmt.Errorf("load existing signed step event: %w", err)
	}
	if !eventHash.Valid || !signature.Valid || !signingKeyID.Valid {
		return false, nil
	}
	return eventHash.String == strings.TrimSpace(request.EventHashToSign) &&
		signature.String == strings.TrimSpace(request.Signature) &&
		signingKeyID.String == strings.TrimSpace(request.SigningKeyID), nil
}

func (r *PostgresRepository) lastJournalEventHash(ctx context.Context, tx *sql.Tx, journalID string) (*string, error) {
	var previousHash string
	err := tx.QueryRowContext(
		ctx,
		`SELECT event_hash
		 FROM care_journal_events
		 WHERE journal_id = $1
		   AND event_hash IS NOT NULL
		 ORDER BY created_at DESC, id DESC
		 LIMIT 1`,
		journalID,
	).Scan(&previousHash)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("load previous journal event hash: %w", err)
	}
	return &previousHash, nil
}

func hashJournalEvent(payload canonicalJournalEventPayload) (string, error) {
	normalizedPayload, err := normalizeJSON(payload.PayloadJSON)
	if err != nil {
		return "", err
	}
	payload.PayloadJSON = normalizedPayload
	payload.CreatedAt = payload.CreatedAt.UTC().Truncate(time.Microsecond)
	canonicalPayload, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(canonicalPayload)
	return hex.EncodeToString(sum[:]), nil
}

func normalizeJSON(raw json.RawMessage) (json.RawMessage, error) {
	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		return nil, err
	}
	normalized, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	return json.RawMessage(normalized), nil
}

func nullableStringValue(value *string) any {
	if value == nil {
		return nil
	}
	return *value
}

func (r *PostgresRepository) ensureProtectedStepsForJournal(ctx context.Context, tx *sql.Tx, journalID string) error {
	if _, err := tx.ExecContext(
		ctx,
		`INSERT INTO care_journal_steps (
		   journal_id, day_number, title, description, deadline_at, status, completed_at, completed_by_client_id
		 )
		 SELECT cr.journal_id,
		        COALESCE(NULLIF(cr.due_offset_days, 0), cr.step_number),
		        cr.title,
		        cr.description,
		        COALESCE(
		          cr.due_at,
		          a.scheduled_at + make_interval(days => COALESCE(NULLIF(cr.due_offset_days, 0), cr.step_number))
		        ),
		        CASE
		          WHEN confirmation.confirmed_at IS NOT NULL AND confirmation.actor_user_id IS NOT NULL
		          THEN 'completed_by_client'
		          ELSE 'pending'
		        END,
		        confirmation.confirmed_at,
		        confirmation.actor_user_id
		 FROM care_recommendations cr
		 JOIN appointments a ON a.id = cr.appointment_id
		 LEFT JOIN LATERAL (
		   SELECT e.created_at AS confirmed_at,
		          e.actor_user_id
		   FROM care_journal_entries e
		   WHERE e.journal_id = cr.journal_id
		     AND e.recommendation_id = cr.id
		     AND e.entry_type = 'client_confirmation'
		   ORDER BY e.created_at ASC
		   LIMIT 1
		 ) confirmation ON TRUE
		 WHERE cr.journal_id = $1
		   AND cr.status = 'approved'
		   AND NOT EXISTS (
		     SELECT 1
		     FROM care_journal_steps existing
		     WHERE existing.journal_id = $1
		   )
		 ORDER BY cr.step_number ASC`,
		journalID,
	); err != nil {
		return fmt.Errorf("ensure protected journal steps: %w", err)
	}
	return nil
}

func (r *PostgresRepository) resolveStepConfirmationTarget(ctx context.Context, tx *sql.Tx, journalID string, stepID string) (stepConfirmationTarget, error) {
	target, found, err := r.findTargetByProtectedStepID(ctx, tx, journalID, stepID, true)
	if err != nil {
		return stepConfirmationTarget{}, err
	}
	if found {
		return target, nil
	}

	target, found, err = r.findTargetByRecommendationID(ctx, tx, journalID, stepID, true)
	if err != nil {
		return stepConfirmationTarget{}, err
	}
	if found {
		return target, nil
	}

	return stepConfirmationTarget{}, ErrStepNotFound
}

func (r *PostgresRepository) resolveStepConfirmationTargetReadOnly(ctx context.Context, tx *sql.Tx, journalID string, stepID string) (stepConfirmationTarget, error) {
	target, found, err := r.findTargetByProtectedStepID(ctx, tx, journalID, stepID, false)
	if err != nil {
		return stepConfirmationTarget{}, err
	}
	if found {
		return target, nil
	}

	target, found, err = r.findTargetByRecommendationID(ctx, tx, journalID, stepID, false)
	if err != nil {
		return stepConfirmationTarget{}, err
	}
	if found {
		return target, nil
	}

	return stepConfirmationTarget{}, ErrStepNotFound
}

func (r *PostgresRepository) findTargetByProtectedStepID(ctx context.Context, tx *sql.Tx, journalID string, stepID string, lock bool) (stepConfirmationTarget, bool, error) {
	var target stepConfirmationTarget
	var status string
	query := `SELECT cjs.id::text,
		        COALESCE(cr.id::text, ''),
		        COALESCE(cr.step_number, cjs.day_number),
		        cjs.status,
		        cjs.deadline_at
		 FROM care_journal_steps cjs
		 LEFT JOIN LATERAL (
		   SELECT cr.id, cr.step_number
		   FROM care_recommendations cr
		   WHERE cr.journal_id = cjs.journal_id
		     AND cr.title = cjs.title
		     AND cr.description = cjs.description
		     AND COALESCE(NULLIF(cr.due_offset_days, 0), cr.step_number) = cjs.day_number
		   ORDER BY cr.step_number ASC, cr.created_at ASC, cr.id ASC
		   LIMIT 1
		 ) cr ON TRUE
		 WHERE cjs.journal_id = $1
		   AND cjs.id = $2`
	if lock {
		query += `
		 FOR UPDATE OF cjs`
	}
	err := tx.QueryRowContext(
		ctx,
		query,
		journalID,
		stepID,
	).Scan(
		&target.ProtectedStepID,
		&target.RecommendationID,
		&target.StepNumber,
		&status,
		&target.DeadlineAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return stepConfirmationTarget{}, false, nil
		}
		return stepConfirmationTarget{}, false, fmt.Errorf("resolve protected journal step: %w", err)
	}
	target.Status = JournalStepStatus(status)
	return target, true, nil
}

func (r *PostgresRepository) findTargetByRecommendationID(ctx context.Context, tx *sql.Tx, journalID string, stepID string, lock bool) (stepConfirmationTarget, bool, error) {
	var target stepConfirmationTarget
	var status string
	query := `SELECT cjs.id::text,
		        cr.id::text,
		        cr.step_number,
		        cjs.status,
		        cjs.deadline_at
		 FROM care_recommendations cr
		 JOIN care_journal_steps cjs
		   ON cjs.journal_id = cr.journal_id
		  AND cjs.title = cr.title
		  AND cjs.description = cr.description
		  AND cjs.day_number = COALESCE(NULLIF(cr.due_offset_days, 0), cr.step_number)
		 WHERE cr.journal_id = $1
		   AND cr.id = $2
		 ORDER BY cjs.created_at ASC, cjs.id ASC
		 LIMIT 1`
	if lock {
		query += `
		 FOR UPDATE OF cjs`
	}
	err := tx.QueryRowContext(
		ctx,
		query,
		journalID,
		stepID,
	).Scan(
		&target.ProtectedStepID,
		&target.RecommendationID,
		&target.StepNumber,
		&status,
		&target.DeadlineAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return stepConfirmationTarget{}, false, nil
		}
		return stepConfirmationTarget{}, false, fmt.Errorf("resolve recommendation journal step: %w", err)
	}
	target.Status = JournalStepStatus(status)
	return target, true, nil
}

func journalStatusAllowsStepConfirmation(status string) bool {
	return journalStatusAllowsClientProtectedEvent(status)
}

func journalStatusAllowsClientProtectedEvent(status string) bool {
	return strings.TrimSpace(status) == "" || JournalStatus(status) == JournalStatusActive
}

func validateProtectedStepConfirmation(target stepConfirmationTarget, now time.Time) error {
	switch target.Status {
	case JournalStepStatusCompletedByClient:
		return nil
	case JournalStepStatusPending:
		if target.DeadlineAt.Valid && now.After(target.DeadlineAt.Time) {
			return ErrNotReady
		}
		return nil
	default:
		return ErrNotReady
	}
}

func validateProtectedStepPreparation(target stepConfirmationTarget, now time.Time) error {
	if target.Status != JournalStepStatusPending {
		return ErrNotReady
	}
	if target.DeadlineAt.Valid && now.After(target.DeadlineAt.Time) {
		return ErrNotReady
	}
	return nil
}

func stepCompletedPayloadBytes(journalID string, target stepConfirmationTarget, clientID string, completedAt time.Time) ([]byte, error) {
	var deadlineAt *time.Time
	if target.DeadlineAt.Valid {
		value := target.DeadlineAt.Time
		deadlineAt = &value
	}
	payload := stepCompletedEventPayload{
		JournalID:              journalID,
		StepID:                 target.ProtectedStepID,
		LegacyRecommendationID: target.RecommendationID,
		CompletedAt:            completedAt,
		CompletedByClientID:    clientID,
		DeadlineAt:             deadlineAt,
		EventType:              JournalEventTypeStepCompletedByClient,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal protected step completion payload: %w", err)
	}
	return payloadBytes, nil
}

func validateStepConfirmationCommitRequest(request StepConfirmationCommit) error {
	if !eventHashPattern.MatchString(strings.TrimSpace(request.EventHashToSign)) {
		return ErrInvalidCommit
	}
	if request.PreviousHash != nil && !eventHashPattern.MatchString(strings.TrimSpace(*request.PreviousHash)) {
		return ErrInvalidCommit
	}
	if request.CompletedAt.IsZero() || strings.TrimSpace(request.SigningKeyID) == "" || strings.TrimSpace(request.Signature) == "" {
		return ErrInvalidCommit
	}
	return nil
}

func normalizeClientUnavailabilityNoticeInput(input ClientUnavailabilityNoticeInput) (ClientUnavailabilityNoticeInput, error) {
	from := input.UnavailableFrom.UTC().Truncate(time.Microsecond)
	until := input.UnavailableUntil.UTC().Truncate(time.Microsecond)
	reason := strings.TrimSpace(input.Reason)
	comment := strings.TrimSpace(input.Comment)

	if from.IsZero() || until.IsZero() || !from.Before(until) {
		return ClientUnavailabilityNoticeInput{}, ErrInvalidNotice
	}
	if reason == "" && comment == "" {
		return ClientUnavailabilityNoticeInput{}, ErrInvalidNotice
	}
	if len([]rune(reason)) > 200 || len([]rune(comment)) > 1000 {
		return ClientUnavailabilityNoticeInput{}, ErrInvalidNotice
	}

	return ClientUnavailabilityNoticeInput{
		UnavailableFrom:  from,
		UnavailableUntil: until,
		Reason:           reason,
		Comment:          comment,
	}, nil
}

func normalizeClientProblemReportInput(input ClientProblemReportInput) (ClientProblemReportInput, error) {
	reason := strings.TrimSpace(input.Reason)
	comment := strings.TrimSpace(input.Comment)
	if reason == "" && comment == "" {
		return ClientProblemReportInput{}, ErrInvalidProblem
	}
	if len([]rune(reason)) > 200 || len([]rune(comment)) > 1000 {
		return ClientProblemReportInput{}, ErrInvalidProblem
	}

	return ClientProblemReportInput{
		Reason:  reason,
		Comment: comment,
	}, nil
}

func normalizeDeadlineExtensionInput(input DeadlineExtensionInput) (DeadlineExtensionInput, error) {
	newDeadlineAt := input.NewDeadlineAt.UTC().Truncate(time.Microsecond)
	reason := strings.TrimSpace(input.Reason)
	if newDeadlineAt.IsZero() || reason == "" || len([]rune(reason)) > 1000 {
		return DeadlineExtensionInput{}, ErrInvalidDeadline
	}

	var linkedNoticeID *string
	if input.LinkedClientNoticeEventID != nil {
		trimmed := strings.TrimSpace(*input.LinkedClientNoticeEventID)
		if trimmed == "" {
			return DeadlineExtensionInput{}, ErrInvalidDeadline
		}
		linkedNoticeID = &trimmed
	}

	return DeadlineExtensionInput{
		NewDeadlineAt:             newDeadlineAt,
		Reason:                    reason,
		LinkedClientNoticeEventID: linkedNoticeID,
	}, nil
}

func validateDeadlineExtensionTarget(target stepConfirmationTarget, newDeadlineAt time.Time) (*time.Time, error) {
	if target.Status != JournalStepStatusPending {
		return nil, ErrNotReady
	}

	if !target.DeadlineAt.Valid {
		return nil, nil
	}

	oldDeadlineAt := target.DeadlineAt.Time.UTC().Truncate(time.Microsecond)
	if !newDeadlineAt.After(oldDeadlineAt) {
		return nil, ErrInvalidDeadline
	}
	return &oldDeadlineAt, nil
}

func (r *PostgresRepository) validateLinkedClientMessageEvent(ctx context.Context, tx *sql.Tx, journalID string, eventID string) error {
	var exists bool
	err := tx.QueryRowContext(
		ctx,
		`SELECT EXISTS (
		   SELECT 1
		   FROM care_journal_events
		   WHERE id::text = $1
		     AND journal_id = $2
		     AND event_type IN ('client_unavailability_notice_added', 'client_problem_reported')
		 )`,
		eventID,
		journalID,
	).Scan(&exists)
	if err != nil {
		return fmt.Errorf("validate linked client message event: %w", err)
	}
	if !exists {
		return ErrInvalidDeadline
	}
	return nil
}

func normalizeJournalStopInput(input JournalStopInput) (JournalStopInput, error) {
	reason := strings.TrimSpace(input.Reason)
	stopCategory := strings.TrimSpace(input.StopCategory)
	if reason == "" || len([]rune(reason)) > 1000 || !isValidJournalStopCategory(stopCategory) {
		return JournalStopInput{}, ErrInvalidStop
	}

	var linkedNoticeID *string
	if input.LinkedClientNoticeEventID != nil {
		trimmed := strings.TrimSpace(*input.LinkedClientNoticeEventID)
		if trimmed == "" {
			return JournalStopInput{}, ErrInvalidStop
		}
		linkedNoticeID = &trimmed
	}

	return JournalStopInput{
		Reason:                    reason,
		StopCategory:              stopCategory,
		LinkedClientNoticeEventID: linkedNoticeID,
	}, nil
}

func isValidJournalStopCategory(category string) bool {
	switch category {
	case "complication",
		"in_person_inspection_required",
		"client_reported_problem",
		"recommendations_no_longer_valid",
		"replacement_journal_planned",
		"other":
		return true
	default:
		return false
	}
}

func normalizeReplacementJournalInput(input ReplacementJournalInput) (ReplacementJournalInput, error) {
	reason := strings.TrimSpace(input.Reason)
	if reason == "" || len([]rune(reason)) > 1000 || len(input.Steps) == 0 {
		return ReplacementJournalInput{}, ErrInvalidReplacement
	}

	steps := make([]ReplacementJournalStepInput, 0, len(input.Steps))
	for _, step := range input.Steps {
		title := strings.TrimSpace(step.Title)
		description := strings.TrimSpace(step.Description)
		if step.DayNumber <= 0 || title == "" || description == "" {
			return ReplacementJournalInput{}, ErrInvalidReplacement
		}
		if len([]rune(title)) > 200 || len([]rune(description)) > 4000 {
			return ReplacementJournalInput{}, ErrInvalidReplacement
		}

		var deadlineAt *time.Time
		if step.DeadlineAt != nil {
			value := step.DeadlineAt.UTC().Truncate(time.Microsecond)
			if value.IsZero() {
				return ReplacementJournalInput{}, ErrInvalidReplacement
			}
			deadlineAt = &value
		}

		steps = append(steps, ReplacementJournalStepInput{
			DayNumber:   step.DayNumber,
			Title:       title,
			Description: description,
			DeadlineAt:  deadlineAt,
		})
	}

	return ReplacementJournalInput{
		Reason: reason,
		Steps:  steps,
	}, nil
}

func emptyStringAsNil(value string) *string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	trimmed := strings.TrimSpace(value)
	return &trimmed
}

func nullableTimeValue(value *time.Time) any {
	if value == nil {
		return nil
	}
	return *value
}

func normalizeOptionalHash(value *string) *string {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func verifyEd25519Signature(publicKey string, eventHash string, signature string) error {
	rawPublicKey, err := decodeEd25519PublicKey(publicKey)
	if err != nil {
		return ErrInvalidSignature
	}
	rawSignature, err := base64.StdEncoding.DecodeString(strings.TrimSpace(signature))
	if err != nil {
		return ErrInvalidSignature
	}
	if len(rawSignature) != ed25519.SignatureSize {
		return ErrInvalidSignature
	}
	if !ed25519.Verify(ed25519.PublicKey(rawPublicKey), []byte(strings.TrimSpace(eventHash)), rawSignature) {
		return ErrInvalidSignature
	}
	return nil
}

type confirmationPayload struct {
	JournalID         string    `json:"journal_id"`
	RecommendationID  string    `json:"recommendation_id"`
	StepNumber        int       `json:"step_number"`
	ConfirmedByUserID string    `json:"confirmed_by_user_id"`
	ConfirmedAt       time.Time `json:"confirmed_at"`
}

func confirmationHash(payload []byte, previousHash string) string {
	sum := sha256.Sum256(append([]byte(previousHash+"|"), payload...))
	return hex.EncodeToString(sum[:])
}

type scanner interface {
	Scan(dest ...any) error
}

func scanJournal(row scanner) (Journal, error) {
	var journal Journal
	var lastVerifiedAt sql.NullTime
	var status string
	var rootJournalID sql.NullString
	var parentJournalID sql.NullString
	var replacedByJournalID sql.NullString
	var activatedAt sql.NullTime
	var stoppedAt sql.NullTime
	var completedAt sql.NullTime
	var stopReason sql.NullString
	var replacementReason sql.NullString
	var finalHash sql.NullString
	if err := row.Scan(
		&journal.ID,
		&journal.AppointmentID,
		&journal.ClientID,
		&journal.MasterID,
		&journal.IntegrityStatus,
		&lastVerifiedAt,
		&journal.CreatedAt,
		&status,
		&rootJournalID,
		&parentJournalID,
		&replacedByJournalID,
		&journal.VersionNumber,
		&activatedAt,
		&stoppedAt,
		&completedAt,
		&stopReason,
		&replacementReason,
		&finalHash,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Journal{}, ErrJournalNotFound
		}
		return Journal{}, fmt.Errorf("scan journal: %w", err)
	}
	if lastVerifiedAt.Valid {
		journal.LastVerifiedAt = &lastVerifiedAt.Time
	}
	journal.Status = JournalStatus(status)
	if rootJournalID.Valid {
		journal.RootJournalID = &rootJournalID.String
	}
	if parentJournalID.Valid {
		journal.ParentJournalID = &parentJournalID.String
	}
	if replacedByJournalID.Valid {
		journal.ReplacedByJournalID = &replacedByJournalID.String
	}
	if activatedAt.Valid {
		value := activatedAt.Time
		journal.ActivatedAt = &value
	}
	if stoppedAt.Valid {
		value := stoppedAt.Time
		journal.StoppedAt = &value
	}
	if completedAt.Valid {
		value := completedAt.Time
		journal.CompletedAt = &value
	}
	if stopReason.Valid {
		journal.StopReason = &stopReason.String
	}
	if replacementReason.Valid {
		journal.ReplacementReason = &replacementReason.String
	}
	if finalHash.Valid {
		journal.FinalHash = &finalHash.String
	}
	return journal, nil
}

func scanJournals(rows *sql.Rows) ([]Journal, error) {
	var journals []Journal
	for rows.Next() {
		journal, err := scanJournal(rows)
		if err != nil {
			return nil, err
		}
		journals = append(journals, journal)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate journals: %w", err)
	}
	if journals == nil {
		journals = []Journal{}
	}
	return journals, nil
}
