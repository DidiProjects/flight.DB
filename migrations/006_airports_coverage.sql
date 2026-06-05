-- ─── 006_airports_coverage ───────────────────────────────────────────────────
-- Cria a tabela airports para armazenar os aeroportos cobertos por cada companhia aérea.

CREATE TABLE IF NOT EXISTS airports (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  airline_code    VARCHAR(20) NOT NULL REFERENCES airlines(code) ON DELETE CASCADE,
  airport_code    VARCHAR(10) NOT NULL,
  name            VARCHAR(255),
  timezone        VARCHAR(100),
  country_code    VARCHAR(10),
  country_name    VARCHAR(255),
  city            VARCHAR(255),
  region          VARCHAR(255),
  currency        VARCHAR(10),
  updated_at      TIMESTAMPTZ  DEFAULT now(),
  CONSTRAINT airports_airline_airport_uk UNIQUE (airline_code, airport_code)
);

CREATE INDEX IF NOT EXISTS idx_airports_airline_code ON airports(airline_code);
CREATE INDEX IF NOT EXISTS idx_airports_airport_code ON airports(airport_code);
CREATE INDEX IF NOT EXISTS idx_airports_city        ON airports(city);
