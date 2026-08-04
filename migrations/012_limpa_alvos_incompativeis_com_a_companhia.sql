-- 012 — apaga alvo que a companhia da rotina não sabe precificar
--
-- Até agora a API validava a companhia só na CRIAÇÃO, e só `has_roundtrip`.
-- Alvo e prioridade nunca eram revalidados na edição: bastava criar a rotina
-- numa companhia que suporta e depois trocar a companhia. Foi assim que
-- sobraram rotinas com alvo híbrido (20.000 pts + R$400) em Ryanair, BA e
-- LATAM, três companhias com `has_hyb = false`.
--
-- A validação passou a existir nos três caminhos (create, update e
-- adminUpdate), sobre o estado FINAL da rotina. Sem esta limpeza, as linhas
-- antigas ficariam presas: qualquer edição futura seria recusada por causa de um
-- alvo que a pessoa não pode nem ver na tela daquela companhia.
--
-- Regra igual à da API: a dimensão só cai quando NENHUMA companhia da rotina a
-- precifica. Rotina [azul, latam] com alvo em pontos continua válida — a Azul
-- avalia, a LATAM só não contribui.
--
-- Idempotente.

-- Alvo híbrido (os dois campos caem juntos: meio alvo híbrido não é alvo).
UPDATE routines r
SET target_hyb_pts = NULL, target_hyb_cash = NULL
WHERE (r.target_hyb_pts IS NOT NULL OR r.target_hyb_cash IS NOT NULL)
  AND NOT EXISTS (
    SELECT 1 FROM routine_airlines ra JOIN airlines a ON a.code = ra.airline
    WHERE ra.routine_id = r.id AND a.has_hyb
  );

-- Alvo em pontos.
UPDATE routines r
SET target_pts = NULL
WHERE r.target_pts IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM routine_airlines ra JOIN airlines a ON a.code = ra.airline
    WHERE ra.routine_id = r.id AND a.has_pts
  );

-- Alvo em dinheiro.
UPDATE routines r
SET target_cash = NULL
WHERE r.target_cash IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM routine_airlines ra JOIN airlines a ON a.code = ra.airline
    WHERE ra.routine_id = r.id AND a.has_cash
  );

-- Prioridade impossível volta para dinheiro — é a única dimensão que toda
-- companhia ativa publica hoje. Deixar como está manteria a rotina inelegível
-- para edição, e a prioridade é o campo que decide o que a avaliação compara:
-- apontar para uma dimensão que ninguém precifica é rotina que nunca alerta.
UPDATE routines r
SET priority = 'cash'
WHERE r.priority IN ('pts', 'hyb')
  AND NOT EXISTS (
    SELECT 1 FROM routine_airlines ra JOIN airlines a ON a.code = ra.airline
    WHERE ra.routine_id = r.id
      AND ((r.priority = 'pts' AND a.has_pts) OR (r.priority = 'hyb' AND a.has_hyb))
  )
  AND EXISTS (
    SELECT 1 FROM routine_airlines ra JOIN airlines a ON a.code = ra.airline
    WHERE ra.routine_id = r.id AND a.has_cash
  );
