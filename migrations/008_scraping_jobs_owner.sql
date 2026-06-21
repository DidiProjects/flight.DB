-- scraping_jobs ganha dono (user_id). A deduplicação passa a ser POR USUÁRIO:
-- rotinas de usuários diferentes na mesma rota+data+companhia viram jobs
-- separados (cada um com seu dono); rotinas do MESMO usuário continuam
-- deduplicadas num job só, evitando scrape redundante.
--
-- Apenas novos jobs recebem dono. Os antigos ficam com user_id NULL e expiram
-- naturalmente quando a data do voo passa (expireOldJobs → dead → cleanup),
-- então não há backfill. NULLs são distintos em UNIQUE no Postgres, logo as
-- linhas antigas nunca conflitam com as novas (owner-scoped).

ALTER TABLE scraping_jobs
  ADD COLUMN user_id UUID REFERENCES users(id) ON DELETE CASCADE;

-- Ciclo de vida separado do status de execução: quando a rota perde a rotina
-- ativa, o job é "aposentado" (orphaned_at = NOW()) em vez de virar 'dead' —
-- assim o status da última execução (ex.: success) é preservado. orphaned_at
-- IS NULL = ativo; é o que decide se o job entra no pool de despacho.
ALTER TABLE scraping_jobs
  ADD COLUMN orphaned_at TIMESTAMPTZ;

ALTER TABLE scraping_jobs
  DROP CONSTRAINT IF EXISTS scraping_jobs_airline_origin_destination_flight_date_key;

ALTER TABLE scraping_jobs
  ADD CONSTRAINT scraping_jobs_owner_key
  UNIQUE (airline, origin, destination, flight_date, user_id);

CREATE INDEX idx_scraping_jobs_user_id ON scraping_jobs(user_id);
