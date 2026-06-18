-- Moeda passa a ser propriedade do MERCADO (aeroporto), não mais global da companhia.
-- A moeda da rotina passa a ser resolvida por airports.currency da origem.
--
-- airports.currency vira obrigatória. Backfill: registros sem moeda herdam a moeda
-- legada da companhia (airlines.currency) antes do SET NOT NULL.

BEGIN;

UPDATE airports a
   SET currency = al.currency
  FROM airlines al
 WHERE a.airline_code = al.code
   AND a.currency IS NULL;

ALTER TABLE airports
  ALTER COLUMN currency SET NOT NULL;

COMMIT;
