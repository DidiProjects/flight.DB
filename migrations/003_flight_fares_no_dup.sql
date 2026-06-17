-- Impede inserir o mesmo voo duas vezes dentro de uma mesma coleta (scraping_job).
-- Snapshots em jobs diferentes (histórico de preço) continuam permitidos.

-- 1) Remove duplicatas pré-existentes, mantendo a linha mais antiga (menor ctid)
--    de cada grupo (scraping_job_id, flight_date, is_return, flight_number).
DELETE FROM flight_fares a
USING flight_fares b
WHERE a.flight_number IS NOT NULL
  AND b.flight_number IS NOT NULL
  AND a.scraping_job_id = b.scraping_job_id
  AND a.flight_date     = b.flight_date
  AND a.is_return       = b.is_return
  AND a.flight_number   = b.flight_number
  AND a.ctid > b.ctid;

-- 2) Cria o índice único parcial.
CREATE UNIQUE INDEX IF NOT EXISTS idx_flight_fares_no_dup
  ON flight_fares(scraping_job_id, flight_date, is_return, flight_number)
  WHERE flight_number IS NOT NULL;
