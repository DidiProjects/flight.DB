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
    code      VARCHAR(20)  PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    currency  VARCHAR(3),
    active    BOOLEAN      NOT NULL DEFAULT true,
    has_cash  BOOLEAN      NOT NULL DEFAULT true,
    has_pts   BOOLEAN      NOT NULL DEFAULT false,
    has_hyb   BOOLEAN      NOT NULL DEFAULT false,
    -- Sabe fazer busca ida-e-volta (uma sessão, duas pernas, total do par)?
    -- Rotina round_trip só aceita companhia com isto true, senão o job de par
    -- voltaria com pernas avulsas e sem bundle.
    has_roundtrip BOOLEAN  NOT NULL DEFAULT false
);

-- ─── airports ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS airports (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  airline_code    VARCHAR(20) NOT NULL REFERENCES airlines(code) ON DELETE CASCADE,
  airport_code    VARCHAR(10) NOT NULL,
  name            VARCHAR(255),
  timezone        VARCHAR(100),
  country_code    VARCHAR(10),
  country_name    VARCHAR(255),
  city            VARCHAR(255),
  region          VARCHAR(255),
  currency        VARCHAR(10)  NOT NULL,
  updated_at      TIMESTAMPTZ  DEFAULT now(),
  CONSTRAINT airports_airline_airport_uk UNIQUE (airline_code, airport_code)
);

-- ─── routines ────────────────────────────────────────────────────────────────

CREATE TABLE routines (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            VARCHAR(100) NOT NULL,
    origin          CHAR(3)      NOT NULL,
    destination     CHAR(3)      NOT NULL,
    outbound_start  DATE         NOT NULL,
    outbound_end    DATE         NOT NULL,
    -- Ida-e-volta como UMA intenção. A coleta de uma rotina RT é por PAR de
    -- datas (scraping_jobs.return_date), não por perna avulsa: tarifa one-way
    -- não serve para precificar RT, senão o desconto de bundle se perde.
    trip_type       VARCHAR(20)  NOT NULL DEFAULT 'one_way' CHECK (trip_type IN ('one_way', 'round_trip')),
    inbound_start   DATE,
    inbound_end     DATE,
    passengers      SMALLINT     NOT NULL DEFAULT 1,
    currency        VARCHAR(3)   NULL,
    target_cash     NUMERIC(10,2),
    target_pts      INTEGER,
    target_hyb_pts  INTEGER,
    target_hyb_cash NUMERIC(10,2),
    margin          NUMERIC(4,3) NOT NULL DEFAULT 0.1,
    priority        VARCHAR(10)  NOT NULL DEFAULT 'cash' CHECK (priority IN ('cash', 'pts', 'hyb')),
    notification_modes     TEXT[]       NOT NULL,
    notification_frequency VARCHAR(10)  NOT NULL CHECK (notification_frequency IN ('hourly', 'daily', 'monthly')),
    scheduled_time         TIME         DEFAULT '20:00',
    cc_emails              JSONB        NOT NULL DEFAULT '[]',
    is_active              BOOLEAN      NOT NULL DEFAULT true,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT notification_modes_valid CHECK (notification_modes <@ ARRAY['target', 'scheduled']),
    CONSTRAINT notification_modes_not_empty CHECK (array_length(notification_modes, 1) >= 1),
    CONSTRAINT at_least_one_target_if_target_mode CHECK (
        NOT ('target' = ANY(notification_modes))
        OR (target_cash IS NOT NULL OR target_pts IS NOT NULL OR
            target_hyb_pts IS NOT NULL OR target_hyb_cash IS NOT NULL)
    ),
    -- Janela de volta obrigatória em round_trip, proibida em one_way.
    CONSTRAINT routines_inbound_window_check CHECK (
        (trip_type = 'one_way'    AND inbound_start IS NULL     AND inbound_end IS NULL)
     OR (trip_type = 'round_trip' AND inbound_start IS NOT NULL AND inbound_end IS NOT NULL)
    ),
    CONSTRAINT routines_inbound_range_check CHECK (
        inbound_start IS NULL OR inbound_end >= inbound_start
    ),
    CONSTRAINT routines_inbound_after_outbound_check CHECK (
        inbound_start IS NULL OR inbound_start >= outbound_start
    )
);

-- ─── routine_airlines ─────────────────────────────────────────────────────────

CREATE TABLE routine_airlines (
    routine_id UUID        NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline    VARCHAR(20) NOT NULL REFERENCES airlines(code),
    PRIMARY KEY (routine_id, airline)
);

-- ─── routine_pending_requests ─────────────────────────────────────────────────

CREATE TABLE routine_pending_requests (
    routine_id   UUID        NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline      VARCHAR(20) NOT NULL REFERENCES airlines(code),
    request_id   UUID        NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (routine_id, airline)
);

-- ─── flight_offers ───────────────────────────────────────────────────────────

CREATE TABLE flight_offers (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id            UUID         NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline               VARCHAR(20)  NOT NULL REFERENCES airlines(code),
    flight_number         VARCHAR(10)  NOT NULL,
    date                  DATE         NOT NULL,
    is_return             BOOLEAN      NOT NULL DEFAULT false,
    origin_iata           CHAR(3)      NOT NULL,
    origin_timestamp      TIMESTAMPTZ  NOT NULL,
    destination_iata      CHAR(3)      NOT NULL,
    destination_timestamp TIMESTAMPTZ  NOT NULL,
    duration_min          INTEGER      NOT NULL,
    stops                 SMALLINT     NOT NULL DEFAULT 0,
    currency              VARCHAR(3)   NOT NULL,
    fare_cash             NUMERIC(10,2),
    fare_pts              INTEGER,
    fare_hyb_pts          INTEGER,
    fare_hyb_cash         NUMERIC(10,2),
    within_target         BOOLEAN      NOT NULL DEFAULT false,
    scraped_at            TIMESTAMPTZ  NOT NULL,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── best_fares ──────────────────────────────────────────────────────────────

CREATE TABLE best_fares (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id      UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline         VARCHAR(20)   NOT NULL REFERENCES airlines(code),
    analysis_id     UUID,
    date            DATE          NOT NULL,
    is_return       BOOLEAN       NOT NULL DEFAULT false,
    fare_type       VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb')),
    amount          NUMERIC(12,2) NOT NULL,
    flight_offer_id UUID          NOT NULL REFERENCES flight_offers(id) ON DELETE CASCADE,
    currency        VARCHAR(3)    NOT NULL DEFAULT 'BRL',
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT best_fares_unique UNIQUE (routine_id, airline, date, is_return, fare_type)
);

-- ─── notification_log ────────────────────────────────────────────────────────

CREATE TABLE notification_log (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id      UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline         VARCHAR(20)   REFERENCES airlines(code),
    type            VARCHAR(20)   NOT NULL CHECK (type      IN ('alert', 'scheduled')),
    fare_type       VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb')),
    outbound_amount NUMERIC(12,2),
    return_amount   NUMERIC(12,2),
    email_to        VARCHAR(255)  NOT NULL,
    email_cc        TEXT,
    sent_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ─── target_alert_state ──────────────────────────────────────────────────────
-- Watermark por célula (rotina × data × tipo de tarifa) do alerta 'target'.
-- Fonte de verdade do anti-repetição: o alerta só re-dispara quando o melhor
-- preço de UMA data cai abaixo do que já foi notificado para aquela data.
-- Não é log (isso é notification_log) — é o estado vivo de "o que já avisamos".
CREATE TABLE target_alert_state (
    routine_id       UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    flight_date      DATE          NOT NULL,
    fare_type        VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb')),
    notified_amount  NUMERIC(12,2) NOT NULL,
    notified_airline VARCHAR(20),
    notified_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (routine_id, flight_date, fare_type)
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
CREATE INDEX IF NOT EXISTS idx_airports_airline_code ON airports(airline_code);
CREATE INDEX IF NOT EXISTS idx_airports_airport_code ON airports(airport_code);
CREATE INDEX IF NOT EXISTS idx_airports_city        ON airports(city);
CREATE INDEX idx_refresh_token               ON refresh_tokens(token);
CREATE INDEX idx_routines_user_id            ON routines(user_id);
CREATE INDEX idx_routines_is_active          ON routines(is_active);
CREATE INDEX idx_routines_trip_type          ON routines(trip_type);
CREATE INDEX idx_routine_airlines_routine_id ON routine_airlines(routine_id);
CREATE INDEX idx_routine_airlines_airline    ON routine_airlines(airline);
CREATE INDEX idx_routine_pending_routine_id  ON routine_pending_requests(routine_id);
CREATE INDEX idx_flight_offers_routine_id    ON flight_offers(routine_id);
CREATE INDEX idx_flight_offers_date          ON flight_offers(date);
CREATE INDEX idx_flight_offers_scraped_at    ON flight_offers(scraped_at);
CREATE INDEX idx_best_fares_routine_id       ON best_fares(routine_id);
CREATE INDEX idx_best_fares_airline          ON best_fares(routine_id, airline);
CREATE INDEX idx_notif_log_routine_id        ON notification_log(routine_id);
CREATE INDEX idx_notif_log_sent_at           ON notification_log(sent_at);
CREATE INDEX idx_notif_log_lookup            ON notification_log(routine_id, fare_type, type, sent_at DESC);
CREATE INDEX idx_notif_log_airline_lookup    ON notification_log(routine_id, fare_type, airline, sent_at DESC);
CREATE INDEX idx_target_alert_state_flight_date ON target_alert_state(flight_date);
CREATE INDEX idx_pw_reset_token              ON password_reset_tokens(token);
CREATE INDEX idx_unsubscribe_token           ON unsubscribe_tokens(token);

-- ─── scraping_jobs ───────────────────────────────────────────────────────────

CREATE TABLE scraping_jobs (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  airline             VARCHAR(20)   NOT NULL REFERENCES airlines(code),
  origin              VARCHAR(10)   NOT NULL,
  destination         VARCHAR(10)   NOT NULL,
  flight_date         DATE          NOT NULL,

  status              VARCHAR(20)   NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'running', 'success', 'failed', 'dead', 'cancelled')),
  priority            INT           NOT NULL DEFAULT 0,

  retry_count         INT           NOT NULL DEFAULT 0,
  max_retries         INT           NOT NULL DEFAULT 3,
  next_run_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  last_success_at     TIMESTAMPTZ,
  last_failure_at     TIMESTAMPTZ,
  last_error          TEXT,

  running_since       TIMESTAMPTZ,
  running_timeout_min INT           NOT NULL DEFAULT 20,
  -- Setado na telemetria job.started (início real do scrape). NULL = na fila.
  started_at          TIMESTAMPTZ,
  -- Último worker.heartbeat/snapshot que listou este job (lease). Para de avançar
  -- quando o worker some → o job é reclamado.
  last_heartbeat_at   TIMESTAMPTZ,

  request_id          UUID,

  -- Coleta por PAR (round-trip): NULL = busca one-way; preenchido = busca
  -- ida-e-volta com as duas datas fixas, para capturar o desconto de bundle.
  return_date         DATE,

  -- Ciclo de vida (independe do status de execução). Setado quando a rota
  -- perde a rotina ativa; NULL = ativo. Decide se o job entra no despacho.
  orphaned_at         TIMESTAMPTZ,

  -- Pedido de cancelamento registrado; o worker aborta via AbortSignal.
  cancel_requested_at TIMESTAMPTZ,

  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- NULLS NOT DISTINCT: sem isso cada job one-way (return_date NULL) viraria
  -- uma linha nova a cada upsert, porque NULL != NULL.
  CONSTRAINT scraping_jobs_route_key
    UNIQUE NULLS NOT DISTINCT (airline, origin, destination, flight_date, return_date),
  CONSTRAINT scraping_jobs_return_after_outbound_check
    CHECK (return_date IS NULL OR return_date >= flight_date)
);

CREATE INDEX idx_scraping_jobs_status_next_run ON scraping_jobs(status, next_run_at);
CREATE INDEX idx_scraping_jobs_airline_status  ON scraping_jobs(airline, status);
CREATE INDEX idx_scraping_jobs_flight_date     ON scraping_jobs(flight_date);
CREATE INDEX idx_scraping_jobs_request_id      ON scraping_jobs(request_id) WHERE request_id IS NOT NULL;
CREATE INDEX idx_scraping_jobs_return_date     ON scraping_jobs(return_date) WHERE return_date IS NOT NULL;

-- ─── flight_fares ─────────────────────────────────────────────────────────────

CREATE TABLE flight_fares (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  scraping_job_id  UUID          NOT NULL REFERENCES scraping_jobs(id) ON DELETE CASCADE,
  request_id       UUID,

  flight_number    VARCHAR(20),
  flight_date      DATE          NOT NULL,
  is_return        BOOLEAN       NOT NULL DEFAULT FALSE,
  origin           VARCHAR(10)   NOT NULL,
  destination      VARCHAR(10)   NOT NULL,
  airline          VARCHAR(20)   NOT NULL REFERENCES airlines(code),

  departure_time   TIME,
  arrival_time     TIME,
  duration_min     INT,
  stops            INT,
  currency         VARCHAR(3),

  fare_cash        NUMERIC(10,2),
  fare_pts         NUMERIC(10,0),
  fare_hyb_pts     NUMERIC(10,0),
  fare_hyb_cash    NUMERIC(10,2),

  -- Par de origem da tarifa. NULL = colhida numa busca one-way avulsa, e
  -- portanto NÃO serve para precificar um round-trip.
  return_date      DATE,

  -- Voltas são precificadas no contexto da IDA escolhida (relação 1-para-N):
  -- nas linhas de volta, o número do voo de ida que originou aquele preço.
  paired_outbound_flight VARCHAR(20),

  -- Total do par, gravado nas duas pernas da mesma busca RT.
  bundle_cash      NUMERIC(10,2),
  bundle_pts       NUMERIC(10,0),
  bundle_hyb_pts   NUMERIC(10,0),
  bundle_hyb_cash  NUMERIC(10,2),

  scraped_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_flight_fares_route
  ON flight_fares(airline, origin, destination, flight_date, scraped_at DESC);
CREATE INDEX idx_flight_fares_scraped_at
  ON flight_fares(scraped_at);
CREATE INDEX idx_flight_fares_job
  ON flight_fares(scraping_job_id);
CREATE INDEX idx_flight_fares_request_id
  ON flight_fares(request_id) WHERE request_id IS NOT NULL;

-- Impede inserir o mesmo voo duas vezes dentro de uma mesma EXECUÇÃO (request_id).
-- O discriminador é request_id, não scraping_job_id: com scraping_jobs por rota,
-- o job é permanente, então usar scraping_job_id aqui congelaria o snapshot na
-- primeira coleta. Snapshots de execuções diferentes (histórico de preço) são
-- preservados — cada run tem request_id próprio.
CREATE INDEX idx_flight_fares_paired_outbound
  ON flight_fares(request_id, paired_outbound_flight)
  WHERE paired_outbound_flight IS NOT NULL;

CREATE INDEX idx_flight_fares_pair
  ON flight_fares(airline, origin, destination, flight_date, return_date)
  WHERE return_date IS NOT NULL;

-- paired_outbound_flight entra na chave porque a MESMA volta aparece na lista de
-- várias idas, com preço potencialmente diferente em cada uma. Sem ela o
-- ON CONFLICT DO NOTHING guardaria só a primeira combinação.
CREATE UNIQUE INDEX idx_flight_fares_no_dup
  ON flight_fares(request_id, flight_date, is_return, flight_number, paired_outbound_flight)
  NULLS NOT DISTINCT
  WHERE flight_number IS NOT NULL AND request_id IS NOT NULL;

-- ─── flight_fares_daily ───────────────────────────────────────────────────────

CREATE TABLE flight_fares_daily (
  airline       VARCHAR(20)   NOT NULL REFERENCES airlines(code),
  origin        VARCHAR(10)   NOT NULL,
  destination   VARCHAR(10)   NOT NULL,
  flight_date   DATE          NOT NULL,
  bucket_date   DATE          NOT NULL,
  fare_type     VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb_pts', 'hyb_cash')),

  price_min     NUMERIC(10,2),
  price_max     NUMERIC(10,2),
  price_avg     NUMERIC(10,2),
  sample_count  INT           NOT NULL DEFAULT 0,

  PRIMARY KEY (airline, origin, destination, flight_date, bucket_date, fare_type)
);

-- ─── analysis_runs ────────────────────────────────────────────────────────────
-- Histórico de execuções de análise (uma linha por execução de scraping_job).
-- Campos de rota denormalizados para sobreviver à limpeza de scraping_jobs.

CREATE TABLE analysis_runs (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  scraping_job_id UUID         REFERENCES scraping_jobs(id) ON DELETE SET NULL,
  request_id      UUID         NOT NULL,
  airline         VARCHAR(20)  NOT NULL,
  origin          VARCHAR(10)  NOT NULL,
  destination     VARCHAR(10)  NOT NULL,
  flight_date     DATE         NOT NULL,
  -- Perna de volta quando a execução foi uma busca round-trip.
  return_date     DATE,
  status          VARCHAR(20)  NOT NULL DEFAULT 'running'
                  CHECK (status IN ('running', 'success', 'failed', 'dead', 'blocked', 'cancelled')),
  error_message   TEXT,
  fares_found     INT,
  -- Worker que assumiu a execução (telemetria realtime).
  worker_id       VARCHAR(40),
  -- Quem pediu o cancelamento; NULL quando não foi cancelada.
  cancelled_by    UUID         REFERENCES users(id) ON DELETE SET NULL,
  started_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  finished_at     TIMESTAMPTZ
);

CREATE INDEX idx_analysis_runs_match
  ON analysis_runs(airline, origin, destination, flight_date, started_at DESC);
CREATE INDEX idx_analysis_runs_request
  ON analysis_runs(request_id);

-- ─── analysis_run_events ──────────────────────────────────────────────────────
-- Timeline de eventos por request_id, alimentada pela telemetria do worker.
-- É o que o FRONT consome para acompanhar a análise em tempo real.

CREATE TABLE analysis_run_events (
  id         BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id UUID         NOT NULL,
  seq        INTEGER      NOT NULL,
  ts         TIMESTAMPTZ  NOT NULL DEFAULT now(),
  type       VARCHAR(30)  NOT NULL CHECK (type IN ('queued', 'started', 'progress', 'log', 'finished')),
  level      VARCHAR(10)  CHECK (level IN ('info', 'warn', 'error')),
  payload    JSONB        NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX idx_run_events_request_seq ON analysis_run_events(request_id, seq);
CREATE INDEX        idx_run_events_ts          ON analysis_run_events(ts);

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

CREATE TRIGGER trg_scraping_jobs_updated_at
    BEFORE UPDATE ON scraping_jobs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
