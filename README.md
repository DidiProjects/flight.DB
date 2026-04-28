# flight.DB

PostgreSQL database for the flight system. Defines the schema, seed scripts, and container configuration consumed by `flight.API`.

## Stack

- **PostgreSQL 16** — relational database, timezone America/Sao_Paulo
- **Docker** — custom image
- **Docker Compose** — local development setup

## Project structure

```
init-scripts/
  01-schema.sql   ← 8 tables, indexes, updated_at triggers
  02-seed.sh      ← airlines + initial admin user (bcrypt via pgcrypto)
backup/           ← SQL dumps
Dockerfile
docker-compose.yaml
design.md         ← full system design (flight.API + flight.DB)
```

## Schema

| Table | Description |
|---|---|
| `users` | Authenticated users — roles: `admin`, `user` |
| `refresh_tokens` | JWT refresh tokens (revocable) |
| `password_reset_tokens` | Secure tokens for password recovery flow |
| `airlines` | Available airlines with supported fare types (`has_brl`, `has_pts`, `has_hyb`) |
| `routines` | User-defined flight monitoring routines (max 10 per user) |
| `flight_offers` | Raw flight offers received from `scraping.API` |
| `best_fares` | Best accumulated fare per routine/date/direction/type |
| `notification_log` | Email dispatch history — used for anti-spam logic |
| `unsubscribe_tokens` | One-time tokens for unsubscribing from email notifications |

Full schema details and system design in [`design.md`](design.md).

## Running locally

**Requires:** Docker + Docker Compose.

Create `.env` at the project root:

```env
PG_USER=admin
PG_PASSWORD=admin123
PG_DB=dev-flightDB
ADMIN_EMAIL=admin@flight.local
ADMIN_INITIAL_PASSWORD=changeme123
```

Start the container:

```sh
docker compose up
```

On first initialization Docker runs `init-scripts/` automatically — schema + seed. On subsequent starts the volume already exists and the scripts are skipped.

## Useful commands

```sh
# Connect to the database
docker exec -it flight-db psql -U admin -d dev-flightDB

# List tables
\dt

# View logs
docker logs flight-db

# Stop container (keeps volume)
docker compose down

# Stop and remove everything including volume (⚠ destroys data)
docker compose down -v
```

## Backup and restore

```sh
# Generate backup
docker exec -t flight-db pg_dump -U admin -d dev-flightDB > backup/flight_backup.sql

# Restore backup
cat backup/flight_backup.sql | docker exec -i flight-db psql -U admin -d dev-flightDB
```

## Deploy (GitHub Actions)

The workflow `.github/workflows/deploy.yml` publishes via Tailscale + SSH + rsync.

### Secrets

| Secret | Description |
|---|---|
| `POSTGRES_DB` | Production database name |
| `POSTGRES_USER` | PostgreSQL user |
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `ADMIN_EMAIL` | Initial admin email |
| `ADMIN_INITIAL_PASSWORD` | Admin provisional password (must be changed on first login) |
| `SSH_PRIVATE_KEY` | SSH key for server access |
| `TAILSCALE_CLIENT_SECRET` | Tailscale auth key |

### Variables

| Variable | Description |
|---|---|
| `TAILSCALE_IP` | Server IP via Tailscale |
| `DB_PORT` | Exposed PostgreSQL port on the host (`5433`) |
| `RESTORE_BACKUP` | Set to `true` to restore `backup/flight_backup.sql` on deploy |

> **Note:** `init-scripts/` only run on the **first volume initialization**. To re-seed in production, clear the volume or run the scripts manually.
