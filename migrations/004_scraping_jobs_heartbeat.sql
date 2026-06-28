-- 004_scraping_jobs_heartbeat.sql
-- Lease por heartbeat: o worker declara periodicamente (worker.heartbeat/snapshot)
-- os jobs que detém; last_heartbeat_at registra o último sinal. Job só é reclamado
-- quando o heartbeat para (worker morto/indisponível), não por relógio cego.

ALTER TABLE scraping_jobs ADD COLUMN IF NOT EXISTS last_heartbeat_at TIMESTAMPTZ;
