-- 004 — realtime jobs + cancelamento
--
-- Direção oposta às migrations 001–003: aqui é o 01-schema.sql que estava
-- atrasado. A feature de realtime/cancelamento (timeline de eventos por job,
-- status 'cancelled', autoria do cancelamento) foi aplicada nos bancos em uso
-- mas nunca entrou no arquivo de schema — um banco novo nascia sem ela e o
-- flight.API quebraria ao gravar a timeline.
--
-- Esta migration é no-op em bancos que já têm os objetos; serve para bancos
-- criados a partir do 01-schema.sql antigo. O 01-schema.sql foi atualizado na
-- mesma mudança.
--
-- Idempotente.

-- ─── timeline de eventos por request ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analysis_run_events (
    id         BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id UUID         NOT NULL,
    seq        INTEGER      NOT NULL,
    ts         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    type       VARCHAR(30)  NOT NULL CHECK (type IN ('queued', 'started', 'progress', 'log', 'finished')),
    level      VARCHAR(10)  CHECK (level IN ('info', 'warn', 'error')),
    payload    JSONB        NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_run_events_request_seq
    ON analysis_run_events(request_id, seq);
CREATE INDEX IF NOT EXISTS idx_run_events_ts
    ON analysis_run_events(ts);

-- ─── analysis_runs: worker responsável + autoria do cancelamento ────────────
ALTER TABLE analysis_runs ADD COLUMN IF NOT EXISTS worker_id    VARCHAR(40);
ALTER TABLE analysis_runs ADD COLUMN IF NOT EXISTS cancelled_by UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'analysis_runs_cancelled_by_fkey'
          AND conrelid = 'analysis_runs'::regclass
    ) THEN
        ALTER TABLE analysis_runs
            ADD CONSTRAINT analysis_runs_cancelled_by_fkey
            FOREIGN KEY (cancelled_by) REFERENCES users(id) ON DELETE SET NULL;
    END IF;
END $$;

-- ─── status 'cancelled' nos dois CHECKs ─────────────────────────────────────
ALTER TABLE analysis_runs DROP CONSTRAINT IF EXISTS analysis_runs_status_check;
ALTER TABLE analysis_runs ADD  CONSTRAINT analysis_runs_status_check
    CHECK (status IN ('running', 'success', 'failed', 'dead', 'blocked', 'cancelled'));

ALTER TABLE scraping_jobs DROP CONSTRAINT IF EXISTS scraping_jobs_status_check;
ALTER TABLE scraping_jobs ADD  CONSTRAINT scraping_jobs_status_check
    CHECK (status IN ('pending', 'running', 'success', 'failed', 'dead', 'cancelled'));

-- ─── scraping_jobs: marca de pedido de cancelamento ─────────────────────────
ALTER TABLE scraping_jobs ADD COLUMN IF NOT EXISTS cancel_requested_at TIMESTAMPTZ;
