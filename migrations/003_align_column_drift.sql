-- 003 — alinhar colunas divergentes com o 01-schema.sql
--
-- Drift acumulado em bancos antigos: colunas criadas como TEXT onde o schema
-- declara VARCHAR(n)/UUID, uma coluna ausente e uma nullability diferente.
-- Nada aqui muda comportamento da aplicação — é convergência de tipo para que
-- banco existente e banco novo (criado do 01-schema.sql) fiquem idênticos.
--
-- Idempotente. Conversões validadas contra os dados antes de escrever:
--   best_fares.analysis_id  → 0 valores não-castáveis para UUID
--   best_fares.currency     → tamanho máximo 3
--   refresh_tokens.token    → tamanho máximo 128
--   routines.currency       → 0 NULLs

-- ─── flight_offers.currency (ausente) ───────────────────────────────────────
-- Schema: VARCHAR(3) NOT NULL sem default. Como a tabela tem dados, adiciona
-- com default para fazer o backfill e em seguida remove o default, chegando
-- exatamente na definição do schema.
ALTER TABLE flight_offers ADD COLUMN IF NOT EXISTS currency VARCHAR(3);
UPDATE flight_offers SET currency = 'BRL' WHERE currency IS NULL;
ALTER TABLE flight_offers ALTER COLUMN currency SET NOT NULL;
ALTER TABLE flight_offers ALTER COLUMN currency DROP DEFAULT;

-- ─── best_fares: TEXT → tipos do schema ─────────────────────────────────────
ALTER TABLE best_fares
    ALTER COLUMN analysis_id TYPE UUID USING analysis_id::uuid;

ALTER TABLE best_fares
    ALTER COLUMN currency TYPE VARCHAR(3) USING currency::varchar(3);
ALTER TABLE best_fares ALTER COLUMN currency SET DEFAULT 'BRL';

-- ─── refresh_tokens.token: TEXT → VARCHAR(128) ──────────────────────────────
ALTER TABLE refresh_tokens
    ALTER COLUMN token TYPE VARCHAR(128) USING token::varchar(128);

-- Índice com nome divergente: o schema declara idx_refresh_token.
DROP INDEX IF EXISTS idx_refresh_tokens_token;
CREATE INDEX IF NOT EXISTS idx_refresh_token ON refresh_tokens(token);

-- ─── routines.currency: NOT NULL DEFAULT 'BRL' → nullable sem default ───────
-- O schema declara a coluna opcional: a moeda é resolvida em runtime
-- (job histórico → aeroporto de origem), não fixada na rotina.
ALTER TABLE routines ALTER COLUMN currency DROP NOT NULL;
ALTER TABLE routines ALTER COLUMN currency DROP DEFAULT;
