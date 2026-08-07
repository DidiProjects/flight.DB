-- 009 — ligação 1-para-N entre a ida e suas voltas
--
-- Na Azul, as voltas de uma busca ida-e-volta são precificadas NO CONTEXTO da
-- ida escolhida: seleciona-se uma tarifa de ida e só então aparecem as voltas
-- daquela combinação. Voltas de idas diferentes podem ter preços diferentes —
-- é exatamente por isso que o desconto de ida-e-volta pode existir.
--
-- Sem esta coluna as voltas de todas as idas cairiam no mesmo balaio e a
-- avaliação voltaria a somar mínimos independentes, que é o que se quer evitar.
--
-- Preenchido SÓ nas linhas de volta, com o número do voo de ida que as originou.
-- NULL na ida e em qualquer tarifa one-way.
--
-- Idempotente.

ALTER TABLE flight_fares ADD COLUMN IF NOT EXISTS paired_outbound_flight VARCHAR(20);

CREATE INDEX IF NOT EXISTS idx_flight_fares_paired_outbound
  ON flight_fares(request_id, paired_outbound_flight)
  WHERE paired_outbound_flight IS NOT NULL;
