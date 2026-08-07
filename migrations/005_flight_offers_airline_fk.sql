-- 005 — flight_offers.airline: FK para airlines(code)
--
-- Última divergência entre banco existente e 01-schema.sql. Os bancos em uso já
-- têm a FK (sob o nome legado fk_flight_offers_airline); o arquivo de schema
-- declarava a coluna solta, então um banco novo nascia sem a integridade
-- referencial que as tabelas irmãs têm (scraping_jobs.airline e
-- best_fares.airline já referenciam airlines(code)).
--
-- Idempotente. A detecção é pela DEFINIÇÃO (coluna + tabela referenciada), não
-- pelo nome: checar por nome criaria uma FK duplicada em bancos onde ela já
-- existe com o nome legado.

DO $$
DECLARE
    existing_name TEXT;
BEGIN
    SELECT conname INTO existing_name
    FROM pg_constraint
    WHERE conrelid = 'flight_offers'::regclass
      AND contype  = 'f'
      AND confrelid = 'airlines'::regclass
      AND conkey = ARRAY[(SELECT attnum FROM pg_attribute
                          WHERE attrelid = 'flight_offers'::regclass
                            AND attname  = 'airline')]
    LIMIT 1;

    IF existing_name IS NULL THEN
        -- Banco novo / sem a FK: cria com o nome canônico.
        ALTER TABLE flight_offers
            ADD CONSTRAINT flight_offers_airline_fkey
            FOREIGN KEY (airline) REFERENCES airlines(code);
    ELSIF existing_name <> 'flight_offers_airline_fkey' THEN
        -- Banco existente com o nome legado: só normaliza o nome, para ficar
        -- idêntico ao que o 01-schema.sql gera.
        EXECUTE format('ALTER TABLE flight_offers RENAME CONSTRAINT %I TO flight_offers_airline_fkey', existing_name);
    END IF;
END $$;
