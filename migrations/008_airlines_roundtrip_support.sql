-- 008 — quais companhias sabem fazer busca ida-e-volta
--
-- Com a coleta de RT por PAR (migration 007), um job de par despachado para uma
-- companhia que só sabe buscar one-way voltaria com as duas pernas avulsas e
-- SEM bundle — exatamente o reaproveitamento que a 007 existe para impedir, só
-- que disfarçado de dado de par, o que é pior que o estado anterior.
--
-- Por isso rotina round_trip só aceita companhia com has_roundtrip = true.
--
-- Hoje só a Azul: a URL de resultados aceita a perna c[1] e devolve ida e volta
-- na mesma tela. As demais seguem apenas one-way até ganharem o fluxo RT.
--
-- Idempotente.

ALTER TABLE airlines ADD COLUMN IF NOT EXISTS has_roundtrip BOOLEAN NOT NULL DEFAULT false;

UPDATE airlines SET has_roundtrip = true  WHERE code = 'azul';
UPDATE airlines SET has_roundtrip = false WHERE code <> 'azul';
