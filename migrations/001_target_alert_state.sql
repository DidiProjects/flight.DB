-- 001 — target_alert_state
--
-- Watermark por célula (rotina × data × tipo de tarifa) do alerta 'target'.
-- A tabela já existe no 01-schema.sql, mas bancos criados antes dela nunca a
-- receberam (os init-scripts só rodam na primeira inicialização do volume).
--
-- Sintoma sem esta migration: SchedulerService.runDailyMaintenance quebra com
-- 42P01 relation "target_alert_state" does not exist, em
-- TargetAlertStateRepository.cleanupPastDates.
--
-- Idempotente.

CREATE TABLE IF NOT EXISTS target_alert_state (
    routine_id       UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    flight_date      DATE          NOT NULL,
    fare_type        VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb')),
    notified_amount  NUMERIC(12,2) NOT NULL,
    notified_airline VARCHAR(20),
    notified_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (routine_id, flight_date, fare_type)
);

CREATE INDEX IF NOT EXISTS idx_target_alert_state_flight_date
    ON target_alert_state(flight_date);
