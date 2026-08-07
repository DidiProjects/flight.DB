-- 015 — a moeda passa a ser obrigatória, e o Real deixa de ser carimbado
--
-- A moeda era deduzida de cadastro (`airlines.currency` → tarifas já coletadas →
-- `airports.currency`) e o cadastro está errado: a BA tem GBP nos 1192
-- aeroportos, inclusive os 46 no Brasil; a LATAM tem BRL nos 1509, inclusive
-- LHR e DUB. Resultado: rotina GRU→LHR marcada em libra recebendo tarifa em
-- real.
--
-- A partir de agora a moeda vem do TEXTO DO PREÇO no scraping, e de mais lugar
-- nenhum (ver moeda-design.md). Aqui o banco passa a exigir isso.
--
-- ⚠ Ordem importa. Esta migration só é segura DEPOIS de a `scraping.API` parar
-- de emitir tarifa sem moeda e de o `ScrapeService` filtrar as que chegarem
-- assim — o INSERT de tarifas é UM comando multi-linha, então uma linha sem
-- moeda abortaria a coleta inteira, não só a oferta ruim.
--
-- O `DROP COLUMN airlines.currency` NÃO está aqui de propósito: o
-- `AirlinesRepository` ainda seleciona a coluna, e derrubá-la agora quebraria
-- toda consulta de companhia (inclusive a criação de rotina). Ele vem numa
-- migration própria, depois de o código parar de ler.
--
-- Idempotente.

-- 1. Tarifa sem moeda deixa de ser aceita. Verificado: 0 nulas no dev.
ALTER TABLE flight_fares ALTER COLUMN currency SET NOT NULL;

-- 2. Fim do Real carimbado no que não é Real. A coluna segue NOT NULL — o que
--    sai é o DEFAULT que preenchia sozinho quando ninguém informava.
ALTER TABLE best_fares ALTER COLUMN currency DROP DEFAULT;

-- 3. O watermark passa a guardar a COMPOSIÇÃO original do preço.
--
--    Ele guarda o melhor preço já alertado para a célula (rotina, data, tipo) e
--    sobrevive entre ciclos. Com alvo em Real, o valor comparado passaria a ser
--    convertido — e aí o câmbio andar viraria queda de preço: os mesmos £730 a
--    6,83 dão R$4.986 e a 6,60 dão R$4.818, e o sistema anunciaria recorde sem
--    a companhia ter mexido em nada.
--
--    Guardando a composição original ([{direction, currency, amount}, ...]),
--    composição idêntica significa que o preço não mudou — não alerta,
--    independente do câmbio.
ALTER TABLE target_alert_state
  ADD COLUMN IF NOT EXISTS notified_breakdown JSONB;
