-- 024 — Justiça por rotina na fila de coleta.
--
-- `scraping_jobs.priority` (staleness + proximidade da data) ordena a fila, mas
-- é justo entre JOBS, não entre ROTINAS: jobs são deduplicados por rota+datas.
-- Uma rotina de janela larga fabrica muitos jobs (só-ida até 30, ida-e-volta
-- até 25 pares) e, no mesmo tier de proximidade, segura o topo da fila —
-- consumindo todo o `max_dispatches_per_hour` da companhia por horas enquanto
-- outra rotina com um job só disputa 1-contra-25.
--
-- A correção é um terceiro termo em `updatePriorities`: horas desde o último
-- despacho DA ROTINA naquela companhia. Assim que a rotina larga recebe UM
-- despacho, todos os jobs dela perdem o bônus no mesmo instante (compartilham a
-- linha da rotina), e o job da outra rotina passa na frente no tick seguinte.
-- Alternância no nível da rotina, sem tocar no caminho quente (`claimBatch`).
--
-- Este migration só cria o ESTADO que o termo lê:
--
--  * `routine_airline_dispatch` — uma linha por (rotina, companhia), carimbada
--    em `dispatchBatch` (despacho, não sucesso: a justiça é sobre acesso à
--    sessão de navegador, que o despacho consome independente do resultado).
--
--  * view `job_routine_membership` — o casamento job↔rotina (rota, janela de
--    datas, trip_type) num lugar só: a lógica de `upsertFromRoutines`,
--    invertida. View e não tabela materializada — sem drift, sem manutenção em
--    retire/revive/edit de rotina.

BEGIN;

CREATE TABLE routine_airline_dispatch (
    routine_id         UUID        NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline            VARCHAR(20) NOT NULL REFERENCES airlines(code),
    last_dispatched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (routine_id, airline)
);

CREATE VIEW job_routine_membership AS
SELECT j.id AS job_id,
       r.id AS routine_id
  FROM scraping_jobs j
  JOIN routine_airlines ra ON ra.airline = j.airline
  JOIN routines        r  ON r.id = ra.routine_id
 WHERE r.is_active = true
   AND r.origin      = j.origin
   AND r.destination = j.destination
   AND j.flight_date BETWEEN r.outbound_start AND r.outbound_end
   AND (
        (j.return_date IS NULL     AND r.trip_type = 'one_way')
     OR (j.return_date IS NOT NULL AND r.trip_type = 'round_trip'
         AND j.return_date BETWEEN r.inbound_start AND r.inbound_end)
   );

COMMIT;
