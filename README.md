# flight.DB

Banco de dados PostgreSQL do sistema flight. Define o schema, seeds e configurações de container para uso pelo `flight.API`.

## Stack

- **PostgreSQL 16** — banco relacional, timezone America/Sao_Paulo
- **Docker** — imagem customizada
- **Docker Compose** — setup local

## Estrutura

```
init-scripts/
  01-schema.sql   ← 7 tabelas, indexes, triggers updated_at
  02-seed.sh      ← airlines + admin inicial (bcrypt via pgcrypto)
backup/           ← dumps SQL
Dockerfile
docker-compose.yaml
design.md         ← design completo do sistema (flight.API + flight.DB)
```

## Schema

7 tabelas: `users`, `password_reset_tokens`, `airlines`, `routines`, `flight_offers`, `best_fares`, `notification_log`, `unsubscribe_tokens`.

Detalhes completos em [`design.md`](design.md).

## Rodando localmente

**Pré-requisito:** Docker + Docker Compose.

Crie o `.env` na raiz:

```env
PG_USER=admin
PG_PASSWORD=admin123
PG_DB=flightdb
ADMIN_EMAIL=admin@flight.local
ADMIN_INITIAL_PASSWORD=changeme123
```

Suba o container:

```sh
docker compose up
```

Na primeira inicialização o Docker executa os `init-scripts/` automaticamente — schema + seed. Nas reinicializações seguintes o volume já existe e os scripts não rodam novamente.

## Comandos úteis

```sh
# Conectar ao banco
docker exec -it flight-db psql -U admin -d flightdb

# Listar tabelas
\dt

# Ver logs
docker logs flight-db

# Parar e remover container (mantém volume)
docker compose down

# Parar e remover tudo, inclusive volume (⚠ apaga dados)
docker compose down -v
```

## Backup e restauração

```sh
# Gerar backup
docker exec -t flight-db pg_dump -U admin -d flightdb > backup/flight_backup.sql

# Restaurar backup
cat backup/flight_backup.sql | docker exec -i flight-db psql -U admin -d flightdb
```

## Deploy (GitHub Actions)

O workflow `.github/workflows/deploy.yml` publica via Tailscale + SSH + rsync.

### Secrets

| Secret | Descrição |
|---|---|
| `POSTGRES_DB` | Nome do banco em produção |
| `POSTGRES_USER` | Usuário do PostgreSQL |
| `POSTGRES_PASSWORD` | Senha do PostgreSQL |
| `ADMIN_EMAIL` | Email do admin inicial |
| `ADMIN_INITIAL_PASSWORD` | Senha provisória do admin |
| `SSH_PRIVATE_KEY` | Chave SSH para acesso ao servidor |
| `TS_OAUTH_CLIENT_ID` | OAuth client ID do Tailscale |
| `TS_OAUTH_SECRET` | OAuth secret do Tailscale |

### Variables

| Variable | Descrição |
|---|---|
| `TAILSCALE_IP` | IP do servidor via Tailscale |
| `DB_PORT` | Porta exposta do PostgreSQL |
| `RESTORE_BACKUP` | `true` para restaurar `backup/flight_backup.sql` no deploy |

O OAuth client do Tailscale precisa do scope `devices:write`. Crie em [tailscale.com/s/oauth-clients](https://tailscale.com/s/oauth-clients).
