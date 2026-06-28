-- 003_scraping_jobs_started_at.sql
-- Distingue "esperando na fila" de "rodando de fato". started_at é setado quando
-- chega a telemetria job.started; NULL = ainda na fila do scraper. Idempotente.

ALTER TABLE scraping_jobs ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;

-- Timeout por job acima do scrape mais lento observado (~16min) para não matar
-- execução legítima em andamento.
ALTER TABLE scraping_jobs ALTER COLUMN running_timeout_min SET DEFAULT 20;
UPDATE scraping_jobs SET running_timeout_min = 20 WHERE running_timeout_min = 10;
