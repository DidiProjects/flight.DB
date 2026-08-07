-- 016 — a moeda de cadastro da companhia sai de cena
--
-- Segunda metade da 015, adiada de propósito: naquele momento o
-- `AirlinesRepository` ainda selecionava a coluna, e derrubá-la teria quebrado
-- TODA consulta de companhia — inclusive a criação de rotina. Expand/contract:
-- primeiro o código para de ler, depois a coluna cai.
--
-- Por que sai: `airlines.currency` alimentava o `resolveCurrency` da rotina,
-- junto com `airports.currency`. Os dois cadastros estão errados (a BA tem GBP
-- nos 1192 aeroportos, inclusive os 46 no Brasil), e é daí que vinha rotina
-- GRU→LHR marcada em libra recebendo tarifa em real.
--
-- No lugar: a moeda da COLETA vem do texto do preço no scraping, por tarifa; e
-- a moeda do ALVO é sempre Real, fixa.
--
-- `airports.currency` fica de pé por ora (decisão de 2026-08-04), sem consumo.
--
-- Idempotente.

ALTER TABLE airlines DROP COLUMN IF EXISTS currency;
