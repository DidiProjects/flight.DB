-- 022 — Teto de despachos por hora, por companhia.
--
-- Concorrência (SCRAPE_MAX_IN_FLIGHT_PER_AIRLINE) limita quantas coletas de
-- uma companhia rodam AO MESMO TEMPO — não quantas COMEÇAM por hora. Assim
-- que uma termina, a próxima já é reivindicável no instante seguinte; um
-- grid de datas grande bate na companhia sem folga nenhuma, e o backoff
-- (021) só age depois que algo já deu errado.
--
-- `max_dispatches_per_hour` é o teto duro que falta: antes de reivindicar um
-- lote, o scheduler conta quantos lotes daquela companhia já foram criados
-- na última hora e para de despachar quando bate o número. Editável por
-- companhia no mesmo admin que já edita `batch_size`, sem deploy.
--
-- Default 2/h: folga suficiente pra cadência normal (30-45min por lote,
-- medido) sem abrir mão do teto quando o grid é grande.

BEGIN;

ALTER TABLE airlines
  ADD COLUMN max_dispatches_per_hour INT NOT NULL DEFAULT 2 CHECK (max_dispatches_per_hour >= 1);

COMMIT;
