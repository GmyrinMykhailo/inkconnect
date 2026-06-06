CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('client', 'master', 'admin');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'service_kind') THEN
        CREATE TYPE service_kind AS ENUM ('tattoo', 'piercing', 'scarification', 'other');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'appointment_status') THEN
        CREATE TYPE appointment_status AS ENUM (
            'pending',
            'confirmed',
            'rejected',
            'completed',
            'cancelled'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'journal_entry_type') THEN
        CREATE TYPE journal_entry_type AS ENUM (
            'recommendation',
            'client_confirmation',
            'integrity_check',
            'system_note'
        );
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username CITEXT NOT NULL UNIQUE,
    email CITEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role user_role NOT NULL,
    full_name TEXT NOT NULL,
    last_name TEXT,
    first_name TEXT,
    middle_name TEXT,
    phone TEXT,
    city TEXT,
    show_full_name_in_profile BOOLEAN NOT NULL DEFAULT FALSE,
    show_city_in_profile BOOLEAN NOT NULL DEFAULT FALSE,
    bio TEXT,
    avatar_url TEXT,
    public_key TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS username CITEXT;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS show_city_in_profile BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS show_full_name_in_profile BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS last_name TEXT;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS first_name TEXT;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS middle_name TEXT;

UPDATE users
SET
    last_name = COALESCE(NULLIF(last_name, ''), NULLIF(split_part(trim(full_name), ' ', 1), '')),
    first_name = COALESCE(NULLIF(first_name, ''), NULLIF(split_part(trim(full_name), ' ', 2), '')),
    middle_name = COALESCE(
        NULLIF(middle_name, ''),
        NULLIF(trim(regexp_replace(trim(full_name), '^\S+\s+\S+\s*', '')), '')
    )
WHERE trim(full_name) <> '';

UPDATE users
SET username = lower(split_part(email::text, '@', 1)) || '_' || left(replace(id::text, '-', ''), 8)
WHERE username IS NULL OR trim(username::text) = '';

ALTER TABLE users
    ALTER COLUMN username SET NOT NULL;

CREATE TABLE IF NOT EXISTS media_objects (
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

CREATE TABLE IF NOT EXISTS auth_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_agent TEXT,
    ip_address INET
);

CREATE TABLE IF NOT EXISTS user_signing_keys (
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
);

ALTER TABLE user_signing_keys
    ADD COLUMN IF NOT EXISTS encrypted_private_key TEXT;

ALTER TABLE user_signing_keys
    ADD COLUMN IF NOT EXISTS private_key_encryption_key_id TEXT;

ALTER TABLE user_signing_keys
    ADD COLUMN IF NOT EXISTS private_key_encrypted_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS master_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    studio_name TEXT,
    category TEXT NOT NULL DEFAULT 'Тату-мастер',
    min_session_price INTEGER NOT NULL DEFAULT 5000 CHECK (min_session_price >= 0),
    hourly_rate INTEGER NOT NULL DEFAULT 2500 CHECK (hourly_rate >= 0),
    break_between_clients TEXT NOT NULL DEFAULT '30 минут',
    experience_years INTEGER NOT NULL DEFAULT 0 CHECK (experience_years >= 0),
    rating NUMERIC(3, 2) NOT NULL DEFAULT 0 CHECK (rating >= 0 AND rating <= 5),
    review_count INTEGER NOT NULL DEFAULT 0 CHECK (review_count >= 0),
    is_verified BOOLEAN NOT NULL DEFAULT FALSE
);

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

CREATE TABLE IF NOT EXISTS master_work_schedule (
    master_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day_of_week SMALLINT NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
    is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    intervals JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (master_id, day_of_week)
);

CREATE TABLE IF NOT EXISTS favorite_masters (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    master_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, master_id)
);

CREATE INDEX IF NOT EXISTS favorite_masters_user_created_idx
    ON favorite_masters (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    master_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind service_kind NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    service_type TEXT NOT NULL DEFAULT 'session',
    style TEXT,
    category TEXT,
    price_min NUMERIC(10, 2) CHECK (price_min >= 0),
    price_max NUMERIC(10, 2) CHECK (price_max >= 0),
    duration_minutes INTEGER CHECK (duration_minutes > 0),
    use_auto_price BOOLEAN NOT NULL DEFAULT FALSE,
    from_price BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT services_service_type_chk
        CHECK (service_type IN ('session', 'consultation', 'sketch')),
    CONSTRAINT services_price_range_chk
        CHECK (price_max IS NULL OR price_min IS NULL OR price_max >= price_min)
);

ALTER TABLE services
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

CREATE TABLE IF NOT EXISTS portfolio_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    master_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    service_id UUID REFERENCES services(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT,
    image_url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS master_publications (
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

CREATE TABLE IF NOT EXISTS appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    master_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    service_id UUID NOT NULL REFERENCES services(id) ON DELETE RESTRICT,
    scheduled_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER CHECK (duration_minutes > 0),
    status appointment_status NOT NULL DEFAULT 'pending',
    client_note TEXT,
    master_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT appointments_client_master_chk CHECK (client_id <> master_id)
);

CREATE TABLE IF NOT EXISTS care_journals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id UUID NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
    client_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    master_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_by_master_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    latest_hash TEXT,
    last_verified_at TIMESTAMPTZ,
    integrity_status BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT care_journals_client_master_chk CHECK (client_id <> master_id)
);

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS created_by_master_id UUID REFERENCES users(id) ON DELETE RESTRICT;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS root_journal_id UUID REFERENCES care_journals(id) ON DELETE SET NULL;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS parent_journal_id UUID REFERENCES care_journals(id) ON DELETE SET NULL;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS replaced_by_journal_id UUID REFERENCES care_journals(id) ON DELETE SET NULL;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS version_number INTEGER NOT NULL DEFAULT 1;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS stopped_at TIMESTAMPTZ;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS stop_reason TEXT;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS replacement_reason TEXT;

ALTER TABLE care_journals
    ADD COLUMN IF NOT EXISTS final_hash TEXT;

ALTER TABLE care_journals
    DROP CONSTRAINT IF EXISTS care_journals_status_chk;

ALTER TABLE care_journals
    ADD CONSTRAINT care_journals_status_chk
        CHECK (status IN (
            'draft',
            'awaiting_client_confirmation',
            'active',
            'completed',
            'stopped',
            'replaced'
        ));

ALTER TABLE care_journals
    DROP CONSTRAINT IF EXISTS care_journals_version_number_chk;

ALTER TABLE care_journals
    ADD CONSTRAINT care_journals_version_number_chk
        CHECK (version_number > 0);

ALTER TABLE care_journals
    DROP CONSTRAINT IF EXISTS care_journals_appointment_id_key;

DROP INDEX IF EXISTS care_journals_appointment_id_key;

CREATE TABLE IF NOT EXISTS care_recommendations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id UUID NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
    journal_id UUID REFERENCES care_journals(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'draft',
    step_number INTEGER NOT NULL CHECK (step_number > 0),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    due_offset_days INTEGER,
    due_at TIMESTAMPTZ,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    sent_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT care_recommendations_status_chk
        CHECK (status IN ('draft', 'sent', 'approved')),
    CONSTRAINT care_recommendations_due_offset_days_chk
        CHECK (due_offset_days IS NULL OR due_offset_days >= 0),
    CONSTRAINT care_recommendations_appointment_step_key
        UNIQUE (appointment_id, step_number)
);

ALTER TABLE care_recommendations
    ADD COLUMN IF NOT EXISTS appointment_id UUID REFERENCES appointments(id) ON DELETE CASCADE;

UPDATE care_recommendations cr
SET appointment_id = cj.appointment_id
FROM care_journals cj
WHERE cr.journal_id = cj.id
  AND cr.appointment_id IS NULL;

ALTER TABLE care_recommendations
    ALTER COLUMN journal_id DROP NOT NULL;

ALTER TABLE care_recommendations
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'draft';

ALTER TABLE care_recommendations
    ADD COLUMN IF NOT EXISTS due_offset_days INTEGER;

ALTER TABLE care_recommendations
    ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ;

ALTER TABLE care_recommendations
    ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

ALTER TABLE care_recommendations
    DROP CONSTRAINT IF EXISTS care_recommendations_status_chk;

ALTER TABLE care_recommendations
    ADD CONSTRAINT care_recommendations_status_chk
        CHECK (status IN ('draft', 'sent', 'approved'));

ALTER TABLE care_recommendations
    DROP CONSTRAINT IF EXISTS care_recommendations_due_offset_days_chk;

ALTER TABLE care_recommendations
    ADD CONSTRAINT care_recommendations_due_offset_days_chk
        CHECK (due_offset_days IS NULL OR due_offset_days >= 0);

ALTER TABLE care_recommendations
    DROP CONSTRAINT IF EXISTS care_recommendations_journal_id_step_number_key;

ALTER TABLE care_recommendations
    DROP CONSTRAINT IF EXISTS care_recommendations_appointment_step_key;

ALTER TABLE care_recommendations
    ADD CONSTRAINT care_recommendations_appointment_step_key
        UNIQUE (appointment_id, step_number);

CREATE TABLE IF NOT EXISTS care_journal_steps (
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
);

UPDATE care_journal_steps cjs
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
  AND cjs.day_number > 0;

CREATE TABLE IF NOT EXISTS care_journal_events (
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
);

CREATE TABLE IF NOT EXISTS care_journal_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_id UUID NOT NULL REFERENCES care_journals(id) ON DELETE CASCADE,
    recommendation_id UUID REFERENCES care_recommendations(id) ON DELETE SET NULL,
    entry_type journal_entry_type NOT NULL,
    actor_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    previous_entry_id UUID REFERENCES care_journal_entries(id) ON DELETE SET NULL,
    previous_hash TEXT,
    entry_hash TEXT NOT NULL,
    digital_signature TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT care_journal_entries_hash_chk
        CHECK (entry_hash <> ''),
    CONSTRAINT care_journal_entries_prev_link_chk
        CHECK (
            (previous_entry_id IS NULL AND previous_hash IS NULL)
            OR (previous_entry_id IS NOT NULL AND previous_hash IS NOT NULL)
        )
);

CREATE TABLE IF NOT EXISTS direct_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id UUID REFERENCES appointments(id) ON DELETE SET NULL,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_text TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ,
    CONSTRAINT direct_messages_sender_recipient_chk CHECK (sender_id <> recipient_id)
);

CREATE TABLE IF NOT EXISTS chat_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    participant_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMPTZ,
    CONSTRAINT chat_threads_participants_chk CHECK (participant_a_id <> participant_b_id)
);

CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_body TEXT NOT NULL,
    encryption_nonce TEXT NOT NULL,
    body_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'delivered',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    edited_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT chat_messages_status_chk CHECK (status IN ('sent', 'delivered'))
);

CREATE TABLE IF NOT EXISTS reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id UUID NOT NULL UNIQUE REFERENCES appointments(id) ON DELETE CASCADE,
    client_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    master_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS moderation_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    target_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    target_review_id UUID REFERENCES reviews(id) ON DELETE SET NULL,
    action_type TEXT NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT moderation_actions_target_chk
        CHECK (target_user_id IS NOT NULL OR target_review_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_city ON users(city);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL AND btrim(phone) <> '';
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
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id ON auth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires_at ON auth_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_user_signing_keys_user_id_status ON user_signing_keys(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_signing_keys_user_id_fingerprint
    ON user_signing_keys(user_id, key_fingerprint);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_signing_keys_fingerprint ON user_signing_keys(key_fingerprint);
CREATE INDEX IF NOT EXISTS idx_master_styles_style ON master_styles(style);
CREATE INDEX IF NOT EXISTS idx_services_master_id ON services(master_id);
CREATE INDEX IF NOT EXISTS idx_services_kind_style ON services(kind, style);
CREATE INDEX IF NOT EXISTS idx_appointments_client_id ON appointments(client_id);
CREATE INDEX IF NOT EXISTS idx_appointments_master_id ON appointments(master_id);
CREATE INDEX IF NOT EXISTS idx_appointments_status_scheduled_at ON appointments(status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_care_journals_appointment_id ON care_journals(appointment_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_care_journals_one_open_per_appointment
    ON care_journals(appointment_id)
    WHERE status IN ('draft', 'awaiting_client_confirmation', 'active');
CREATE INDEX IF NOT EXISTS idx_care_journals_client_id ON care_journals(client_id);
CREATE INDEX IF NOT EXISTS idx_care_journals_master_id ON care_journals(master_id);
CREATE INDEX IF NOT EXISTS idx_care_journals_status ON care_journals(status);
CREATE INDEX IF NOT EXISTS idx_care_journals_root_journal_id ON care_journals(root_journal_id);
CREATE INDEX IF NOT EXISTS idx_care_journals_parent_journal_id ON care_journals(parent_journal_id);
CREATE INDEX IF NOT EXISTS idx_care_journals_replaced_by_journal_id ON care_journals(replaced_by_journal_id);
CREATE INDEX IF NOT EXISTS idx_care_recommendations_journal_id ON care_recommendations(journal_id);
CREATE INDEX IF NOT EXISTS idx_care_recommendations_appointment_id ON care_recommendations(appointment_id);
CREATE INDEX IF NOT EXISTS idx_care_recommendations_status ON care_recommendations(status);
CREATE INDEX IF NOT EXISTS idx_care_journal_steps_journal_id ON care_journal_steps(journal_id);
CREATE INDEX IF NOT EXISTS idx_care_journal_steps_status ON care_journal_steps(status);
CREATE INDEX IF NOT EXISTS idx_care_journal_steps_deadline_at ON care_journal_steps(deadline_at);
CREATE INDEX IF NOT EXISTS idx_care_journal_steps_completed_by_client_id
    ON care_journal_steps(completed_by_client_id);
CREATE INDEX IF NOT EXISTS idx_care_journal_events_journal_id_created_at
    ON care_journal_events(journal_id, created_at);
CREATE INDEX IF NOT EXISTS idx_care_journal_events_step_id ON care_journal_events(step_id);
CREATE INDEX IF NOT EXISTS idx_care_journal_events_actor_id ON care_journal_events(actor_id);
CREATE INDEX IF NOT EXISTS idx_care_journal_events_signing_key_id ON care_journal_events(signing_key_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_care_journal_events_event_hash
    ON care_journal_events(event_hash)
    WHERE event_hash IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_care_journal_events_step_completed_unique
    ON care_journal_events(journal_id, step_id)
    WHERE event_type = 'step_completed_by_client' AND step_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_care_journal_entries_journal_id_created_at
    ON care_journal_entries(journal_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_care_journal_entries_client_confirmation_unique
    ON care_journal_entries(journal_id, recommendation_id)
    WHERE entry_type = 'client_confirmation';
CREATE INDEX IF NOT EXISTS idx_care_journal_entries_recommendation_id
    ON care_journal_entries(recommendation_id);
CREATE INDEX IF NOT EXISTS idx_direct_messages_sender_recipient
    ON direct_messages(sender_id, recipient_id, sent_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_threads_unique_pair
    ON chat_threads (LEAST(participant_a_id, participant_b_id), GREATEST(participant_a_id, participant_b_id));
CREATE INDEX IF NOT EXISTS idx_chat_threads_participant_a
    ON chat_threads(participant_a_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_threads_participant_b
    ON chat_threads(participant_b_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_thread_created
    ON chat_messages(thread_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender
    ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_reviews_master_id ON reviews(master_id);
CREATE INDEX IF NOT EXISTS idx_moderation_actions_admin_id ON moderation_actions(admin_id);

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_media_objects_updated_at ON media_objects;
CREATE TRIGGER trg_media_objects_updated_at
BEFORE UPDATE ON media_objects
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_master_publications_updated_at ON master_publications;
CREATE TRIGGER trg_master_publications_updated_at
BEFORE UPDATE ON master_publications
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_appointments_updated_at ON appointments;
CREATE TRIGGER trg_appointments_updated_at
BEFORE UPDATE ON appointments
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_services_updated_at ON services;
CREATE TRIGGER trg_services_updated_at
BEFORE UPDATE ON services
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_care_journal_steps_updated_at ON care_journal_steps;
CREATE TRIGGER trg_care_journal_steps_updated_at
BEFORE UPDATE ON care_journal_steps
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE VIEW v_care_journal_timeline AS
SELECT
    e.id,
    e.journal_id,
    e.recommendation_id,
    e.entry_type,
    e.actor_user_id,
    e.previous_entry_id,
    e.previous_hash,
    e.entry_hash,
    e.digital_signature,
    e.payload,
    e.created_at
FROM care_journal_entries e
ORDER BY e.journal_id, e.created_at, e.id;
