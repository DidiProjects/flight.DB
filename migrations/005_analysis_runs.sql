-- PROP: histórico de execuções de análise (admin)
--
-- Registra UMA linha por execução de scraping_job (cia + data), do dispatch ao
-- callback. Os scraping_jobs guardam só o estado atual; esta tabela preserva o
-- histórico execução-a-execução para a visão admin em /admin/user-routines.
--
-- Campos de rota são denormalizados para o histórico sobreviver à limpeza de
-- scraping_jobs (cleanupDeadJobs) — por isso o FK usa ON DELETE SET NULL.

CREATE TABLE analysis_runs (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  scraping_job_id UUID         REFERENCES scraping_jobs(id) ON DELETE SET NULL,
  request_id      UUID         NOT NULL,
  airline         VARCHAR(20)  NOT NULL,
  origin          VARCHAR(10)  NOT NULL,
  destination     VARCHAR(10)  NOT NULL,
  flight_date     DATE         NOT NULL,
  status          VARCHAR(20)  NOT NULL DEFAULT 'running'
                  CHECK (status IN ('running', 'success', 'failed', 'dead', 'blocked')),
  error_message   TEXT,
  fares_found     INT,
  started_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  finished_at     TIMESTAMPTZ
);

CREATE INDEX idx_analysis_runs_match
  ON analysis_runs(airline, origin, destination, flight_date, started_at DESC);
CREATE INDEX idx_analysis_runs_request
  ON analysis_runs(request_id);
