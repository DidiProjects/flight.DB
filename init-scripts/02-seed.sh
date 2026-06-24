#!/bin/bash
set -e

# Seed inicial: companhias aéreas
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
INSERT INTO airlines (code, name, currency, active)
VALUES ('azul', 'Azul Linhas Aéreas', 'BRL', true)
ON CONFLICT (code) DO NOTHING;
EOSQL

# Seed do admin — requer ADMIN_EMAIL e ADMIN_INITIAL_PASSWORD
# Usa :'var' para quoting seguro contra SQL injection
if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_INITIAL_PASSWORD" ]; then
    psql -v ON_ERROR_STOP=1 \
         -v admin_email="$ADMIN_EMAIL" \
         -v admin_password="$ADMIN_INITIAL_PASSWORD" \
         --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
         -c "INSERT INTO users (email, password_hash, role, status, must_change_password, provisional_expires_at)
             VALUES (:'admin_email', crypt(:'admin_password', gen_salt('bf', 12)), 'admin', 'active', true, now() + interval '1 day')
             ON CONFLICT (email) DO NOTHING;"
    echo "Admin seed: $ADMIN_EMAIL"
else
    echo "AVISO: ADMIN_EMAIL ou ADMIN_INITIAL_PASSWORD não definidos — admin não criado."
fi
