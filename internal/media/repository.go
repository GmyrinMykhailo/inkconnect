package media

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

type Repository interface {
	ReplaceUserAvatar(ctx context.Context, object Object) (Object, *Object, error)
	ClearUserAvatar(ctx context.Context, userID string) (*Object, error)
	FindActiveObjectByID(ctx context.Context, mediaID string) (Object, error)
}

type PostgresRepository struct {
	db *sql.DB
}

func NewPostgresRepository(db *sql.DB) *PostgresRepository {
	return &PostgresRepository{db: db}
}

func (r *PostgresRepository) ReplaceUserAvatar(ctx context.Context, object Object) (Object, *Object, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return Object{}, nil, fmt.Errorf("begin replace avatar transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	oldObject, err := currentAvatarForUpdate(ctx, tx, object.OwnerUserID)
	if err != nil {
		return Object{}, nil, err
	}

	var saved Object
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO media_objects (
		     id,
		     owner_user_id,
		     bucket,
		     object_key,
		     kind,
		     content_type,
		     size_bytes
		 )
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING id::text,
		           owner_user_id::text,
		           bucket,
		           object_key,
		           kind,
		           content_type,
		           size_bytes,
		           created_at,
		           updated_at`,
		object.ID,
		object.OwnerUserID,
		object.Bucket,
		object.ObjectKey,
		object.Kind,
		object.ContentType,
		object.SizeBytes,
	).Scan(
		&saved.ID,
		&saved.OwnerUserID,
		&saved.Bucket,
		&saved.ObjectKey,
		&saved.Kind,
		&saved.ContentType,
		&saved.SizeBytes,
		&saved.CreatedAt,
		&saved.UpdatedAt,
	)
	if err != nil {
		return Object{}, nil, fmt.Errorf("insert avatar media object: %w", err)
	}

	result, err := tx.ExecContext(
		ctx,
		`UPDATE users
		 SET avatar_media_id = $2,
		     updated_at = NOW()
		 WHERE id = $1 AND is_active = TRUE`,
		object.OwnerUserID,
		saved.ID,
	)
	if err != nil {
		return Object{}, nil, fmt.Errorf("update user avatar media id: %w", err)
	}
	if affected, err := result.RowsAffected(); err != nil {
		return Object{}, nil, fmt.Errorf("read user avatar update rows affected: %w", err)
	} else if affected == 0 {
		return Object{}, nil, ErrOwnerNotFound
	}

	if oldObject != nil {
		if _, err = tx.ExecContext(
			ctx,
			`UPDATE media_objects
			 SET deleted_at = NOW(),
			     updated_at = NOW()
			 WHERE id = $1`,
			oldObject.ID,
		); err != nil {
			return Object{}, nil, fmt.Errorf("soft delete old avatar media object: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return Object{}, nil, fmt.Errorf("commit replace avatar transaction: %w", err)
	}

	return saved, oldObject, nil
}

func (r *PostgresRepository) ClearUserAvatar(ctx context.Context, userID string) (*Object, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin clear avatar transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	oldObject, err := currentAvatarForUpdate(ctx, tx, userID)
	if err != nil {
		return nil, err
	}
	if oldObject == nil {
		if err = tx.Commit(); err != nil {
			return nil, fmt.Errorf("commit clear avatar transaction: %w", err)
		}
		return nil, nil
	}

	result, err := tx.ExecContext(
		ctx,
		`UPDATE users
		 SET avatar_media_id = NULL,
		     updated_at = NOW()
		 WHERE id = $1 AND is_active = TRUE`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("clear user avatar media id: %w", err)
	}
	if affected, err := result.RowsAffected(); err != nil {
		return nil, fmt.Errorf("read clear avatar rows affected: %w", err)
	} else if affected == 0 {
		return nil, ErrOwnerNotFound
	}

	if _, err = tx.ExecContext(
		ctx,
		`UPDATE media_objects
		 SET deleted_at = NOW(),
		     updated_at = NOW()
		 WHERE id = $1`,
		oldObject.ID,
	); err != nil {
		return nil, fmt.Errorf("soft delete avatar media object: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit clear avatar transaction: %w", err)
	}

	return oldObject, nil
}

func (r *PostgresRepository) FindActiveObjectByID(ctx context.Context, mediaID string) (Object, error) {
	var object Object
	err := r.db.QueryRowContext(
		ctx,
		`SELECT id::text,
		        owner_user_id::text,
		        bucket,
		        object_key,
		        kind,
		        content_type,
		        size_bytes,
		        created_at,
		        updated_at
		 FROM media_objects
		 WHERE id::text = $1
		   AND deleted_at IS NULL`,
		mediaID,
	).Scan(
		&object.ID,
		&object.OwnerUserID,
		&object.Bucket,
		&object.ObjectKey,
		&object.Kind,
		&object.ContentType,
		&object.SizeBytes,
		&object.CreatedAt,
		&object.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Object{}, ErrMediaNotFound
		}
		return Object{}, fmt.Errorf("find active media object: %w", err)
	}

	return object, nil
}

func currentAvatarForUpdate(ctx context.Context, tx *sql.Tx, userID string) (*Object, error) {
	var object Object
	var id sql.NullString
	var ownerUserID sql.NullString
	var bucket sql.NullString
	var objectKey sql.NullString
	var kind sql.NullString
	var contentType sql.NullString
	var sizeBytes sql.NullInt64
	var createdAt sql.NullTime
	var updatedAt sql.NullTime

	err := tx.QueryRowContext(
		ctx,
		`SELECT mo.id::text,
		        mo.owner_user_id::text,
		        mo.bucket,
		        mo.object_key,
		        mo.kind,
		        mo.content_type,
		        mo.size_bytes,
		        mo.created_at,
		        mo.updated_at
		 FROM users u
		 LEFT JOIN media_objects mo ON mo.id = u.avatar_media_id
		   AND mo.deleted_at IS NULL
		   AND mo.kind = 'user_avatar'
		 WHERE u.id = $1 AND u.is_active = TRUE
		 FOR UPDATE OF u`,
		userID,
	).Scan(
		&id,
		&ownerUserID,
		&bucket,
		&objectKey,
		&kind,
		&contentType,
		&sizeBytes,
		&createdAt,
		&updatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrOwnerNotFound
		}
		return nil, fmt.Errorf("load current avatar media object: %w", err)
	}
	if !id.Valid {
		return nil, nil
	}

	object.ID = id.String
	object.OwnerUserID = ownerUserID.String
	object.Bucket = bucket.String
	object.ObjectKey = objectKey.String
	object.Kind = kind.String
	object.ContentType = contentType.String
	if sizeBytes.Valid {
		object.SizeBytes = sizeBytes.Int64
	}
	if createdAt.Valid {
		object.CreatedAt = createdAt.Time
	}
	if updatedAt.Valid {
		object.UpdatedAt = updatedAt.Time
	}

	return &object, nil
}
