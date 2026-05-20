-- Migration 004: Adiciona coluna airline em notification_log
--
-- Permite rastrear referência de notificação por airline, necessário para
-- avaliação consolidada por airline (múltiplas airlines por rotina).
-- Registros anteriores ficam com airline = NULL (sem FK obrigatória).

BEGIN;

ALTER TABLE notification_log
  ADD COLUMN airline VARCHAR(20) REFERENCES airlines(code);

-- Índice para lookup por airline (findLast / findLastByType por airline)
CREATE INDEX idx_notif_log_airline_lookup
  ON notification_log(routine_id, fare_type, airline, sent_at DESC);

COMMIT;
