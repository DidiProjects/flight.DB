-- 008 — Comunicação em tempo real: cancelamento de jobs + timeline de eventos
--
-- Suporta a feature de observabilidade/controle em tempo real (ver
-- flight-monitoring.IA/features.md §16):
--   • novo estado terminal `cancelled` em scraping_jobs e analysis_runs
--   • intenção de cancelamento persistida (worker offline) + auditoria
--   • analysis_run_events: timeline append-only por execução (histórico detalhado)
--
-- Aplicar manualmente em bancos existentes. Já refletido em init-scripts/01-schema.sql.

BEGIN;

-- 1) Novo estado terminal de execução cancelada ----------------------------------
ALTER TABLE scraping_jobs DROP CONSTRAINT scraping_jobs_status_check;
ALTER TABLE scraping_jobs ADD  CONSTRAINT scraping_jobs_status_check
  CHECK (status IN ('pending', 'running', 'success', 'failed', 'dead', 'cancelled'));

ALTER TABLE analysis_runs DROP CONSTRAINT analysis_runs_status_check;
ALTER TABLE analysis_runs ADD  CONSTRAINT analysis_runs_status_check
  CHECK (status IN ('running', 'success', 'failed', 'dead', 'blocked', 'cancelled'));

-- 2) Intenção de cancelamento (entregue na reconexão do worker) + auditoria -------
ALTER TABLE scraping_jobs ADD COLUMN cancel_requested_at TIMESTAMPTZ;
ALTER TABLE analysis_runs ADD COLUMN cancelled_by UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE analysis_runs ADD COLUMN worker_id    VARCHAR(40);

-- 3) Timeline append-only por execução -------------------------------------------
-- Uma linha por evento de telemetria relevante (queued|started|progress|log|finished).
-- request_id casa com analysis_runs.request_id; seq = sequência monotônica por job.
CREATE TABLE analysis_run_events (
  id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id  UUID        NOT NULL,
  seq         INT         NOT NULL,
  ts          TIMESTAMPTZ NOT NULL DEFAULT now(),
  type        VARCHAR(30) NOT NULL
              CHECK (type IN ('queued', 'started', 'progress', 'log', 'finished')),
  level       VARCHAR(10) CHECK (level IN ('info', 'warn', 'error')),
  payload     JSONB       NOT NULL DEFAULT '{}'
);

-- Ordenação determinística + dedup por (request_id, seq).
CREATE UNIQUE INDEX idx_run_events_request_seq ON analysis_run_events(request_id, seq);
-- Pruning por idade (alinhado ao cleanup das demais tabelas, ~10-15 dias).
CREATE INDEX idx_run_events_ts ON analysis_run_events(ts);

COMMIT;
