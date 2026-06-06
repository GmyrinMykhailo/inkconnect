package users

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrEmailAlreadyExists    = errors.New("email already exists")
	ErrPhoneAlreadyExists    = errors.New("phone already exists")
	ErrUsernameAlreadyExists = errors.New("username already exists")
	ErrUserNotFound          = errors.New("user not found")
	ErrCannotFavoriteSelf    = errors.New("cannot favorite self")
)

type Repository interface {
	CreateUser(ctx context.Context, params CreateUserParams) (string, error)
	UpsertSigningKey(ctx context.Context, params UpsertSigningKeyParams) error
	FindUserByEmail(ctx context.Context, email string) (UserWithPassword, error)
	FindPasswordHashByUserID(ctx context.Context, userID string) (string, error)
	FindSecurityContactByUserID(ctx context.Context, userID string) (SecurityContact, error)
	FindProfileByUserID(ctx context.Context, userID string) (UserProfile, error)
	FindPublicProfileByUsername(ctx context.Context, username string) (PublicUserProfile, error)
	UpdateProfile(ctx context.Context, userID string, params UpdateProfileParams) (UserProfile, error)
	UpdatePasswordHash(ctx context.Context, userID string, passwordHash string) error
	UsernameExists(ctx context.Context, username string) (bool, error)
	EmailExists(ctx context.Context, email string) (bool, error)
	PhoneExists(ctx context.Context, phone string) (bool, error)
	EmailExistsForOtherUser(ctx context.Context, email string, userID string) (bool, error)
	PhoneExistsForOtherUser(ctx context.Context, phone string, userID string) (bool, error)
	UpdateEmail(ctx context.Context, userID string, email string) (SecurityContact, error)
	UpdatePhone(ctx context.Context, userID string, phone string) (SecurityContact, error)
	DeactivateUserAndDeleteSessions(ctx context.Context, userID string) error
	SearchMasters(ctx context.Context, query string, limit int) ([]PublicMasterProfile, error)
	FindPublicMasterByUsername(ctx context.Context, username string) (PublicMasterProfile, error)
	ListFavoriteMasters(ctx context.Context, userID string) ([]PublicMasterProfile, error)
	AddFavoriteMaster(ctx context.Context, userID string, masterID string) error
	RemoveFavoriteMaster(ctx context.Context, userID string, masterID string) error
	CreateSession(ctx context.Context, params CreateSessionParams) error
	FindUserBySessionHash(ctx context.Context, sessionHash string) (AuthenticatedUser, error)
	DeleteSessionByHash(ctx context.Context, sessionHash string) error
}

type CreateUserParams struct {
	Username          string
	Email             string
	PasswordHash      string
	Role              Role
	FullName          string
	LastName          string
	FirstName         string
	MiddleName        string
	Phone             string
	City              string
	ShowCityInProfile bool
	Bio               string
	PublicKey         string
	StudioName        string
}

type UpsertSigningKeyParams struct {
	UserID                    string
	PublicKey                 string
	Algorithm                 string
	KeyFingerprint            string
	Status                    string
	EncryptedPrivateKey       *string
	PrivateKeyEncryptionKeyID *string
	PrivateKeyEncryptedAt     *time.Time
}

type UpdateProfileParams struct {
	LastName              string
	FirstName             string
	MiddleName            string
	StudioName            string
	UpdateMasterStudio    bool
	City                  string
	Bio                   string
	ShowFullNameInProfile bool
	ShowCityInProfile     bool
	FullName              string
}

type PostgresRepository struct {
	db *sql.DB
}

func NewPostgresRepository(db *sql.DB) *PostgresRepository {
	return &PostgresRepository{db: db}
}

func EnsureFavoriteMastersSchema(ctx context.Context, db *sql.DB) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS favorite_masters (
			user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			master_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			PRIMARY KEY (user_id, master_id)
		)`,
		`CREATE INDEX IF NOT EXISTS favorite_masters_user_created_idx
		 ON favorite_masters (user_id, created_at DESC)`,
	}

	for _, statement := range statements {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("ensure favorite masters schema: %w", err)
		}
	}

	return nil
}

func (r *PostgresRepository) CreateUser(ctx context.Context, params CreateUserParams) (string, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return "", fmt.Errorf("begin create user transaction: %w", err)
	}

	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var userID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO users (username, email, password_hash, role, full_name, last_name, first_name, middle_name, phone, city, show_city_in_profile, bio, public_key)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		 RETURNING id`,
		params.Username,
		params.Email,
		params.PasswordHash,
		params.Role,
		params.FullName,
		params.LastName,
		params.FirstName,
		params.MiddleName,
		params.Phone,
		params.City,
		params.ShowCityInProfile,
		params.Bio,
		params.PublicKey,
	).Scan(&userID)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			if pgErr.ConstraintName == "users_username_key" || pgErr.ConstraintName == "idx_users_username" {
				return "", ErrUsernameAlreadyExists
			}
			if pgErr.ConstraintName == "users_email_key" || pgErr.ConstraintName == "idx_users_email" {
				return "", ErrEmailAlreadyExists
			}
			if pgErr.ConstraintName == "users_phone_key" || pgErr.ConstraintName == "idx_users_phone" {
				return "", ErrPhoneAlreadyExists
			}
			return "", ErrEmailAlreadyExists
		}
		return "", fmt.Errorf("insert user: %w", err)
	}

	if params.Role == RoleMaster {
		_, err = tx.ExecContext(
			ctx,
			`INSERT INTO master_profiles (user_id, studio_name)
			 VALUES ($1, $2)`,
			userID,
			params.StudioName,
		)
		if err != nil {
			return "", fmt.Errorf("insert master profile: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return "", fmt.Errorf("commit create user transaction: %w", err)
	}

	return userID, nil
}

func (r *PostgresRepository) UpsertSigningKey(ctx context.Context, params UpsertSigningKeyParams) error {
	_, err := r.db.ExecContext(
		ctx,
		`INSERT INTO user_signing_keys (
		   user_id,
		   public_key,
		   algorithm,
		   key_fingerprint,
		   status,
		   encrypted_private_key,
		   private_key_encryption_key_id,
		   private_key_encrypted_at
		 )
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		 ON CONFLICT (user_id, key_fingerprint) DO UPDATE
		 SET public_key = EXCLUDED.public_key,
		     algorithm = EXCLUDED.algorithm,
		     status = EXCLUDED.status,
		     encrypted_private_key = COALESCE(EXCLUDED.encrypted_private_key, user_signing_keys.encrypted_private_key),
		     private_key_encryption_key_id = COALESCE(EXCLUDED.private_key_encryption_key_id, user_signing_keys.private_key_encryption_key_id),
		     private_key_encrypted_at = COALESCE(EXCLUDED.private_key_encrypted_at, user_signing_keys.private_key_encrypted_at)`,
		params.UserID,
		params.PublicKey,
		params.Algorithm,
		params.KeyFingerprint,
		params.Status,
		params.EncryptedPrivateKey,
		params.PrivateKeyEncryptionKeyID,
		params.PrivateKeyEncryptedAt,
	)
	if err != nil {
		return fmt.Errorf("upsert user signing key: %w", err)
	}

	return nil
}

func (r *PostgresRepository) FindUserByEmail(ctx context.Context, email string) (UserWithPassword, error) {
	var user UserWithPassword
	err := r.db.QueryRowContext(
		ctx,
		`SELECT u.id, u.username, COALESCE(mp.studio_name, ''), u.email, u.password_hash, u.role, u.public_key
		 FROM users u
		 LEFT JOIN master_profiles mp ON mp.user_id = u.id
		 WHERE u.email = $1 AND u.is_active = TRUE`,
		email,
	).Scan(
		&user.ID,
		&user.Username,
		&user.StudioName,
		&user.Email,
		&user.PasswordHash,
		&user.Role,
		&user.PublicKey,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return UserWithPassword{}, ErrUserNotFound
		}
		return UserWithPassword{}, fmt.Errorf("find user by email: %w", err)
	}

	return user, nil
}

func (r *PostgresRepository) FindPasswordHashByUserID(ctx context.Context, userID string) (string, error) {
	var passwordHash string
	err := r.db.QueryRowContext(
		ctx,
		`SELECT password_hash
		 FROM users
		 WHERE id = $1 AND is_active = TRUE`,
		userID,
	).Scan(&passwordHash)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", ErrUserNotFound
		}
		return "", fmt.Errorf("find password hash by user id: %w", err)
	}

	return passwordHash, nil
}

func (r *PostgresRepository) FindSecurityContactByUserID(ctx context.Context, userID string) (SecurityContact, error) {
	var contact SecurityContact
	err := r.db.QueryRowContext(
		ctx,
		`SELECT email, COALESCE(phone, '')
		 FROM users
		 WHERE id = $1 AND is_active = TRUE`,
		userID,
	).Scan(&contact.Email, &contact.Phone)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return SecurityContact{}, ErrUserNotFound
		}
		return SecurityContact{}, fmt.Errorf("find security contact by user id: %w", err)
	}

	return contact, nil
}

func (r *PostgresRepository) FindProfileByUserID(ctx context.Context, userID string) (UserProfile, error) {
	var profile UserProfile
	err := r.db.QueryRowContext(
		ctx,
		`SELECT u.id,
		        u.username,
		        u.role,
		        COALESCE(u.last_name, ''),
		        COALESCE(u.first_name, ''),
		        COALESCE(u.middle_name, ''),
		        COALESCE(mp.studio_name, ''),
		        COALESCE(u.city, ''),
		        COALESCE(u.bio, ''),
		        COALESCE('/api/v1/media/' || am.id::text, COALESCE(u.avatar_url, '')),
		        u.show_full_name_in_profile,
		        u.show_city_in_profile
		 FROM users u
		 LEFT JOIN master_profiles mp ON mp.user_id = u.id
		 LEFT JOIN media_objects am ON am.id = u.avatar_media_id
		   AND am.deleted_at IS NULL
		   AND am.kind = 'user_avatar'
		 WHERE u.id = $1 AND u.is_active = TRUE`,
		userID,
	).Scan(
		&profile.ID,
		&profile.Username,
		&profile.Role,
		&profile.LastName,
		&profile.FirstName,
		&profile.MiddleName,
		&profile.StudioName,
		&profile.City,
		&profile.Bio,
		&profile.AvatarURL,
		&profile.ShowFullNameInProfile,
		&profile.ShowCityInProfile,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return UserProfile{}, ErrUserNotFound
		}
		return UserProfile{}, fmt.Errorf("find profile by user id: %w", err)
	}

	return profile, nil
}

func (r *PostgresRepository) FindPublicProfileByUsername(ctx context.Context, username string) (PublicUserProfile, error) {
	var profile PublicUserProfile
	var fullName sql.NullString
	err := r.db.QueryRowContext(
		ctx,
		`SELECT u.id,
		        u.username,
		        u.role,
		        CASE WHEN u.show_full_name_in_profile THEN NULLIF(trim(CONCAT_WS(' ', u.last_name, u.first_name, u.middle_name)), '') ELSE NULL END,
		        CASE WHEN u.show_city_in_profile THEN COALESCE(u.city, '') ELSE '' END,
		        COALESCE(u.bio, ''),
		        COALESCE('/api/v1/media/' || am.id::text, COALESCE(u.avatar_url, ''))
		 FROM users u
		 LEFT JOIN media_objects am ON am.id = u.avatar_media_id
		   AND am.deleted_at IS NULL
		   AND am.kind = 'user_avatar'
		 WHERE lower(u.username::text) = lower($1)
		   AND u.is_active = TRUE`,
		strings.TrimSpace(username),
	).Scan(
		&profile.ID,
		&profile.Username,
		&profile.Role,
		&fullName,
		&profile.City,
		&profile.Bio,
		&profile.AvatarURL,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return PublicUserProfile{}, ErrUserNotFound
		}
		return PublicUserProfile{}, fmt.Errorf("find public profile by username: %w", err)
	}

	profile.FullName = strings.TrimSpace(fullName.String)
	profile.DisplayName = publicUserDisplayName(profile.Username, profile.FullName)
	return profile, nil
}

func (r *PostgresRepository) UpdateProfile(ctx context.Context, userID string, params UpdateProfileParams) (UserProfile, error) {
	var updatedID string
	err := r.db.QueryRowContext(
		ctx,
		`UPDATE users
		 SET last_name = $2,
		     first_name = $3,
		     middle_name = $4,
		     city = $5,
		     bio = $6,
		     show_full_name_in_profile = $7,
		     show_city_in_profile = $8,
		     full_name = $9,
		     updated_at = NOW()
		 WHERE id = $1 AND is_active = TRUE
		 RETURNING id::text`,
		userID,
		params.LastName,
		params.FirstName,
		params.MiddleName,
		params.City,
		params.Bio,
		params.ShowFullNameInProfile,
		params.ShowCityInProfile,
		params.FullName,
	).Scan(&updatedID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return UserProfile{}, ErrUserNotFound
		}
		return UserProfile{}, fmt.Errorf("update profile: %w", err)
	}

	if params.UpdateMasterStudio {
		if _, err := r.db.ExecContext(
			ctx,
			`UPDATE master_profiles
			 SET studio_name = $2
			 WHERE user_id = $1`,
			userID,
			params.StudioName,
		); err != nil {
			return UserProfile{}, fmt.Errorf("update master profile studio name: %w", err)
		}
	}

	return r.FindProfileByUserID(ctx, userID)
}

func (r *PostgresRepository) UpdatePasswordHash(ctx context.Context, userID string, passwordHash string) error {
	result, err := r.db.ExecContext(
		ctx,
		`UPDATE users
		 SET password_hash = $2,
		     updated_at = NOW()
		 WHERE id = $1 AND is_active = TRUE`,
		userID,
		passwordHash,
	)
	if err != nil {
		return fmt.Errorf("update password hash: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("read password update rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return ErrUserNotFound
	}

	return nil
}

func (r *PostgresRepository) UsernameExists(ctx context.Context, username string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users
			WHERE username = $1
		)`,
		username,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check username exists: %w", err)
	}

	return exists, nil
}

func (r *PostgresRepository) EmailExists(ctx context.Context, email string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users
			WHERE email = $1
		)`,
		email,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check email exists: %w", err)
	}

	return exists, nil
}

func (r *PostgresRepository) PhoneExists(ctx context.Context, phone string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users
			WHERE phone = $1
		)`,
		phone,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check phone exists: %w", err)
	}

	return exists, nil
}

func (r *PostgresRepository) EmailExistsForOtherUser(ctx context.Context, email string, userID string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users
			WHERE email = $1 AND id <> $2
		)`,
		email,
		userID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check email exists for other user: %w", err)
	}

	return exists, nil
}

func (r *PostgresRepository) PhoneExistsForOtherUser(ctx context.Context, phone string, userID string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users
			WHERE phone = $1 AND id <> $2
		)`,
		phone,
		userID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check phone exists for other user: %w", err)
	}

	return exists, nil
}

func (r *PostgresRepository) UpdateEmail(ctx context.Context, userID string, email string) (SecurityContact, error) {
	var contact SecurityContact
	err := r.db.QueryRowContext(
		ctx,
		`UPDATE users
		 SET email = $2,
		     updated_at = NOW()
		 WHERE id = $1 AND is_active = TRUE
		 RETURNING email, COALESCE(phone, '')`,
		userID,
		email,
	).Scan(&contact.Email, &contact.Phone)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return SecurityContact{}, ErrUserNotFound
		}
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return SecurityContact{}, ErrEmailAlreadyExists
		}
		return SecurityContact{}, fmt.Errorf("update email: %w", err)
	}

	return contact, nil
}

func (r *PostgresRepository) UpdatePhone(ctx context.Context, userID string, phone string) (SecurityContact, error) {
	var contact SecurityContact
	err := r.db.QueryRowContext(
		ctx,
		`UPDATE users
		 SET phone = $2,
		     updated_at = NOW()
		 WHERE id = $1 AND is_active = TRUE
		 RETURNING email, COALESCE(phone, '')`,
		userID,
		phone,
	).Scan(&contact.Email, &contact.Phone)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return SecurityContact{}, ErrUserNotFound
		}
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return SecurityContact{}, ErrPhoneAlreadyExists
		}
		return SecurityContact{}, fmt.Errorf("update phone: %w", err)
	}

	return contact, nil
}

func (r *PostgresRepository) DeactivateUserAndDeleteSessions(ctx context.Context, userID string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin deactivate user transaction: %w", err)
	}

	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	result, err := tx.ExecContext(
		ctx,
		`UPDATE users
		 SET is_active = FALSE,
		     updated_at = NOW()
		 WHERE id = $1 AND is_active = TRUE`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("deactivate user: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("read deactivate user rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return ErrUserNotFound
	}

	if _, err = tx.ExecContext(ctx, `DELETE FROM auth_sessions WHERE user_id = $1`, userID); err != nil {
		return fmt.Errorf("delete user sessions: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit deactivate user transaction: %w", err)
	}

	return nil
}

func (r *PostgresRepository) SearchMasters(ctx context.Context, query string, limit int) ([]PublicMasterProfile, error) {
	if limit <= 0 {
		limit = 100
	}
	if limit > 200 {
		limit = 200
	}

	normalized := "%" + query + "%"
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT u.id,
		        u.username,
		        COALESCE('/api/v1/media/' || am.id::text, COALESCE(u.avatar_url, '')),
		        COALESCE(mp.studio_name, ''),
		        CASE WHEN u.show_full_name_in_profile THEN NULLIF(trim(CONCAT_WS(' ', u.last_name, u.first_name, u.middle_name)), '') ELSE NULL END,
		        u.role,
		        CASE WHEN u.show_city_in_profile THEN COALESCE(u.city, '') ELSE '' END,
		        COALESCE(u.bio, ''),
		        mp.category,
		        mp.min_session_price,
		        mp.hourly_rate,
		        mp.rating::float8,
		        mp.review_count,
		        mp.is_verified
		 FROM users u
		 JOIN master_profiles mp ON mp.user_id = u.id
		 LEFT JOIN media_objects am ON am.id = u.avatar_media_id
		   AND am.deleted_at IS NULL
		   AND am.kind = 'user_avatar'
		 WHERE u.is_active = TRUE
		   AND u.role = 'master'
		   AND (
		        $1 = '%%'
		        OR u.username ILIKE $1
		        OR mp.studio_name ILIKE $1
		        OR (
		          u.show_full_name_in_profile
		          AND NULLIF(trim(CONCAT_WS(' ', u.last_name, u.first_name, u.middle_name)), '') ILIKE $1
		        )
		        OR (u.show_city_in_profile AND u.city ILIKE $1)
		        OR EXISTS (
		          SELECT 1
		          FROM master_styles ms
		          WHERE ms.master_id = u.id AND ms.style ILIKE $1
		        )
		        OR EXISTS (
		          SELECT 1
		          FROM services s
		          WHERE s.master_id = u.id
		            AND s.is_active = TRUE
		            AND (s.title ILIKE $1 OR COALESCE(s.description, '') ILIKE $1)
		        )
		   )
		 ORDER BY mp.rating DESC, mp.review_count DESC, u.username
		 LIMIT $2`,
		normalized,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("search masters: %w", err)
	}
	defer rows.Close()

	masters := []PublicMasterProfile{}
	for rows.Next() {
		var master PublicMasterProfile
		var fullName sql.NullString
		if err := rows.Scan(
			&master.ID,
			&master.Username,
			&master.AvatarURL,
			&master.StudioName,
			&fullName,
			&master.Role,
			&master.City,
			&master.Bio,
			&master.Category,
			&master.MinSessionPrice,
			&master.HourlyRate,
			&master.Rating,
			&master.ReviewCount,
			&master.IsVerified,
		); err != nil {
			return nil, fmt.Errorf("scan master search result: %w", err)
		}
		master.FullName = strings.TrimSpace(fullName.String)
		master.DisplayName = publicDisplayName(master.Username, master.FullName, master.StudioName)
		if err := r.hydratePublicMaster(ctx, &master); err != nil {
			return nil, err
		}
		masters = append(masters, master)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate master search results: %w", err)
	}

	return masters, nil
}

func (r *PostgresRepository) FindPublicMasterByUsername(ctx context.Context, username string) (PublicMasterProfile, error) {
	var master PublicMasterProfile
	var fullName sql.NullString
	err := r.db.QueryRowContext(
		ctx,
		`SELECT u.id,
		        u.username,
		        COALESCE('/api/v1/media/' || am.id::text, COALESCE(u.avatar_url, '')),
		        COALESCE(mp.studio_name, ''),
		        CASE WHEN u.show_full_name_in_profile THEN NULLIF(trim(CONCAT_WS(' ', u.last_name, u.first_name, u.middle_name)), '') ELSE NULL END,
		        u.role,
		        CASE WHEN u.show_city_in_profile THEN COALESCE(u.city, '') ELSE '' END,
		        COALESCE(u.bio, ''),
		        mp.category,
		        mp.min_session_price,
		        mp.hourly_rate,
		        mp.rating::float8,
		        mp.review_count,
		        mp.is_verified
		 FROM users u
		 JOIN master_profiles mp ON mp.user_id = u.id
		 LEFT JOIN media_objects am ON am.id = u.avatar_media_id
		   AND am.deleted_at IS NULL
		   AND am.kind = 'user_avatar'
		 WHERE u.is_active = TRUE
		   AND u.role = 'master'
		   AND lower(u.username::text) = lower($1)`,
		username,
	).Scan(
		&master.ID,
		&master.Username,
		&master.AvatarURL,
		&master.StudioName,
		&fullName,
		&master.Role,
		&master.City,
		&master.Bio,
		&master.Category,
		&master.MinSessionPrice,
		&master.HourlyRate,
		&master.Rating,
		&master.ReviewCount,
		&master.IsVerified,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return PublicMasterProfile{}, ErrUserNotFound
		}
		return PublicMasterProfile{}, fmt.Errorf("find public master by username: %w", err)
	}

	master.FullName = strings.TrimSpace(fullName.String)
	master.DisplayName = publicDisplayName(master.Username, master.FullName, master.StudioName)
	if err := r.hydratePublicMaster(ctx, &master); err != nil {
		return PublicMasterProfile{}, err
	}

	return master, nil
}

func (r *PostgresRepository) ListFavoriteMasters(ctx context.Context, userID string) ([]PublicMasterProfile, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT u.id,
		        u.username,
		        COALESCE('/api/v1/media/' || am.id::text, COALESCE(u.avatar_url, '')),
		        COALESCE(mp.studio_name, ''),
		        CASE WHEN u.show_full_name_in_profile THEN NULLIF(trim(CONCAT_WS(' ', u.last_name, u.first_name, u.middle_name)), '') ELSE NULL END,
		        u.role,
		        CASE WHEN u.show_city_in_profile THEN COALESCE(u.city, '') ELSE '' END,
		        COALESCE(u.bio, ''),
		        mp.category,
		        mp.min_session_price,
		        mp.hourly_rate,
		        mp.rating::float8,
		        mp.review_count,
		        mp.is_verified
		 FROM favorite_masters fm
		 JOIN users u ON u.id = fm.master_id
		 JOIN master_profiles mp ON mp.user_id = u.id
		 LEFT JOIN media_objects am ON am.id = u.avatar_media_id
		   AND am.deleted_at IS NULL
		   AND am.kind = 'user_avatar'
		 WHERE fm.user_id = $1
		   AND u.is_active = TRUE
		   AND u.role = 'master'
		 ORDER BY fm.created_at DESC, u.username`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("list favorite masters: %w", err)
	}
	defer rows.Close()

	masters := []PublicMasterProfile{}
	for rows.Next() {
		var master PublicMasterProfile
		var fullName sql.NullString
		if err := rows.Scan(
			&master.ID,
			&master.Username,
			&master.AvatarURL,
			&master.StudioName,
			&fullName,
			&master.Role,
			&master.City,
			&master.Bio,
			&master.Category,
			&master.MinSessionPrice,
			&master.HourlyRate,
			&master.Rating,
			&master.ReviewCount,
			&master.IsVerified,
		); err != nil {
			return nil, fmt.Errorf("scan favorite master: %w", err)
		}
		master.FullName = strings.TrimSpace(fullName.String)
		master.DisplayName = publicDisplayName(master.Username, master.FullName, master.StudioName)
		master.IsFavorite = true
		if err := r.hydratePublicMaster(ctx, &master); err != nil {
			return nil, err
		}
		masters = append(masters, master)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate favorite masters: %w", err)
	}

	return masters, nil
}

func (r *PostgresRepository) AddFavoriteMaster(ctx context.Context, userID string, masterID string) error {
	if strings.TrimSpace(userID) == strings.TrimSpace(masterID) {
		return ErrCannotFavoriteSelf
	}

	var exists bool
	if err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS (
			SELECT 1
			FROM users u
			JOIN master_profiles mp ON mp.user_id = u.id
			WHERE u.id = $1 AND u.role = 'master' AND u.is_active = TRUE
		)`,
		masterID,
	).Scan(&exists); err != nil {
		return fmt.Errorf("check favorite master target: %w", err)
	}
	if !exists {
		return ErrUserNotFound
	}

	_, err := r.db.ExecContext(
		ctx,
		`INSERT INTO favorite_masters (user_id, master_id)
		 VALUES ($1, $2)
		 ON CONFLICT (user_id, master_id) DO NOTHING`,
		userID,
		masterID,
	)
	if err != nil {
		return fmt.Errorf("add favorite master: %w", err)
	}

	return nil
}

func (r *PostgresRepository) RemoveFavoriteMaster(ctx context.Context, userID string, masterID string) error {
	_, err := r.db.ExecContext(
		ctx,
		`DELETE FROM favorite_masters
		 WHERE user_id = $1 AND master_id = $2`,
		userID,
		masterID,
	)
	if err != nil {
		return fmt.Errorf("remove favorite master: %w", err)
	}

	return nil
}

func publicDisplayName(username string, fullName string, _ string) string {
	if strings.TrimSpace(fullName) != "" {
		return strings.TrimSpace(fullName)
	}
	username = strings.TrimSpace(username)
	if username == "" {
		return "@master"
	}
	if strings.HasPrefix(username, "@") {
		return username
	}
	return "@" + username
}

func publicUserDisplayName(username string, fullName string) string {
	if strings.TrimSpace(fullName) != "" {
		return strings.TrimSpace(fullName)
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

func (r *PostgresRepository) hydratePublicMaster(ctx context.Context, master *PublicMasterProfile) error {
	styles, err := r.publicMasterStyles(ctx, master.ID)
	if err != nil {
		return err
	}
	services, err := r.publicMasterServices(ctx, master.ID)
	if err != nil {
		return err
	}
	schedule, err := r.publicMasterSchedule(ctx, master.ID)
	if err != nil {
		return err
	}
	master.Styles = styles
	master.Services = services
	master.Schedule = schedule
	return nil
}

func (r *PostgresRepository) publicMasterStyles(ctx context.Context, masterID string) ([]string, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT style
		 FROM master_styles
		 WHERE master_id = $1
		 ORDER BY style`,
		masterID,
	)
	if err != nil {
		return nil, fmt.Errorf("load public master styles: %w", err)
	}
	defer rows.Close()

	styles := []string{}
	for rows.Next() {
		var style string
		if err := rows.Scan(&style); err != nil {
			return nil, fmt.Errorf("scan public master style: %w", err)
		}
		styles = append(styles, style)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate public master styles: %w", err)
	}
	return styles, nil
}

func (r *PostgresRepository) publicMasterServices(ctx context.Context, masterID string) ([]PublicMasterService, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id,
		        title,
		        COALESCE(description, ''),
		        service_type,
		        duration_minutes,
		        COALESCE(price_min, 0)::int,
		        use_auto_price,
		        from_price
		 FROM services
		 WHERE master_id = $1 AND is_active = TRUE
		 ORDER BY created_at, title`,
		masterID,
	)
	if err != nil {
		return nil, fmt.Errorf("load public master services: %w", err)
	}
	defer rows.Close()

	services := []PublicMasterService{}
	for rows.Next() {
		var service PublicMasterService
		var durationMinutes sql.NullInt64
		if err := rows.Scan(
			&service.ID,
			&service.Name,
			&service.Description,
			&service.Type,
			&durationMinutes,
			&service.Price,
			&service.UseAutoPrice,
			&service.FromPrice,
		); err != nil {
			return nil, fmt.Errorf("scan public master service: %w", err)
		}
		if durationMinutes.Valid {
			hours := float64(durationMinutes.Int64) / 60
			service.DurationHours = &hours
		}
		services = append(services, service)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate public master services: %w", err)
	}
	return services, nil
}

func (r *PostgresRepository) publicMasterSchedule(ctx context.Context, masterID string) ([]PublicMasterScheduleDay, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT day_of_week, is_enabled, intervals
		 FROM master_work_schedule
		 WHERE master_id = $1
		 ORDER BY day_of_week`,
		masterID,
	)
	if err != nil {
		return nil, fmt.Errorf("load public master schedule: %w", err)
	}
	defer rows.Close()

	var days []PublicMasterScheduleDay
	for rows.Next() {
		var day PublicMasterScheduleDay
		var raw []byte
		if err := rows.Scan(&day.DayIndex, &day.Enabled, &raw); err != nil {
			return nil, fmt.Errorf("scan public master schedule: %w", err)
		}
		if len(raw) > 0 {
			if err := json.Unmarshal(raw, &day.Intervals); err != nil {
				return nil, fmt.Errorf("parse public master schedule: %w", err)
			}
		}
		days = append(days, day)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate public master schedule: %w", err)
	}
	if len(days) == 0 {
		return defaultPublicMasterSchedule(), nil
	}
	return days, nil
}

func defaultPublicMasterSchedule() []PublicMasterScheduleDay {
	workdayIntervals := []PublicMasterScheduleInterval{
		{Type: "work", StartMinute: 9 * 60, EndMinute: 13 * 60},
		{Type: "break", StartMinute: 13 * 60, EndMinute: 14 * 60},
		{Type: "work", StartMinute: 14 * 60, EndMinute: 16 * 60},
		{Type: "work", StartMinute: 18 * 60, EndMinute: 20 * 60},
	}
	return []PublicMasterScheduleDay{
		{DayIndex: 0, Enabled: true, Intervals: workdayIntervals},
		{DayIndex: 1, Enabled: true, Intervals: workdayIntervals},
		{DayIndex: 2, Enabled: true, Intervals: workdayIntervals},
		{DayIndex: 3, Enabled: true, Intervals: workdayIntervals},
		{DayIndex: 4, Enabled: true, Intervals: workdayIntervals},
		{DayIndex: 5, Enabled: true, Intervals: workdayIntervals},
		{DayIndex: 6, Enabled: false, Intervals: []PublicMasterScheduleInterval{}},
	}
}

func (r *PostgresRepository) CreateSession(ctx context.Context, params CreateSessionParams) error {
	var ipValue any
	if params.IPAddress != "" {
		ipValue = net.ParseIP(params.IPAddress)
	}

	_, err := r.db.ExecContext(
		ctx,
		`INSERT INTO auth_sessions (user_id, session_hash, expires_at, user_agent, ip_address)
		 VALUES ($1, $2, $3, $4, $5)`,
		params.UserID,
		params.SessionHash,
		params.ExpiresAt,
		params.UserAgent,
		ipValue,
	)
	if err != nil {
		return fmt.Errorf("create auth session: %w", err)
	}

	return nil
}

func (r *PostgresRepository) FindUserBySessionHash(ctx context.Context, sessionHash string) (AuthenticatedUser, error) {
	var user AuthenticatedUser
	err := r.db.QueryRowContext(
		ctx,
		`SELECT u.id, u.username, COALESCE(mp.studio_name, ''), u.email, u.role, u.public_key
		 FROM auth_sessions s
		 JOIN users u ON u.id = s.user_id
		 LEFT JOIN master_profiles mp ON mp.user_id = u.id
		 WHERE s.session_hash = $1
		   AND s.expires_at > NOW()
		   AND u.is_active = TRUE`,
		sessionHash,
	).Scan(
		&user.ID,
		&user.Username,
		&user.StudioName,
		&user.Email,
		&user.Role,
		&user.PublicKey,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return AuthenticatedUser{}, ErrSessionNotFound
		}
		return AuthenticatedUser{}, fmt.Errorf("find user by session hash: %w", err)
	}

	_, _ = r.db.ExecContext(
		ctx,
		`UPDATE auth_sessions
		 SET last_used_at = NOW()
		 WHERE session_hash = $1`,
		sessionHash,
	)

	return user, nil
}

func (r *PostgresRepository) DeleteSessionByHash(ctx context.Context, sessionHash string) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM auth_sessions WHERE session_hash = $1`, sessionHash)
	if err != nil {
		return fmt.Errorf("delete auth session: %w", err)
	}

	return nil
}
