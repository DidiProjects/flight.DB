-- 006 — Fase 1 do round-trip: intenção de ida-e-volta na rotina
--
-- Hoje uma viagem de ida-e-volta é modelada como DUAS rotinas one-way. Isto
-- unifica a intenção numa rotina só, com uma segunda janela de datas (volta).
--
-- A coleta NÃO muda: scraping_jobs continua com UNIQUE(airline, origin,
-- destination, flight_date), um job por perna-data compartilhado entre todas as
-- rotinas. Uma rotina RT apenas deriva jobs das DUAS janelas. O reuso de
-- tarifas entre usuários fica intacto.
--
-- Decisões de produto (2026-07-24) que NÃO viram coluna aqui:
--   · teto de 3 meses entre ida e volta → constante da aplicação
--     (MAX_ROUNDTRIP_SPAN_MONTHS em flight.API/src/utils/), não é por rotina;
--   · ida e volta na mesma companhia → regra de avaliação, routine_airlines
--     já modela as cias da rotina;
--   · par só avaliado com moeda igual nas duas pernas → regra de avaliação.
--
-- Aditivo: rotinas existentes viram 'one_way' e seguem idênticas.
-- Idempotente.

ALTER TABLE routines ADD COLUMN IF NOT EXISTS trip_type     VARCHAR(20) NOT NULL DEFAULT 'one_way';
ALTER TABLE routines ADD COLUMN IF NOT EXISTS inbound_start DATE;
ALTER TABLE routines ADD COLUMN IF NOT EXISTS inbound_end   DATE;

ALTER TABLE routines DROP CONSTRAINT IF EXISTS routines_trip_type_check;
ALTER TABLE routines ADD  CONSTRAINT routines_trip_type_check
    CHECK (trip_type IN ('one_way', 'round_trip'));

-- A janela de volta é obrigatória em round_trip e proibida em one_way: sem isto
-- daria para gravar uma rotina RT sem volta (o par nunca fecharia) ou uma
-- one-way carregando datas de volta órfãs.
ALTER TABLE routines DROP CONSTRAINT IF EXISTS routines_inbound_window_check;
ALTER TABLE routines ADD  CONSTRAINT routines_inbound_window_check
    CHECK (
        (trip_type = 'one_way'    AND inbound_start IS NULL     AND inbound_end IS NULL)
     OR (trip_type = 'round_trip' AND inbound_start IS NOT NULL AND inbound_end IS NOT NULL)
    );

-- Ordem interna da janela de volta (mesma garantia que a janela de ida tem).
ALTER TABLE routines DROP CONSTRAINT IF EXISTS routines_inbound_range_check;
ALTER TABLE routines ADD  CONSTRAINT routines_inbound_range_check
    CHECK (inbound_start IS NULL OR inbound_end >= inbound_start);

-- A volta não pode começar antes da ida.
ALTER TABLE routines DROP CONSTRAINT IF EXISTS routines_inbound_after_outbound_check;
ALTER TABLE routines ADD  CONSTRAINT routines_inbound_after_outbound_check
    CHECK (inbound_start IS NULL OR inbound_start >= outbound_start);

CREATE INDEX IF NOT EXISTS idx_routines_trip_type ON routines(trip_type);
