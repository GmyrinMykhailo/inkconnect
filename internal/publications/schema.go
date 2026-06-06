package publications

import (
	"context"
	"database/sql"
	"fmt"
)

func EnsurePublicationSchema(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(
		ctx,
		`CREATE TABLE IF NOT EXISTS master_publications (
		     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		     master_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		     description TEXT NOT NULL DEFAULT '',
		     comments_disabled BOOLEAN NOT NULL DEFAULT FALSE,
		     deleted_at TIMESTAMPTZ,
		     created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		     updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		     CONSTRAINT master_publications_description_len_chk
		         CHECK (char_length(description) <= 2000)
		 );

		 CREATE TABLE IF NOT EXISTS master_publication_media (
		     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		     publication_id UUID NOT NULL REFERENCES master_publications(id) ON DELETE CASCADE,
		     media_id UUID NOT NULL REFERENCES media_objects(id) ON DELETE RESTRICT,
		     sort_order INTEGER NOT NULL,
		     is_cover BOOLEAN NOT NULL DEFAULT FALSE,
		     created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		     CONSTRAINT master_publication_media_sort_order_chk
		         CHECK (sort_order BETWEEN 0 AND 9)
		 );

		 CREATE TABLE IF NOT EXISTS master_publication_styles (
		     publication_id UUID NOT NULL REFERENCES master_publications(id) ON DELETE CASCADE,
		     style TEXT NOT NULL,
		     created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		     PRIMARY KEY (publication_id, style),
		     CONSTRAINT master_publication_styles_style_chk
		         CHECK (btrim(style) <> '' AND char_length(style) <= 120)
		 );

		 CREATE INDEX IF NOT EXISTS idx_master_publications_master_created
		     ON master_publications(master_id, created_at DESC)
		     WHERE deleted_at IS NULL;

		 CREATE INDEX IF NOT EXISTS idx_master_publication_media_publication_order
		     ON master_publication_media(publication_id, sort_order);

		 CREATE UNIQUE INDEX IF NOT EXISTS idx_master_publication_media_publication_media
		     ON master_publication_media(publication_id, media_id);

		 CREATE UNIQUE INDEX IF NOT EXISTS idx_master_publication_media_publication_order_unique
		     ON master_publication_media(publication_id, sort_order);

		 CREATE UNIQUE INDEX IF NOT EXISTS idx_master_publication_media_one_cover
		     ON master_publication_media(publication_id)
		     WHERE is_cover;

		 CREATE INDEX IF NOT EXISTS idx_master_publication_styles_style
		     ON master_publication_styles(style);

		 DROP TRIGGER IF EXISTS trg_master_publications_updated_at ON master_publications;
		 CREATE TRIGGER trg_master_publications_updated_at
		 BEFORE UPDATE ON master_publications
		 FOR EACH ROW
		 EXECUTE FUNCTION set_updated_at();`,
	)
	if err != nil {
		return fmt.Errorf("ensure publication schema: %w", err)
	}

	return nil
}
