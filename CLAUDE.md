# flight.DB — Instruções para Claude

PostgreSQL 16 em Docker (timezone `America/Sao_Paulo`), consumido pelo `flight.API`.

## Estrutura

- `init-scripts/01-schema.sql` — schema completo (banco novo). `init-scripts/02-seed.sh` — seed airline `azul` + admin. Rodam **só na primeira inicialização** do volume.
- `migrations/NNN_*.sql` — alterações incrementais para bancos existentes; aplicar em ordem, manualmente. O `01-schema.sql` já reflete todas as migrations.
- `docker-compose.yml` / `Dockerfile` — container `flight-db`, porta host `5433`, volume `flight_db_data`.
- `design.md` — referência das tabelas.

## Ao mudar o schema

- Criar uma migration numerada nova **e** refletir a mudança em `01-schema.sql`.
- Atualizar `design.md` e avisar para sincronizar o `flight.API` (queries/tipos).

## Regras permanentes

- **Dados sensíveis:** NUNCA versionar credenciais, senhas, tokens, API keys ou dados pessoais reais.
- **Autonomia:** operar com máxima autonomia; só pedir confirmação em risco real de perda de dados irreversível.
