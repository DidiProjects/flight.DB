# flight.DB

PostgreSQL 16 em Docker (timezone `America/Sao_Paulo`), consumido pelo
`flight.API`. Container `flight-db`, porta 5433, volume `flight_db_data`.

Regras gerais (autonomia, commits, testes, comentários) vivem em `~/.claude/`.
Aqui só o que é armadilha **deste** repositório.

## Estrutura

- `init-scripts/01-schema.sql` — schema completo, **fonte da verdade**. Roda só
  na primeira inicialização do volume.
- `init-scripts/02-seed.sh` — airline `azul` + admin.
- `migrations/NNN_*.sql` — alteração incremental para banco existente. Aplicar
  em ordem, manualmente.
- `design.md` — referência das tabelas.

## Ao mudar o schema

Os três, sempre juntos:

1. migration numerada nova
2. a mesma mudança refletida no `01-schema.sql`
3. `design.md` atualizado

E avisar que o `flight.API` precisa acompanhar (queries e tipos).

## Armadilhas medidas

- **Migration é lida por teste do `flight.API`.** O
  `routineTargetCleanup.integration.test.ts` lia o arquivo do disco para validar
  a regra contra um Postgres real. Apagar migration quebra teste de outro repo —
  conferir antes.
- **Coluna de valor monetário anda em par com a taxa.** `fare_cash_brl` só faz
  sentido com `fx_rate` e `fx_rate_date` na mesma linha: é o que congela o
  câmbio no momento da coleta e impede a régua de 30 dias de se mexer com a
  cotação do dia.
