-- 021 — Pausa por bloqueio escalona com quantas vezes seguidas já aconteceu.
--
-- Hoje um bloqueio (BLOCKED, DOM com evidência de anti-bot) pausa a companhia
-- inteira por 1h fixa, sempre — sem nenhuma memória de que já é a quinta vez
-- seguida. Uma rota que ficou dias bloqueada (medido: Azul, GRU→CNF e
-- CGH→SDU, setembro/2026) continua sendo tentada de hora em hora
-- indefinidamente: cada tentativa gasta a sessão de navegador exclusiva da
-- máquina numa rota que provavelmente vai bloquear de novo, e insiste contra
-- o mesmo anti-bot sem nunca dar folga maior.
--
-- `consecutive_blocks` conta bloqueios seguidos por companhia. A pausa passa a
-- escalar (1h → 2h → 4h → 8h → ... teto 24h) enquanto o contador sobe, e volta
-- a 1h assim que a companhia coletar com sucesso de novo — o contador zera na
-- primeira coleta boa, em qualquer rota dela.

BEGIN;

ALTER TABLE airlines
  ADD COLUMN consecutive_blocks INT NOT NULL DEFAULT 0 CHECK (consecutive_blocks >= 0);

COMMIT;
