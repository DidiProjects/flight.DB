-- 001_airline_currency_optional.sql
-- Moeda por companhia aérea (airlines.currency) como parâmetro OPCIONAL.
--
-- Para companhias cuja tarifa é sempre na mesma moeda (ex. Latam/Azul, sempre BRL),
-- a moeda pode ser fixada na própria companhia. Quando definida, ela tem PRIORIDADE
-- MÁXIMA na resolução da moeda da rotina, na ordem:
--   1. airlines.currency, se definida;
--   2. flight_fares.currency de um job já coletado para o trajeto/companhia;
--   3. moeda do aeroporto de ORIGEM (airports.currency);
--   4. indefinida (NULL).
--
-- Coluna nullable e sem default: companhia sem moeda definida cai na resolução dinâmica.
-- Idempotente: re-adiciona a coluna se foi removida e garante que é opcional.

ALTER TABLE airlines ADD COLUMN IF NOT EXISTS currency VARCHAR(3);
ALTER TABLE airlines ALTER COLUMN currency DROP DEFAULT;
ALTER TABLE airlines ALTER COLUMN currency DROP NOT NULL;

-- Companhias conhecidas operam sempre em BRL.
UPDATE airlines SET currency = 'BRL' WHERE code = 'azul' AND currency IS NULL;
