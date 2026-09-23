-- 025 — easyJet entra ativa, cash e ida-e-volta.
--
-- Como o piloto da GOL (023): `init-scripts/02-seed.sh` só roda em banco novo,
-- então o cadastro da easyJet entra aqui, à mão, pros bancos que já existem —
-- dev e produção — como toda migration deste repositório.
--
-- `has_cash` e `has_roundtrip` — o scraper coleta ida e ida-e-volta pelo
-- formulário da home; a chave "Return trip / One way" fica dentro do datepicker
-- (scraping.API/src/scrapers/easyjet.ts). Não existe flag de "só ida": toda
-- companhia ativa com `has_cash` aceita rotina só de ida, então as duas precisam
-- funcionar antes de `active=true`.
--
-- Depende do scraping.API com camoufox 152+ na máquina que coleta. Com o 135 a
-- busca da easyJet (`POST /funnel/api/query`) levou 403 do Akamai em 10 de 10
-- tentativas (medido 2026-09-23) — aplicar esta migration antes disso põe a
-- companhia no ciclo de despacho só para colecionar bloqueio.
-- `has_pts`/`has_hyb` false — a easyJet não tem programa de milhas com resgate
-- de passagem própria equivalente ao Smiles/TudoAzul; não há pacote de pontos
-- para essa companhia.
--
-- `batch_size` e `max_dispatches_per_hour` NÃO são tocados: são operacionais,
-- editáveis no admin sem deploy, e o default (1 / 2-por-hora) é o começo certo
-- pra um piloto — mesmo raciocínio da 023.
--
-- Mercado: easyJet é o mesmo caso jurídico da Ryanair (019) — companhia
-- pan-europeia operando sob múltiplos AOCs (easyJet Europe, Áustria — espaço
-- único europeu; easyJet UK, Reino Unido — separado desde o Brexit). Entra nos
-- dois mercados que a Ryanair já usa, 'eee' e 'gb', não um mercado novo.

BEGIN;

INSERT INTO airlines (code, name, active, has_cash, has_pts, has_hyb, has_roundtrip)
VALUES ('easyjet', 'easyJet', true, true, false, false, true)
ON CONFLICT (code) DO UPDATE SET
  name          = EXCLUDED.name,
  active        = EXCLUDED.active,
  has_cash      = EXCLUDED.has_cash,
  has_pts       = EXCLUDED.has_pts,
  has_hyb       = EXCLUDED.has_hyb,
  has_roundtrip = EXCLUDED.has_roundtrip;

INSERT INTO airline_markets (airline_code, market_code)
VALUES ('easyjet', 'eee'),
       ('easyjet', 'gb')
ON CONFLICT DO NOTHING;

COMMIT;
