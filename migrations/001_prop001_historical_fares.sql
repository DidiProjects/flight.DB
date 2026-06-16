-- PROP-001: Base de dados histórica de passagens
-- Adiciona: scraping_jobs, flight_fares, flight_fares_daily
-- Remove: routines.pending_request_id, routines.pending_request_at

BEGIN;

-- ============================================================
-- 1. scraping_jobs
-- Guia de raspagem + estado do scheduler
-- Chave de dedup: (airline, origin, destination, flight_date)
-- ============================================================
CREATE TABLE scraping_jobs (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  airline             VARCHAR(20)   NOT NULL REFERENCES airlines(code),
  origin              VARCHAR(10)   NOT NULL,
  destination         VARCHAR(10)   NOT NULL,
  flight_date         DATE          NOT NULL,

  status              VARCHAR(20)   NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'running', 'success', 'failed', 'dead')),
  priority            INT           NOT NULL DEFAULT 0,

  retry_count         INT           NOT NULL DEFAULT 0,
  max_retries         INT           NOT NULL DEFAULT 3,
  next_run_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  last_success_at     TIMESTAMPTZ,
  last_failure_at     TIMESTAMPTZ,
  last_error          TEXT,

  running_since       TIMESTAMPTZ,
  running_timeout_min INT           NOT NULL DEFAULT 10,

  request_id          UUID,

  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  UNIQUE (airline, origin, destination, flight_date)
);

CREATE INDEX idx_scraping_jobs_status_next_run ON scraping_jobs(status, next_run_at);
CREATE INDEX idx_scraping_jobs_airline_status  ON scraping_jobs(airline, status);
CREATE INDEX idx_scraping_jobs_flight_date     ON scraping_jobs(flight_date);
CREATE INDEX idx_scraping_jobs_request_id      ON scraping_jobs(request_id) WHERE request_id IS NOT NULL;

-- trigger de updated_at (mesma função usada no schema existente: update_updated_at)
CREATE TRIGGER trg_scraping_jobs_updated_at
  BEFORE UPDATE ON scraping_jobs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 2. flight_fares
-- Histórico de passagens coletadas (raw — 30 dias)
-- ============================================================
CREATE TABLE flight_fares (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  scraping_job_id  UUID          NOT NULL REFERENCES scraping_jobs(id) ON DELETE CASCADE,

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

  fare_cash        NUMERIC(10,2),
  fare_pts         NUMERIC(10,0),
  fare_hyb_pts     NUMERIC(10,0),
  fare_hyb_cash    NUMERIC(10,2),

  scraped_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_flight_fares_route
  ON flight_fares(airline, origin, destination, flight_date, scraped_at DESC);
CREATE INDEX idx_flight_fares_scraped_at
  ON flight_fares(scraped_at);
CREATE INDEX idx_flight_fares_job
  ON flight_fares(scraping_job_id);

-- ============================================================
-- 3. flight_fares_daily
-- Agregado diário — tier warm (1 ano)
-- ============================================================
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

-- ============================================================
-- 4. Remover colunas deprecated de routines
-- (substituídas por scraping_jobs)
-- ============================================================
ALTER TABLE routines DROP COLUMN IF EXISTS pending_request_id;
ALTER TABLE routines DROP COLUMN IF EXISTS pending_request_at;

COMMIT;
