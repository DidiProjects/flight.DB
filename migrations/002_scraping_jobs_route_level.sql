-- 002_scraping_jobs_route_level.sql
-- Dedup de scraping_jobs volta a ser por ROTA (remove user_id). Idempotente.

BEGIN;

CREATE TEMP TABLE _sj_ranked ON COMMIT DROP AS
  SELECT id, airline, origin, destination, flight_date,
         row_number() OVER (
           PARTITION BY airline, origin, destination, flight_date
           ORDER BY (status = 'dead') ASC,
                    last_success_at DESC NULLS LAST,
                    updated_at DESC
         ) AS rn
  FROM scraping_jobs;

CREATE TEMP TABLE _sj_merge ON COMMIT DROP AS
  SELECT win.id AS survivor_id, lose.id AS dup_id
  FROM _sj_ranked win
  JOIN _sj_ranked lose
    ON lose.airline     = win.airline
   AND lose.origin      = win.origin
   AND lose.destination = win.destination
   AND lose.flight_date = win.flight_date
  WHERE win.rn = 1 AND lose.rn > 1;

DELETE FROM flight_fares ff
USING _sj_merge m
WHERE ff.scraping_job_id = m.dup_id
  AND ff.flight_number IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM flight_fares sf
    WHERE sf.scraping_job_id = m.survivor_id
      AND sf.flight_date     = ff.flight_date
      AND sf.is_return       = ff.is_return
      AND sf.flight_number   = ff.flight_number
  );

UPDATE flight_fares ff
SET scraping_job_id = m.survivor_id
FROM _sj_merge m
WHERE ff.scraping_job_id = m.dup_id;

DELETE FROM scraping_jobs sj
USING _sj_merge m
WHERE sj.id = m.dup_id;

ALTER TABLE scraping_jobs DROP CONSTRAINT IF EXISTS scraping_jobs_owner_key;
DROP INDEX IF EXISTS idx_scraping_jobs_user_id;
ALTER TABLE scraping_jobs DROP COLUMN IF EXISTS user_id;
ALTER TABLE scraping_jobs DROP CONSTRAINT IF EXISTS scraping_jobs_route_key;
ALTER TABLE scraping_jobs
  ADD CONSTRAINT scraping_jobs_route_key UNIQUE (airline, origin, destination, flight_date);

COMMIT;
