SET timezone = 'America/Sao_Paulo';

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─── users ───────────────────────────────────────────────────────────────────

CREATE TABLE users (
    id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email                  VARCHAR(255) UNIQUE NOT NULL,
    name                   VARCHAR(100) NOT NULL,
    password_hash          VARCHAR(255) NOT NULL,
    role                   VARCHAR(10)  NOT NULL DEFAULT 'user'    CHECK (role   IN ('admin', 'user')),
    status                 VARCHAR(20)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'suspended')),
    must_change_password   BOOLEAN      NOT NULL DEFAULT true,
    provisional_expires_at TIMESTAMPTZ,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── refresh_tokens ──────────────────────────────────────────────────────────

CREATE TABLE refresh_tokens (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      VARCHAR(128) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ  NOT NULL,
    used_at    TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── password_reset_tokens ───────────────────────────────────────────────────

CREATE TABLE password_reset_tokens (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      VARCHAR(128) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ  NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── airlines ────────────────────────────────────────────────────────────────

CREATE TABLE airlines (
    code    VARCHAR(10)  PRIMARY KEY,
    name    VARCHAR(100) NOT NULL,
    active  BOOLEAN      NOT NULL DEFAULT true,
    has_brl BOOLEAN      NOT NULL DEFAULT true,
    has_pts BOOLEAN      NOT NULL DEFAULT false,
    has_hyb BOOLEAN      NOT NULL DEFAULT false
);


-- ─── routines ────────────────────────────────────────────────────────────────

CREATE TABLE routines (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            VARCHAR(100) NOT NULL,
    airline         VARCHAR(10)  NOT NULL REFERENCES airlines(code),
    origin          CHAR(3)      NOT NULL,
    destination     CHAR(3)      NOT NULL,
    outbound_start  DATE         NOT NULL,
    outbound_end    DATE         NOT NULL,
    return_start    DATE,
    return_end      DATE,
    passengers      SMALLINT     NOT NULL DEFAULT 1,
    target_brl      NUMERIC(10,2),
    target_pts      INTEGER,
    target_hyb_pts  INTEGER,
    target_hyb_brl  NUMERIC(10,2),
    margin          NUMERIC(4,3) NOT NULL DEFAULT 0.1,
    priority        VARCHAR(3)   NOT NULL DEFAULT 'brl' CHECK (priority IN ('brl', 'pts', 'hyb')),
    notification_mode      VARCHAR(30)  NOT NULL CHECK (notification_mode      IN ('alert_only', 'daily_best_and_alert', 'end_of_period')),
    notification_frequency VARCHAR(10)  NOT NULL CHECK (notification_frequency IN ('hourly', 'daily', 'monthly')),
    end_of_period_time     TIME,
    cc_emails              JSONB        NOT NULL DEFAULT '[]',
    pending_request_id     UUID,
    pending_request_at     TIMESTAMPTZ,
    is_active              BOOLEAN      NOT NULL DEFAULT true,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT at_least_one_target CHECK (
        target_brl IS NOT NULL OR target_pts IS NOT NULL OR
        target_hyb_pts IS NOT NULL OR target_hyb_brl IS NOT NULL
    )
);

-- ─── flight_offers ───────────────────────────────────────────────────────────

CREATE TABLE flight_offers (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id            UUID         NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline               VARCHAR(10)  NOT NULL,
    flight_number         VARCHAR(10)  NOT NULL,
    date                  DATE         NOT NULL,
    is_return             BOOLEAN      NOT NULL DEFAULT false,
    origin_iata           CHAR(3)      NOT NULL,
    origin_timestamp      TIMESTAMPTZ  NOT NULL,
    destination_iata      CHAR(3)      NOT NULL,
    destination_timestamp TIMESTAMPTZ  NOT NULL,
    duration_min          INTEGER      NOT NULL,
    stops                 SMALLINT     NOT NULL DEFAULT 0,
    fare_brl              NUMERIC(10,2),
    fare_pts              INTEGER,
    fare_hyb_pts          INTEGER,
    fare_hyb_brl          NUMERIC(10,2),
    within_target         BOOLEAN      NOT NULL DEFAULT false,
    scraped_at            TIMESTAMPTZ  NOT NULL,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── best_fares ──────────────────────────────────────────────────────────────

CREATE TABLE best_fares (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id      UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    date            DATE          NOT NULL,
    is_return       BOOLEAN       NOT NULL DEFAULT false,
    fare_type       VARCHAR(3)    NOT NULL CHECK (fare_type IN ('brl', 'pts', 'hyb')),
    amount          NUMERIC(12,2) NOT NULL,
    flight_offer_id UUID          NOT NULL REFERENCES flight_offers(id) ON DELETE CASCADE,
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE(routine_id, date, is_return, fare_type)
);

-- ─── notification_log ────────────────────────────────────────────────────────

CREATE TABLE notification_log (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id      UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    type            VARCHAR(20)   NOT NULL CHECK (type      IN ('alert', 'best_of_day', 'end_of_period')),
    fare_type       VARCHAR(3)    NOT NULL CHECK (fare_type IN ('brl', 'pts', 'hyb')),
    outbound_amount NUMERIC(12,2),
    return_amount   NUMERIC(12,2),
    email_to        VARCHAR(255)  NOT NULL,
    email_cc        TEXT,
    sent_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ─── unsubscribe_tokens ──────────────────────────────────────────────────────

CREATE TABLE unsubscribe_tokens (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    token       VARCHAR(128) UNIQUE NOT NULL,
    routine_id  UUID         NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    email       VARCHAR(255) NOT NULL,
    is_primary  BOOLEAN      NOT NULL DEFAULT false,
    expires_at  TIMESTAMPTZ  NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── indexes ─────────────────────────────────────────────────────────────────
CREATE INDEX idx_refresh_token            ON refresh_tokens(token);
CREATE INDEX idx_routines_user_id         ON routines(user_id);
CREATE INDEX idx_routines_is_active       ON routines(is_active);
CREATE INDEX idx_flight_offers_routine_id ON flight_offers(routine_id);
CREATE INDEX idx_flight_offers_date       ON flight_offers(date);
CREATE INDEX idx_flight_offers_scraped_at ON flight_offers(scraped_at);
CREATE INDEX idx_best_fares_routine_id    ON best_fares(routine_id);
CREATE INDEX idx_notif_log_routine_id     ON notification_log(routine_id);
CREATE INDEX idx_notif_log_sent_at        ON notification_log(sent_at);
CREATE INDEX idx_pw_reset_token           ON password_reset_tokens(token);
CREATE INDEX idx_unsubscribe_token        ON unsubscribe_tokens(token);

-- ─── updated_at trigger ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_routines_updated_at
    BEFORE UPDATE ON routines
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_best_fares_updated_at
    BEFORE UPDATE ON best_fares
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
