-- 010 — o dedup por execução precisa distinguir as voltas de idas diferentes
--
-- A chave de 007 era (request_id, flight_date, is_return, flight_number). Ela
-- funcionava quando a busca ida-e-volta devolvia UMA lista de voltas.
--
-- Com o laço 1-para-N isso deixa de valer: a MESMA volta (AD4237, 25/09) aparece
-- na lista de várias idas, e com preço potencialmente DIFERENTE em cada uma —
-- é exatamente esse o mecanismo do desconto de ida-e-volta. Sob a chave antiga,
-- o ON CONFLICT DO NOTHING guardaria só a primeira e descartaria em silêncio o
-- preço de todas as outras combinações. O 1-para-N ficaria sem dado.
--
-- Passa a fazer parte da chave o vínculo com a ida. NULLS NOT DISTINCT porque a
-- ida e a tarifa one-way têm paired_outbound_flight NULL e ainda precisam ser
-- deduplicadas entre si (sem isso, cada upsert de ida viraria linha nova).
--
-- Idempotente.

DROP INDEX IF EXISTS idx_flight_fares_no_dup;
CREATE UNIQUE INDEX idx_flight_fares_no_dup
  ON flight_fares(request_id, flight_date, is_return, flight_number, paired_outbound_flight)
  NULLS NOT DISTINCT
  WHERE flight_number IS NOT NULL AND request_id IS NOT NULL;
