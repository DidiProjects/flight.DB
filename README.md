# flight.DB

PostgreSQL 16 (Docker) para o sistema de monitoramento de voos. Define schema, seed e container consumidos pelo `flight.API`. Timezone `America/Sao_Paulo`.

## Subir o banco

Requer Docker + Docker Compose. `.env` na raiz (valores default em parênteses):

```env
PG_USER=admin
PG_PASSWORD=admin123
PG_DB=dev-flightDB
ADMIN_EMAIL=admin@flight.local
ADMIN_INITIAL_PASSWORD=changeme123
```

```sh
docker compose up -d
```

Porta host: `5433` (→ 5432 no container). Container: `flight-db`. Volume: `flight_db_data`.

## init-scripts vs migrations

- `init-scripts/` — rodam **uma vez**, na primeira inicialização do volume (Docker `docker-entrypoint-initdb.d`):
  - `01-schema.sql` — schema completo para banco novo.
  - `02-seed.sh` — insere airline `azul` + admin (`ADMIN_EMAIL` / `ADMIN_INITIAL_PASSWORD`, senha via pgcrypto).
- `migrations/NNN_*.sql` — alterações incrementais para bancos **já existentes**. Aplicar manualmente, em ordem. `01-schema.sql` já reflete o resultado de todas as migrations.

Para banco novo, basta o `01-schema.sql`. Em produção, schema já criado → aplicar só a migration nova.

## Tabelas

Monitoramento / histórico de preços (núcleo):

| Tabela | Função |
|---|---|
| `routines` | Rotinas de monitoramento (one-way; ida+volta = 2 rotinas). Targets, margem, modos de notificação. |
| `routine_airlines` | Companhias associadas a cada rotina (N:N). |
| `scraping_jobs` | Estado do scheduler: 1 linha por (airline, origin, destination, flight_date); status/retries/next_run. |
| `flight_fares` | Histórico bruto de tarifas coletadas por job. |
| `flight_fares_daily` | Agregado diário (min/max/avg) por rota/data/tipo. |
| `analysis_runs` | Histórico de execuções de análise (1 por dispatch→callback), rota denormalizada. |
| `notification_log` | Histórico de emails enviados (anti-spam). |

Auth / suporte: `users`, `refresh_tokens`, `password_reset_tokens`, `airlines`, `airports`, `flight_offers`, `best_fares`, `unsubscribe_tokens`.

Detalhes de colunas em [`design.md`](design.md).

## Comandos úteis

```sh
docker exec -it flight-db psql -U admin -d dev-flightDB   # conectar (\dt lista tabelas)
docker logs flight-db                                     # logs
docker compose down                                       # parar (mantém volume)
docker compose down -v                                    # parar e APAGAR dados

# backup / restore
docker exec -t flight-db pg_dump -U admin -d dev-flightDB > backup/flight_backup.sql
cat backup/flight_backup.sql | docker exec -i flight-db psql -U admin -d dev-flightDB
```

> `init-scripts/` só rodam na primeira inicialização do volume. Para re-seed: limpar o volume ou rodar os scripts manualmente.
