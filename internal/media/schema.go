package media

import (
	"context"
	"database/sql"
	"fmt"
)

func EnsureMediaSchema(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(
		ctx,
		`CREATE TABLE IF NOT EXISTS media_objects (
		     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		     owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		     bucket TEXT NOT NULL,
		     object_key TEXT NOT NULL,
		     kind TEXT NOT NULL,
		     content_type TEXT NOT NULL,
		     size_bytes BIGINT NOT NULL DEFAULT 0,
		     deleted_at TIMESTAMPTZ,
		     created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		     updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		     CONSTRAINT media_objects_bucket_chk
		         CHECK (btrim(bucket) <> ''),
		     CONSTRAINT media_objects_object_key_chk
		         CHECK (btrim(object_key) <> ''),
		     CONSTRAINT media_objects_kind_chk
		         CHECK (kind IN ('user_avatar', 'master_portfolio', 'master_publication_photo')),
		     CONSTRAINT media_objects_content_type_chk
		         CHECK (btrim(content_type) <> ''),
		     CONSTRAINT media_objects_size_bytes_chk
		         CHECK (size_bytes >= 0)
		 );

		 ALTER TABLE users
		     ADD COLUMN IF NOT EXISTS avatar_media_id UUID;

		 DO $$
		 BEGIN
		     IF NOT EXISTS (
		         SELECT 1
		         FROM pg_constraint
		         WHERE conname = 'users_avatar_media_id_fkey'
		           AND conrelid = 'users'::regclass
		     ) THEN
		         ALTER TABLE users
		             ADD CONSTRAINT users_avatar_media_id_fkey
		             FOREIGN KEY (avatar_media_id) REFERENCES media_objects(id) ON DELETE SET NULL;
		     END IF;
		 END $$;

		 ALTER TABLE media_objects
		     DROP CONSTRAINT IF EXISTS media_objects_kind_chk;

		 ALTER TABLE media_objects
		     ADD CONSTRAINT media_objects_kind_chk
		         CHECK (kind IN ('user_avatar', 'master_portfolio', 'master_publication_photo'));

		 CREATE UNIQUE INDEX IF NOT EXISTS idx_media_objects_bucket_object_key
		     ON media_objects(bucket, object_key);

		 CREATE INDEX IF NOT EXISTS idx_media_objects_owner_kind_created
		     ON media_objects(owner_user_id, kind, created_at DESC);

		 CREATE INDEX IF NOT EXISTS idx_media_objects_active_kind
		     ON media_objects(kind, created_at DESC)
		     WHERE deleted_at IS NULL;

		 CREATE INDEX IF NOT EXISTS idx_users_avatar_media_id
		     ON users(avatar_media_id)
		     WHERE avatar_media_id IS NOT NULL;

		 DROP TRIGGER IF EXISTS trg_media_objects_updated_at ON media_objects;
		 CREATE TRIGGER trg_media_objects_updated_at
		 BEFORE UPDATE ON media_objects
		 FOR EACH ROW
		 EXECUTE FUNCTION set_updated_at();`,
	)
	if err != nil {
		return fmt.Errorf("ensure media schema: %w", err)
	}

	return nil
}
