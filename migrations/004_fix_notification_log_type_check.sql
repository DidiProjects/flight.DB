-- Alinha o CHECK de notification_log.type ao que o código realmente grava.
--
-- Antes:  ('alert', 'best_of_day', 'end_of_period')
--         'scheduled' (email diário) era rejeitado — o INSERT do log estourava
--         APÓS o envio, era engolido pelo try/catch do scheduler e abortava o
--         restante do tick.
--
-- Depois: ('alert', 'scheduled') — espelha NotificationsService (alert + scheduled).
--
-- Dados legados: 'best_of_day' era o nome anterior do email diário das 20h.
-- Migramos esses registros para 'scheduled' para preservar o histórico de
-- auditoria. 'end_of_period' não existe na base.
--
-- ORDEM IMPORTA: o constraint antigo não permite 'scheduled', então é preciso
-- dropá-lo ANTES do UPDATE; senão o próprio UPDATE viola o constraint vigente.

BEGIN;

-- 1) Remove o constraint antigo para liberar o UPDATE.
ALTER TABLE notification_log
  DROP CONSTRAINT IF EXISTS notification_log_type_check;

-- 2) Renomeia o histórico do email diário para o vocabulário atual.
UPDATE notification_log
   SET type = 'scheduled'
 WHERE type IN ('best_of_day', 'end_of_period');

-- 3) Recria o constraint com o conjunto que o código de fato usa.
ALTER TABLE notification_log
  ADD CONSTRAINT notification_log_type_check
  CHECK (type IN ('alert', 'scheduled'));

COMMIT;
