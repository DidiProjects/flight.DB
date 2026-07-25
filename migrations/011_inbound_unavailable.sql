-- 011 — volta indefinida por limitação conhecida
--
-- Em pontos, ao selecionar a tarifa a Azul abre modal de login do programa de
-- fidelidade e a volta fica inacessível. A volta EXISTE — só não conseguimos
-- vê-la. Isso é diferente de uma volta que sumiu sem motivo (fallback one-way,
-- DOM mudou), que continua sendo dado corrompido.
--
-- Decisão de produto (2026-07-25): par com volta indefinida é EXIBIDO sem total
-- e NÃO alerta. Se a volta é desconhecida, o preço da ida não é o preço da
-- viagem: comparar só a ida contra o target dispararia alerta num valor que não
-- existe ("achamos por R$ 365" quando a viagem custa R$ 931+).
--
-- Marcada só na linha de IDA, por quem faz a coleta. FALSE em tudo o mais,
-- inclusive em tarifa one-way (onde a pergunta não faz sentido).
--
-- Idempotente.

ALTER TABLE flight_fares
  ADD COLUMN IF NOT EXISTS inbound_unavailable BOOLEAN NOT NULL DEFAULT FALSE;
