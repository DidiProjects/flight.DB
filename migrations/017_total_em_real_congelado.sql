-- 017: total em Real congelado no momento da análise
--
-- Até aqui a conversão de moeda acontecia em tempo de LEITURA (card de melhor
-- preço) e no ciclo de avaliação, sem nada persistido. Duas consequências:
--
--   1. toda abertura de histórico batia na API de câmbio;
--   2. a régua de 30 dias mudava de valor conforme a cotação do dia — uma queda
--      da libra virava "o voo baratear", misturando câmbio com preço.
--
-- A partir daqui a conversão é feita UMA vez, na ingestão da análise, e gravada
-- na linha junto com a taxa usada. O histórico passa a refletir o câmbio de
-- quando a rotina rodou, e as somas de par voltam a caber em SQL — antes elas
-- exigiam `i.currency = o.currency`, guarda que descartava todo par cujas
-- pernas vinham de mercados diferentes (BA saindo de LHR: ida GBP, volta BRL).

ALTER TABLE flight_fares
  ADD COLUMN IF NOT EXISTS fare_cash_brl     NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS fare_hyb_cash_brl NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS fx_rate           NUMERIC(18,8),
  ADD COLUMN IF NOT EXISTS fx_rate_date      DATE;

COMMENT ON COLUMN flight_fares.fare_cash_brl IS
  'fare_cash convertido para Real na coleta. NULL = linha anterior à 017, ou sem cotação confiável no momento.';
COMMENT ON COLUMN flight_fares.fare_hyb_cash_brl IS
  'Parte em dinheiro do híbrido, convertida para Real na coleta.';
COMMENT ON COLUMN flight_fares.fx_rate IS
  'Quantos BRL valia 1 unidade de `currency` na coleta. 1 quando a tarifa já era em Real.';
COMMENT ON COLUMN flight_fares.fx_rate_date IS
  'Data DA COTAÇÃO usada (o BCE publica em dia útil), não a data da coleta.';

-- Linha já em Real não precisa de cotação: o valor é ele mesmo. Isso faz todo o
-- histórico existente (integralmente BRL) continuar servindo sem backfill de
-- taxas antigas. Linhas em outra moeda ficam com NULL e são ignoradas pelas
-- somas em Real até serem recolhidas.
UPDATE flight_fares
   SET fare_cash_brl     = fare_cash,
       fare_hyb_cash_brl = fare_hyb_cash,
       fx_rate           = 1,
       fx_rate_date      = scraped_at::date
 WHERE currency = 'BRL'
   AND fare_cash_brl IS NULL;
