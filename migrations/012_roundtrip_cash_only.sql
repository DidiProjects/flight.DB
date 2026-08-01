-- 012 — round-trip só é monitorado em dinheiro
--
-- A ida é selecionada em REAIS de propósito: em pontos a Azul exige login do
-- TudoAzul e a volta fica inacessível. Só que, escolhida a tarifa de ida, a
-- companhia deixa de renderizar o seletor de moeda da lista de voltas — a moeda
-- da reserva já está definida. Resultado: as voltas voltam sem `fare_pts` e sem
-- `fare_hyb_*`, e um par em pontos NUNCA fecha total.
--
-- Decisão de produto (2026-08-01): rotina round_trip aceita apenas `priority`
-- 'cash' e alvo em dinheiro. Deixar uma rotina RT em pts/hyb a manteria ligada
-- prometendo um alerta que não chega — pior que recusá-la na entrada.
--
-- MEDIDA TEMPORÁRIA. Cai quando a volta em pontos for obtível (bundle da Fase 2
-- ou companhia que publique a volta em pontos). A validação viva está no
-- flight.API (`roundTripPricingError`); aqui é só o saneamento do que já existe.
--
-- Sem CHECK constraint de propósito: a regra é temporária e depende de uma
-- limitação de UMA companhia. Fixá-la no schema criaria uma migration de
-- reversão só para voltar atrás quando a coleta melhorar.
--
-- Idempotente.

UPDATE routines
   SET priority        = 'cash',
       target_pts      = NULL,
       target_hyb_pts  = NULL,
       target_hyb_cash = NULL,
       updated_at      = NOW()
 WHERE trip_type = 'round_trip'
   AND (priority <> 'cash'
        OR target_pts      IS NOT NULL
        OR target_hyb_pts  IS NOT NULL
        OR target_hyb_cash IS NOT NULL);
