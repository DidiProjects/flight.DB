-- Migration 003: Múltiplas airlines por rotina
--
-- Remove a coluna escalar routines.airline e routines.pending_request_id/at.
-- Introduz routine_airlines (junction table) e routine_pending_requests.
-- Adiciona airline na constraint única de best_fares.
-- Adiciona FK faltante em flight_offers.airline.
--
-- IMPORTANTE: rodar em transação. Testar em staging antes de produção.

BEGIN;

-- ─── 1. Junction table routine_airlines ──────────────────────────────────────
CREATE TABLE routine_airlines (
  routine_id UUID        NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  airline    VARCHAR(20) NOT NULL REFERENCES airlines(code),
  PRIMARY KEY (routine_id, airline)
);

-- Migrar dados existentes (cada rotina vira uma entrada de airline)
INSERT INTO routine_airlines (routine_id, airline)
  SELECT id, airline FROM routines;

-- ─── 2. Tabela de scrapes pendentes por airline ───────────────────────────────
CREATE TABLE routine_pending_requests (
  routine_id   UUID        NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  airline      VARCHAR(20) NOT NULL REFERENCES airlines(code),
  request_id   UUID        NOT NULL,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (routine_id, airline)
);

-- Migrar requests pendentes existentes (se houver)
INSERT INTO routine_pending_requests (routine_id, airline, request_id, requested_at)
  SELECT r.id, r.airline, r.pending_request_id, r.pending_request_at
  FROM routines r
  WHERE r.pending_request_id IS NOT NULL
    AND r.pending_request_at > now() - INTERVAL '1 hour';

-- ─── 3. best_fares — adicionar airline e atualizar constraint única ───────────
ALTER TABLE best_fares ADD COLUMN airline VARCHAR(20) REFERENCES airlines(code);

-- Preencher airline a partir do flight_offer referenciado
UPDATE best_fares bf
SET airline = fo.airline
FROM flight_offers fo
WHERE fo.id = bf.flight_offer_id;

-- Tornar airline NOT NULL após preenchimento
ALTER TABLE best_fares ALTER COLUMN airline SET NOT NULL;

-- Recriar constraint única incluindo airline
ALTER TABLE best_fares
  DROP CONSTRAINT best_fares_routine_id_date_is_return_fare_type_key;

ALTER TABLE best_fares
  ADD CONSTRAINT best_fares_unique
  UNIQUE (routine_id, airline, date, is_return, fare_type);

-- ─── 4. Remover colunas obsoletas de routines ─────────────────────────────────
ALTER TABLE routines DROP COLUMN airline;
ALTER TABLE routines DROP COLUMN pending_request_id;
ALTER TABLE routines DROP COLUMN pending_request_at;

-- ─── 5. FK faltante em flight_offers ─────────────────────────────────────────
ALTER TABLE flight_offers
  ADD CONSTRAINT fk_flight_offers_airline
  FOREIGN KEY (airline) REFERENCES airlines(code);

-- ─── 6. Índices ───────────────────────────────────────────────────────────────
CREATE INDEX idx_routine_airlines_routine_id  ON routine_airlines(routine_id);
CREATE INDEX idx_routine_airlines_airline     ON routine_airlines(airline);
CREATE INDEX idx_routine_pending_routine_id   ON routine_pending_requests(routine_id);
CREATE INDEX idx_best_fares_airline           ON best_fares(routine_id, airline);

COMMIT;
