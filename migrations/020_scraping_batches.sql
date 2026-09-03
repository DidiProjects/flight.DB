-- 020 — Lote de coleta: uma sessão de navegador percorre vários itens.
--
-- Hoje cada data (one-way) ou par de datas (ida-e-volta) é um job independente,
-- e cada job paga um navegador inteiro: `launch()`, entrada no site e sessão
-- anti-bot validada do zero. Medido na BA em 02→03/09/2026, LHR→GRU: ~2 min de
-- cerimônia para ~3-4 min de coleta, 37 sessões entre 21:01 e 06:12, sucesso até
-- 03:52 e bloqueio contínuo depois.
--
-- E não é pico. Uma rotina RT com janelas de 6 datas gera até 36 itens; com
-- SCRAPE_MAX_IN_FLIGHT_PER_AIRLINE = 1 e ~5-6 min por corrida, a vazão real é de
-- ~5-6 coletas/hora contra uma demanda de 6/hora (cadência de 6h para voo a mais
-- de 90 dias). A fila nunca esvazia: a companhia nunca vê uma pausa.
--
-- O lote troca N sessões por uma. O que ele exige do banco é identidade e estado
-- próprios, por três razões que vieram do código e não da preferência:
--
--   1. o back precisa saber quando o lote VOLTOU INTEIRO, para nunca redespachar
--      um pedaço dele;
--   2. item que falhou não pode ser reagendado sozinho — ele volta no lote de
--      retentativa seguinte;
--   3. uma análise nova para a mesma rota precisa poder descartar o que sobrou da
--      anterior.
--
-- O que NÃO muda: `request_id` continua sendo a identidade do par ida-e-volta
-- (EvaluationService agrupa por ele), continua na chave de dedup de
-- `flight_fares`, e continua sendo uma linha de `analysis_runs`. O `batch_id`
-- fica ACIMA disso, nunca no lugar.

BEGIN;

-- Lote = itens da mesma rota+companhia numa sessão só. A rota é a chave porque
-- `scraping_jobs` deduplica por rota desde 2026-06-27 (não há `routine_id`): o
-- job é propriedade do trajeto, compartilhado por todas as rotinas que o cobrem.
CREATE TABLE scraping_batches (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  airline        VARCHAR(20) NOT NULL REFERENCES airlines(code),
  origin         VARCHAR(10) NOT NULL,
  destination    VARCHAR(10) NOT NULL,

  -- 'closing' é o estado entre o sinal de fechamento do worker e a chegada dos
  -- últimos callbacks de item. Sem ele, um fechamento que passa na frente de um
  -- callback fecharia o lote com item ainda no ar.
  status         VARCHAR(20) NOT NULL DEFAULT 'dispatched'
                 CHECK (status IN ('dispatched', 'running', 'closing',
                                   'completed', 'aborted', 'superseded', 'expired')),

  -- Quantos itens o lote espera. DECREMENTA quando um item é cancelado no meio
  -- da corrida (cancelamento pelo admin), senão `received_count` nunca alcança e
  -- o lote só fecharia pelo backstop de tempo.
  item_count     INT         NOT NULL CHECK (item_count >= 0),
  received_count INT         NOT NULL DEFAULT 0 CHECK (received_count >= 0),

  close_reason   TEXT,
  -- Qual lote tomou o lugar deste. Só preenchido em status 'superseded'.
  superseded_by  UUID        REFERENCES scraping_batches(id) ON DELETE SET NULL,
  -- 1 = primeira tentativa da rota; n+1 = lote de retentativa formado com os
  -- itens que falharam no lote n. É o que permite backoff DE LOTE em vez de
  -- backoff por item.
  attempt        INT         NOT NULL DEFAULT 1 CHECK (attempt >= 1),

  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at      TIMESTAMPTZ,

  CONSTRAINT scraping_batches_closed_when_terminal
    CHECK ((status IN ('dispatched', 'running', 'closing')) = (closed_at IS NULL))
);

-- No máximo UM lote vivo por rota+companhia.
--
-- É o banco garantindo o invariante, não a aplicação: dois disparos manuais
-- simultâneos na mesma rota são um caso real (a rota tem várias rotinas, e o
-- endpoint é assíncrono), e sem isto os dois formariam lotes concorrentes contra
-- a mesma companhia — que é exatamente o que produz duas sessões do mesmo IP no
-- mesmo site, medido na BA em 2026-08-24 com as duas voltando BLOCKED juntas.
CREATE UNIQUE INDEX uq_scraping_batches_rota_viva
  ON scraping_batches (airline, origin, destination)
  WHERE status IN ('dispatched', 'running', 'closing');

CREATE INDEX idx_scraping_batches_status ON scraping_batches(status, created_at DESC);

-- ─── vínculo dos itens ────────────────────────────────────────────────────────

-- ON DELETE SET NULL, não CASCADE: apagar o registro de um lote nunca pode levar
-- junto o job, que é a unidade de agendamento e sobrevive a qualquer corrida.
ALTER TABLE scraping_jobs
  ADD COLUMN batch_id UUID REFERENCES scraping_batches(id) ON DELETE SET NULL;

ALTER TABLE analysis_runs
  ADD COLUMN batch_id UUID REFERENCES scraping_batches(id) ON DELETE SET NULL;

CREATE INDEX idx_scraping_jobs_batch ON scraping_jobs(batch_id) WHERE batch_id IS NOT NULL;
CREATE INDEX idx_analysis_runs_batch ON analysis_runs(batch_id) WHERE batch_id IS NOT NULL;

-- ─── tamanho do lote, por companhia ───────────────────────────────────────────

-- Fica em `airlines` porque é uma capacidade da companhia, como `has_roundtrip`
-- e `has_pts` — o custo por item é estrutural e diferente em cada uma: a Ryanair
-- não precisa do laço 1-para-N (as voltas têm preço fixo), a LATAM ainda faz um
-- passe extra de pontos.
--
-- DEFAULT 1 é a migração inteira: lote de 1 item é, byte a byte, o comportamento
-- de hoje. O caminho de código novo entra em produção em regime idêntico ao
-- antigo, e o tamanho sobe DEPOIS, uma companhia por vez, com medição. Rollback
-- é um UPDATE nesta coluna, não um deploy.
ALTER TABLE airlines
  ADD COLUMN batch_size INT NOT NULL DEFAULT 1 CHECK (batch_size >= 1);

COMMIT;
