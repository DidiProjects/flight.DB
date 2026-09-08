-- 023 — GOL entra ativa, pelo voegol (dinheiro; ida e ida-e-volta).
--
-- `init-scripts/02-seed.sh` passou a cadastrar `gol` junto da `azul`, mas o seed
-- só roda em banco novo. Esta migration é o mesmo cadastro para os bancos que já
-- existem — dev e produção — aplicada à mão, como toda migration aqui.
--
-- Por que `INSERT INTO airlines` numa migration, se 019 diz para não fazer isso:
-- o que 019 mediu quebrando em produção foi uma LISTA de vínculos referenciando
-- companhias que aquele banco não tinha — a FK de `airline_markets` abortava e
-- revertia até o DDL. Aqui a própria `gol` entra primeiro, na mesma transação, e
-- o vínculo de mercado depois; não há FK insatisfeita.
--
-- `ON CONFLICT DO UPDATE`, não `DO NOTHING`: no dev já existe uma linha `gol`
-- placeholder (nome com typo, `active=false`, `has_pts` ligado) de um teste antigo
-- de cobertura. Esta é a entrada de verdade da GOL, e ela crava o estado canônico
-- por cima de qualquer rascunho:
--
--   · `has_cash` e `has_roundtrip` — o voegol coleta ida e ida-e-volta; a busca
--     RT é o fluxo de duas páginas (ida → volta), com as pernas precificadas
--     independentemente (Ryanair, não Azul);
--   · `has_pts`/`has_hyb` false — o Smiles (pontos/híbrido) é outro pacote;
--   · `active=true` — entra oferecível e no ciclo de despacho.
--
-- `batch_size` e `max_dispatches_per_hour` NÃO são tocados: são operacionais,
-- editáveis no admin sem deploy, e o default (1 / 2-por-hora) é o começo certo.
--
-- Mercado `br`: 019 já deixou `('gol','br')` escrito na sua própria seed, guardado
-- por JOIN airlines — não entrou porque a `gol` não existia quando 019 rodou.

BEGIN;

INSERT INTO airlines (code, name, active, has_cash, has_pts, has_hyb, has_roundtrip)
VALUES ('gol', 'GOL Linhas Aéreas', true, true, false, false, true)
ON CONFLICT (code) DO UPDATE SET
  name          = EXCLUDED.name,
  active        = EXCLUDED.active,
  has_cash      = EXCLUDED.has_cash,
  has_pts       = EXCLUDED.has_pts,
  has_hyb       = EXCLUDED.has_hyb,
  has_roundtrip = EXCLUDED.has_roundtrip;

INSERT INTO airline_markets (airline_code, market_code)
VALUES ('gol', 'br')
ON CONFLICT DO NOTHING;

COMMIT;
