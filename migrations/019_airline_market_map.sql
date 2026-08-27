-- 019 — Mapa de mercado: quais companhias fazem sentido para um trajeto.
--
-- Hoje quem decide isso é o FRONT, em `RoutineForm`, perguntando se a lista de
-- aeroportos da companhia contém as duas pontas do trajeto. Medido na `airports`
-- desta base, esse filtro:
--
--   · oferece GOL e LATAM para um Madri-Barcelona, e British Airways para
--     Congonhas-Santos Dumont;
--   · deixa a LATAM reivindicar 2,27 M de pares direcionais e a BA 1,42 M, que
--     nenhuma das duas opera. As listas delas são destinos BILHETÁVEIS, com
--     codeshare dentro — não rede operada.
--
-- Duas alternativas foram testadas e reprovadas antes desta. Derivar o país-sede
-- pela contagem de aeroportos faz BA e LATAM parecerem americanas (a cauda longa
-- de destinos bilhetáveis é dominada pelos EUA). Ordenar por tamanho de rede
-- acerta 2 de 4 rotas conhecidas.
--
-- O que discrimina é DIREITO DE TRÁFEGO. Companhia estrangeira não opera voo
-- doméstico em outro país — cabotagem é restrição legal, não preferência
-- comercial. A exceção é o mercado único europeu, e é exatamente por isso que a
-- Ryanair, irlandesa, voa MAD-BCN e FCO-PMO.
--
-- Não é inferível do dado que temos: é fato jurídico, e entra escrito à mão.
-- São 1 a 5 linhas por companhia.

-- Transação explícita: DDL e seed entram juntos ou não entram.
--
-- A atomicidade não pode depender de como a migration é invocada. Em 2026-08-27
-- a tentativa em produção falhou na FK do seed e reverteu tudo, DDL incluído —
-- que é o comportamento certo, mas só aconteceu porque quem rodou passou
-- `--single-transaction`. Com `psql -f` puro cada comando commita sozinho, e a
-- mesma falha teria deixado as tabelas criadas e o mapa pela metade: um banco
-- em que toda companhia é fail-closed, sem candidata para trajeto nenhum.
BEGIN;

-- ─── markets ─────────────────────────────────────────────────────────────────
-- Um mercado é um conjunto de países com cabotagem livre entre si. País isolado
-- é um mercado de um país só — sem caso especial no modelo nem na consulta.

CREATE TABLE markets (
  code       VARCHAR(10)  PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE market_countries (
  market_code  VARCHAR(10) NOT NULL REFERENCES markets(code) ON DELETE CASCADE,
  -- Minúsculo sempre. A `airports` tem a caixa da GOL em MAIÚSCULA e o resto em
  -- minúscula, então toda comparação por país precisa de lower() dos dois lados.
  country_code VARCHAR(2)  NOT NULL CHECK (country_code = lower(country_code)),
  PRIMARY KEY (market_code, country_code)
);

CREATE INDEX idx_market_countries_country ON market_countries(country_code);

-- ─── airline_markets ─────────────────────────────────────────────────────────
-- N-para-N, e as companhias que já existem provam por quê: a Ryanair pertence ao
-- EEE pelo AOC irlandês E ao Reino Unido pelo AOC britânico separado que mantém
-- desde o Brexit (é o que a autoriza a voar STN-EDI); a LATAM são cinco
-- companhias nacionais num grupo.
--
-- Companhia sem linha aqui NUNCA é candidata — fail-closed. O contrário
-- reintroduz em silêncio o ruído que este mapa remove. Em troca, companhia ativa
-- sem mercado é erro de configuração, e a API precisa reclamar disso.

CREATE TABLE airline_markets (
  airline_code VARCHAR(20) NOT NULL REFERENCES airlines(code) ON DELETE CASCADE,
  market_code  VARCHAR(10) NOT NULL REFERENCES markets(code)  ON DELETE RESTRICT,
  PRIMARY KEY (airline_code, market_code)
);

-- ─── seed ────────────────────────────────────────────────────────────────────

INSERT INTO markets (code, name) VALUES
  ('br',  'Brasil'),
  ('cl',  'Chile'),
  ('pe',  'Peru'),
  ('co',  'Colômbia'),
  ('ec',  'Equador'),
  ('gb',  'Reino Unido'),
  ('eee', 'Espaço Econômico Europeu');

INSERT INTO market_countries (market_code, country_code) VALUES
  ('br','br'), ('cl','cl'), ('pe','pe'), ('co','co'), ('ec','ec'), ('gb','gb');

-- EEE = os 27 da UE mais Islândia, Liechtenstein e Noruega. O Reino Unido NÃO
-- está aqui: saiu com o Brexit, e é por isso que a BA não pode mais operar
-- doméstico na Itália.
INSERT INTO market_countries (market_code, country_code)
SELECT 'eee', c FROM unnest(ARRAY[
  'at','be','bg','hr','cy','cz','dk','ee','fi','fr','de','gr','hu','ie','it',
  'lv','lt','lu','mt','nl','pl','pt','ro','sk','si','es','se','is','li','no'
]) c;

-- Só entra vínculo de companhia que EXISTE naquele banco.
--
-- `airlines` é dado operacional, não de schema: o único cadastro que o projeto
-- faz sozinho é o da `azul` (`init-scripts/02-seed.sh`), e as demais entram por
-- ambiente. Cravar a lista aqui derrubava a migration INTEIRA num banco que não
-- tivesse todas — medido em produção em 2026-08-27, que não tem a `gol`
-- (`active = false`, cadastrada só esperando voltar): a FK abortou e a
-- transação reverteu até o DDL.
--
-- Quem cadastra a companhia cadastra o mercado dela junto, como o `02-seed.sh`
-- já faz com a `azul` — "entra junto do cadastro dela, nunca depois". Por isso
-- a `gol` continua na lista: no dia em que ela for cadastrada, o vínculo dela
-- já está escrito aqui, e este é o registro de qual mercado é o dela.
INSERT INTO airline_markets (airline_code, market_code)
SELECT v.airline_code, v.market_code
FROM (VALUES
  ('azul',           'br'),
  ('gol',            'br'),   -- active = false hoje; mapeada para quando voltar
  ('latam',          'br'),
  ('latam',          'cl'),
  ('latam',          'pe'),
  ('latam',          'co'),
  ('latam',          'ec'),
  ('britishairways', 'gb'),
  ('ryanair',        'eee'),
  ('ryanair',        'gb')
) AS v(airline_code, market_code)
JOIN airlines a ON a.code = v.airline_code;

COMMIT;
