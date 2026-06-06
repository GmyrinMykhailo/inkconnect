package publications

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	mediastore "inkconnect/internal/media"
)

type Repository interface {
	IsMaster(ctx context.Context, userID string) (bool, error)
	Create(ctx context.Context, masterID string, input CreatePublicationInput) (Publication, error)
	CreateWithMediaObjects(ctx context.Context, masterID string, publicationID string, input CreatePublicationInput, objects []mediastore.Object) (Publication, error)
	ListByMasterUsername(ctx context.Context, username string) ([]Publication, error)
	FindByID(ctx context.Context, publicationID string) (Publication, error)
	SoftDelete(ctx context.Context, masterID string, publicationID string) error
}

type PostgresRepository struct {
	db *sql.DB
}

func NewPostgresRepository(db *sql.DB) *PostgresRepository {
	return &PostgresRepository{db: db}
}

func (r *PostgresRepository) IsMaster(ctx context.Context, userID string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(
		ctx,
		`SELECT EXISTS (
		     SELECT 1
		     FROM users
		     WHERE id = $1
		       AND role = 'master'
		       AND is_active = TRUE
		 )`,
		userID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check publication master account: %w", err)
	}

	return exists, nil
}

func (r *PostgresRepository) Create(ctx context.Context, masterID string, input CreatePublicationInput) (Publication, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return Publication{}, fmt.Errorf("begin create publication transaction: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var publicationID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO master_publications (
		     master_id,
		     description,
		     comments_disabled
		 )
		 VALUES ($1, $2, $3)
		 RETURNING id::text`,
		masterID,
		input.Description,
		input.CommentsDisabled,
	).Scan(&publicationID)
	if err != nil {
		return Publication{}, fmt.Errorf("insert publication: %w", err)
	}

	for _, item := range input.Media {
		var linkID string
		err = tx.QueryRowContext(
			ctx,
			`INSERT INTO master_publication_media (
			     publication_id,
			     media_id,
			     sort_order,
			     is_cover
			 )
			 SELECT $1, mo.id, $3, $4
			 FROM media_objects mo
			 WHERE mo.id = $2
			   AND mo.owner_user_id = $5
			   AND mo.kind = $6
			   AND mo.deleted_at IS NULL
			 RETURNING id::text`,
			publicationID,
			item.MediaID,
			item.SortOrder,
			item.IsCover,
			masterID,
			mediastore.KindMasterPublicationPhoto,
		).Scan(&linkID)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return Publication{}, ErrPublicationMediaNotFound
			}
			return Publication{}, fmt.Errorf("insert publication media: %w", err)
		}
	}

	for _, style := range input.Styles {
		_, err = tx.ExecContext(
			ctx,
			`INSERT INTO master_publication_styles (
			     publication_id,
			     style
			 )
			 VALUES ($1, $2)
			 ON CONFLICT (publication_id, style) DO NOTHING`,
			publicationID,
			style,
		)
		if err != nil {
			return Publication{}, fmt.Errorf("insert publication style: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return Publication{}, fmt.Errorf("commit create publication transaction: %w", err)
	}

	return r.FindByID(ctx, publicationID)
}

func (r *PostgresRepository) CreateWithMediaObjects(ctx context.Context, masterID string, publicationID string, input CreatePublicationInput, objects []mediastore.Object) (Publication, error) {
	if publicationID == "" || len(input.Media) != len(objects) {
		return Publication{}, ErrPublicationInvalidInput
	}

	objectsByID := make(map[string]mediastore.Object, len(objects))
	for _, object := range objects {
		if object.ID == "" || objectsByID[object.ID].ID != "" {
			return Publication{}, ErrPublicationInvalidInput
		}
		objectsByID[object.ID] = object
	}
	for _, item := range input.Media {
		if _, ok := objectsByID[item.MediaID]; !ok {
			return Publication{}, ErrPublicationInvalidInput
		}
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return Publication{}, fmt.Errorf("begin create uploaded publication transaction: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var savedPublicationID string
	err = tx.QueryRowContext(
		ctx,
		`INSERT INTO master_publications (
		     id,
		     master_id,
		     description,
		     comments_disabled
		 )
		 VALUES ($1, $2, $3, $4)
		 RETURNING id::text`,
		publicationID,
		masterID,
		input.Description,
		input.CommentsDisabled,
	).Scan(&savedPublicationID)
	if err != nil {
		return Publication{}, fmt.Errorf("insert uploaded publication: %w", err)
	}

	for _, object := range objects {
		_, err = tx.ExecContext(
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
			 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			object.ID,
			masterID,
			object.Bucket,
			object.ObjectKey,
			object.Kind,
			object.ContentType,
			object.SizeBytes,
		)
		if err != nil {
			return Publication{}, fmt.Errorf("insert publication media object: %w", err)
		}
	}

	for _, item := range input.Media {
		_, err = tx.ExecContext(
			ctx,
			`INSERT INTO master_publication_media (
			     publication_id,
			     media_id,
			     sort_order,
			     is_cover
			 )
			 VALUES ($1, $2, $3, $4)`,
			savedPublicationID,
			item.MediaID,
			item.SortOrder,
			item.IsCover,
		)
		if err != nil {
			return Publication{}, fmt.Errorf("insert uploaded publication media: %w", err)
		}
	}

	for _, style := range input.Styles {
		_, err = tx.ExecContext(
			ctx,
			`INSERT INTO master_publication_styles (
			     publication_id,
			     style
			 )
			 VALUES ($1, $2)
			 ON CONFLICT (publication_id, style) DO NOTHING`,
			savedPublicationID,
			style,
		)
		if err != nil {
			return Publication{}, fmt.Errorf("insert uploaded publication style: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return Publication{}, fmt.Errorf("commit create uploaded publication transaction: %w", err)
	}

	return r.FindByID(ctx, savedPublicationID)
}

func (r *PostgresRepository) ListByMasterUsername(ctx context.Context, username string) ([]Publication, error) {
	var masterID string
	err := r.db.QueryRowContext(
		ctx,
		`SELECT id::text
		 FROM users
		 WHERE username = $1
		   AND role = 'master'
		   AND is_active = TRUE`,
		username,
	).Scan(&masterID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrPublicationNotFound
		}
		return nil, fmt.Errorf("find publication master by username: %w", err)
	}

	rows, err := r.db.QueryContext(
		ctx,
		`SELECT id::text,
		        master_id::text,
		        description,
		        comments_disabled,
		        created_at,
		        updated_at
		 FROM master_publications
		 WHERE master_id = $1
		   AND deleted_at IS NULL
		 ORDER BY created_at DESC, id DESC`,
		masterID,
	)
	if err != nil {
		return nil, fmt.Errorf("list master publications: %w", err)
	}
	defer rows.Close()

	publications := []Publication{}
	for rows.Next() {
		publication, err := scanPublicationRow(rows)
		if err != nil {
			return nil, err
		}
		hydrated, err := r.hydratePublication(ctx, publication)
		if err != nil {
			return nil, err
		}
		publications = append(publications, hydrated)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate master publications: %w", err)
	}

	return publications, nil
}

func (r *PostgresRepository) FindByID(ctx context.Context, publicationID string) (Publication, error) {
	row := r.db.QueryRowContext(
		ctx,
		`SELECT id::text,
		        master_id::text,
		        description,
		        comments_disabled,
		        created_at,
		        updated_at
		 FROM master_publications
		 WHERE id = $1
		   AND deleted_at IS NULL`,
		publicationID,
	)

	publication, err := scanPublicationRow(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Publication{}, ErrPublicationNotFound
		}
		return Publication{}, err
	}

	return r.hydratePublication(ctx, publication)
}

func (r *PostgresRepository) SoftDelete(ctx context.Context, masterID string, publicationID string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin delete publication transaction: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var deletedID string
	err = tx.QueryRowContext(
		ctx,
		`UPDATE master_publications
		 SET deleted_at = NOW()
		 WHERE id = $1
		   AND master_id = $2
		   AND deleted_at IS NULL
		 RETURNING id::text`,
		publicationID,
		masterID,
	).Scan(&deletedID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrPublicationNotFound
		}
		return fmt.Errorf("soft delete publication: %w", err)
	}

	_, err = tx.ExecContext(
		ctx,
		`UPDATE media_objects
		 SET deleted_at = NOW()
		 WHERE id IN (
		     SELECT media_id
		     FROM master_publication_media
		     WHERE publication_id = $1
		 )
		   AND owner_user_id = $2
		   AND kind = $3
		   AND deleted_at IS NULL`,
		publicationID,
		masterID,
		mediastore.KindMasterPublicationPhoto,
	)
	if err != nil {
		return fmt.Errorf("soft delete publication media: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit delete publication transaction: %w", err)
	}

	return nil
}

type publicationScanner interface {
	Scan(dest ...any) error
}

func scanPublicationRow(scanner publicationScanner) (Publication, error) {
	var publication Publication
	err := scanner.Scan(
		&publication.ID,
		&publication.MasterID,
		&publication.Description,
		&publication.CommentsDisabled,
		&publication.CreatedAt,
		&publication.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Publication{}, err
		}
		return Publication{}, fmt.Errorf("scan publication: %w", err)
	}
	return publication, nil
}

func (r *PostgresRepository) hydratePublication(ctx context.Context, publication Publication) (Publication, error) {
	media, err := r.listPublicationMedia(ctx, publication.ID)
	if err != nil {
		return Publication{}, err
	}
	publication.Media = media
	for _, item := range media {
		if item.IsCover {
			publication.CoverImageURL = item.ImageURL
			break
		}
	}

	styles, err := r.listPublicationStyles(ctx, publication.ID)
	if err != nil {
		return Publication{}, err
	}
	publication.Styles = styles

	return publication, nil
}

func (r *PostgresRepository) listPublicationMedia(ctx context.Context, publicationID string) ([]PublicationMedia, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT pm.id::text,
		        pm.media_id::text,
		        pm.sort_order,
		        pm.is_cover,
		        mo.content_type,
		        mo.size_bytes
		 FROM master_publication_media pm
		 JOIN media_objects mo ON mo.id = pm.media_id
		 WHERE pm.publication_id = $1
		   AND mo.deleted_at IS NULL
		 ORDER BY pm.sort_order ASC, pm.id ASC`,
		publicationID,
	)
	if err != nil {
		return nil, fmt.Errorf("list publication media: %w", err)
	}
	defer rows.Close()

	items := []PublicationMedia{}
	for rows.Next() {
		var item PublicationMedia
		if err := rows.Scan(
			&item.ID,
			&item.MediaID,
			&item.SortOrder,
			&item.IsCover,
			&item.ContentType,
			&item.SizeBytes,
		); err != nil {
			return nil, fmt.Errorf("scan publication media: %w", err)
		}
		item.ImageURL = "/api/v1/media/" + item.MediaID
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate publication media: %w", err)
	}

	return items, nil
}

func (r *PostgresRepository) listPublicationStyles(ctx context.Context, publicationID string) ([]string, error) {
	rows, err := r.db.QueryContext(
		ctx,
		`SELECT style
		 FROM master_publication_styles
		 WHERE publication_id = $1
		 ORDER BY created_at ASC, style ASC`,
		publicationID,
	)
	if err != nil {
		return nil, fmt.Errorf("list publication styles: %w", err)
	}
	defer rows.Close()

	styles := []string{}
	for rows.Next() {
		var style string
		if err := rows.Scan(&style); err != nil {
			return nil, fmt.Errorf("scan publication style: %w", err)
		}
		styles = append(styles, style)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate publication styles: %w", err)
	}

	return styles, nil
}
