-- 007 — coleta por PAR para rotinas round-trip
--
-- Até aqui a unidade de coleta era sempre a perna-data, e uma rotina de duas
-- pernas reaproveitava tarifas one-way avulsas. Isso assume que o preço RT é
-- decomponível (ida+volta == ida avulsa + volta avulsa) — hipótese que nunca
-- foi medida. Se a cia dá desconto de ida-e-volta, ele é invisível.
--
-- Agora o job carrega `return_date`:
--   NULL      -> busca one-way (comportamento anterior, intacto)
--   preenchido -> busca ida-e-volta de verdade, com as duas datas fixas
--
-- Um job RT só casa com outro job RT das MESMAS duas datas. A chave usa
-- NULLS NOT DISTINCT (PG 15+) porque, no padrão, NULL != NULL faria cada job
-- one-way virar uma linha nova a cada upsert.
--
-- Idempotente.

-- ─── scraping_jobs ──────────────────────────────────────────────────────────
ALTER TABLE scraping_jobs ADD COLUMN IF NOT EXISTS return_date DATE;

ALTER TABLE scraping_jobs DROP CONSTRAINT IF EXISTS scraping_jobs_route_key;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'scraping_jobs_route_key'
          AND conrelid = 'scraping_jobs'::regclass
    ) THEN
        ALTER TABLE scraping_jobs
            ADD CONSTRAINT scraping_jobs_route_key
            UNIQUE NULLS NOT DISTINCT (airline, origin, destination, flight_date, return_date);
    END IF;
END $$;

-- A volta não pode anteceder a ida no mesmo job.
ALTER TABLE scraping_jobs DROP CONSTRAINT IF EXISTS scraping_jobs_return_after_outbound_check;
ALTER TABLE scraping_jobs ADD  CONSTRAINT scraping_jobs_return_after_outbound_check
    CHECK (return_date IS NULL OR return_date >= flight_date);

CREATE INDEX IF NOT EXISTS idx_scraping_jobs_return_date
    ON scraping_jobs(return_date) WHERE return_date IS NOT NULL;

-- ─── flight_fares ───────────────────────────────────────────────────────────
-- A tarifa passa a saber de que par ela veio. NULL = tarifa one-way avulsa.
-- Sem isto, a tarifa colhida numa busca RT seria indistinguível de uma avulsa
-- e voltaria a ser reaproveitada como se fosse.
ALTER TABLE flight_fares ADD COLUMN IF NOT EXISTS return_date DATE;

-- Total do par (bundle). Gravado nas DUAS pernas da mesma busca RT, para que a
-- avaliação leia o total sem precisar recombinar. NULL em tarifa one-way.
ALTER TABLE flight_fares ADD COLUMN IF NOT EXISTS bundle_cash     NUMERIC(10,2);
ALTER TABLE flight_fares ADD COLUMN IF NOT EXISTS bundle_pts      NUMERIC(10,0);
ALTER TABLE flight_fares ADD COLUMN IF NOT EXISTS bundle_hyb_pts  NUMERIC(10,0);
ALTER TABLE flight_fares ADD COLUMN IF NOT EXISTS bundle_hyb_cash NUMERIC(10,2);

-- O dedup por execução precisa distinguir as duas pernas do mesmo par.
DROP INDEX IF EXISTS idx_flight_fares_no_dup;
CREATE UNIQUE INDEX idx_flight_fares_no_dup
  ON flight_fares(request_id, flight_date, is_return, flight_number)
  WHERE flight_number IS NOT NULL AND request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_flight_fares_pair
  ON flight_fares(airline, origin, destination, flight_date, return_date)
  WHERE return_date IS NOT NULL;

-- ─── analysis_runs ──────────────────────────────────────────────────────────
ALTER TABLE analysis_runs ADD COLUMN IF NOT EXISTS return_date DATE;
