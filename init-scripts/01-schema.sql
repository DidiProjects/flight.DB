SET timezone = 'America/Sao_Paulo';

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─── users ───────────────────────────────────────────────────────────────────

CREATE TABLE users (
    id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email                  VARCHAR(255) UNIQUE NOT NULL,
    name                   VARCHAR(100) NOT NULL,
    password_hash          VARCHAR(255) NOT NULL,
    role                   VARCHAR(10)  NOT NULL DEFAULT 'user'    CHECK (role   IN ('admin', 'user')),
    status                 VARCHAR(20)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'suspended')),
    must_change_password   BOOLEAN      NOT NULL DEFAULT true,
    provisional_expires_at TIMESTAMPTZ,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── refresh_tokens ──────────────────────────────────────────────────────────

CREATE TABLE refresh_tokens (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      VARCHAR(128) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ  NOT NULL,
    used_at    TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── password_reset_tokens ───────────────────────────────────────────────────

CREATE TABLE password_reset_tokens (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      VARCHAR(128) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ  NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── airlines ────────────────────────────────────────────────────────────────

CREATE TABLE airlines (
    code      VARCHAR(20)  PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    -- No `currency` column: the collected currency comes from the price text in
    -- scraping, and the target is always in Real. Per-airline registration only
    -- produced a wrong guess (016).
    active    BOOLEAN      NOT NULL DEFAULT true,
    has_cash  BOOLEAN      NOT NULL DEFAULT true,
    has_pts   BOOLEAN      NOT NULL DEFAULT false,
    has_hyb   BOOLEAN      NOT NULL DEFAULT false,
    -- Can it search round-trip (one session, two legs, pair total)? A round_trip
    -- routine only accepts an airline with this true, otherwise the pair job
    -- would come back with loose legs and no bundle.
    has_roundtrip BOOLEAN  NOT NULL DEFAULT false
);

-- ─── airports ────────────────────────────────────────────────────────────────

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
  currency        VARCHAR(10)  NOT NULL,
  updated_at      TIMESTAMPTZ  DEFAULT now(),
  CONSTRAINT airports_airline_airport_uk UNIQUE (airline_code, airport_code)
);

-- ─── routines ────────────────────────────────────────────────────────────────

CREATE TABLE routines (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            VARCHAR(100) NOT NULL,
    origin          CHAR(3)      NOT NULL,
    destination     CHAR(3)      NOT NULL,
    outbound_start  DATE         NOT NULL,
    outbound_end    DATE         NOT NULL,
    -- Round-trip as ONE intent. An RT routine collects by PAIR of dates
    -- (scraping_jobs.return_date), never by loose leg: a one-way fare cannot
    -- price an RT without losing the bundle discount.
    trip_type       VARCHAR(20)  NOT NULL DEFAULT 'one_way' CHECK (trip_type IN ('one_way', 'round_trip')),
    inbound_start   DATE,
    inbound_end     DATE,
    passengers      SMALLINT     NOT NULL DEFAULT 1,
    currency        VARCHAR(3)   NULL,
    target_cash     NUMERIC(10,2),
    target_pts      INTEGER,
    target_hyb_pts  INTEGER,
    target_hyb_cash NUMERIC(10,2),
    margin          NUMERIC(4,3) NOT NULL DEFAULT 0.1,
    priority        VARCHAR(10)  NOT NULL DEFAULT 'cash' CHECK (priority IN ('cash', 'pts', 'hyb')),
    notification_modes     TEXT[]       NOT NULL,
    notification_frequency VARCHAR(10)  NOT NULL CHECK (notification_frequency IN ('hourly', 'daily', 'monthly')),
    scheduled_time         TIME         DEFAULT '20:00',
    cc_emails              JSONB        NOT NULL DEFAULT '[]',
    is_active              BOOLEAN      NOT NULL DEFAULT true,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT notification_modes_valid CHECK (notification_modes <@ ARRAY['target', 'scheduled']),
    CONSTRAINT notification_modes_not_empty CHECK (array_length(notification_modes, 1) >= 1),
    CONSTRAINT at_least_one_target_if_target_mode CHECK (
        NOT ('target' = ANY(notification_modes))
        OR (target_cash IS NOT NULL OR target_pts IS NOT NULL OR
            target_hyb_pts IS NOT NULL OR target_hyb_cash IS NOT NULL)
    ),
    -- Return window is required on round_trip and forbidden on one_way.
    CONSTRAINT routines_inbound_window_check CHECK (
        (trip_type = 'one_way'    AND inbound_start IS NULL     AND inbound_end IS NULL)
     OR (trip_type = 'round_trip' AND inbound_start IS NOT NULL AND inbound_end IS NOT NULL)
    ),
    CONSTRAINT routines_inbound_range_check CHECK (
        inbound_start IS NULL OR inbound_end >= inbound_start
    ),
    CONSTRAINT routines_inbound_after_outbound_check CHECK (
        inbound_start IS NULL OR inbound_start >= outbound_start
    )
);

-- ─── routine_airlines ─────────────────────────────────────────────────────────

CREATE TABLE routine_airlines (
    routine_id UUID        NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline    VARCHAR(20) NOT NULL REFERENCES airlines(code),
    PRIMARY KEY (routine_id, airline)
);

-- ─── routine_pending_requests ─────────────────────────────────────────────────

CREATE TABLE routine_pending_requests (
    routine_id   UUID        NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline      VARCHAR(20) NOT NULL REFERENCES airlines(code),
    request_id   UUID        NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (routine_id, airline)
);

-- ─── flight_offers ───────────────────────────────────────────────────────────

CREATE TABLE flight_offers (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id            UUID         NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline               VARCHAR(20)  NOT NULL REFERENCES airlines(code),
    flight_number         VARCHAR(10)  NOT NULL,
    date                  DATE         NOT NULL,
    is_return             BOOLEAN      NOT NULL DEFAULT false,
    origin_iata           CHAR(3)      NOT NULL,
    origin_timestamp      TIMESTAMPTZ  NOT NULL,
    destination_iata      CHAR(3)      NOT NULL,
    destination_timestamp TIMESTAMPTZ  NOT NULL,
    duration_min          INTEGER      NOT NULL,
    stops                 SMALLINT     NOT NULL DEFAULT 0,
    currency              VARCHAR(3)   NOT NULL,
    fare_cash             NUMERIC(10,2),
    fare_pts              INTEGER,
    fare_hyb_pts          INTEGER,
    fare_hyb_cash         NUMERIC(10,2),
    within_target         BOOLEAN      NOT NULL DEFAULT false,
    scraped_at            TIMESTAMPTZ  NOT NULL,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── best_fares ──────────────────────────────────────────────────────────────

CREATE TABLE best_fares (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id      UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline         VARCHAR(20)   NOT NULL REFERENCES airlines(code),
    analysis_id     UUID,
    date            DATE          NOT NULL,
    is_return       BOOLEAN       NOT NULL DEFAULT false,
    fare_type       VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb')),
    amount          NUMERIC(12,2) NOT NULL,
    flight_offer_id UUID          NOT NULL REFERENCES flight_offers(id) ON DELETE CASCADE,
    -- No DEFAULT: stamping Real on what is not Real is how the wrong currency
    -- got in silently (015).
    currency        VARCHAR(3)    NOT NULL,
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT best_fares_unique UNIQUE (routine_id, airline, date, is_return, fare_type)
);

-- ─── notification_log ────────────────────────────────────────────────────────

CREATE TABLE notification_log (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id      UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    airline         VARCHAR(20)   REFERENCES airlines(code),
    type            VARCHAR(20)   NOT NULL CHECK (type      IN ('alert', 'scheduled')),
    fare_type       VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb')),
    outbound_amount NUMERIC(12,2),
    return_amount   NUMERIC(12,2),
    email_to        VARCHAR(255)  NOT NULL,
    email_cc        TEXT,
    sent_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ─── target_alert_state ──────────────────────────────────────────────────────
-- Watermark per cell (routine × date × fare type) for the 'target' alert.
-- Source of truth for the anti-repeat rule: the alert only fires again when the
-- best price of ONE date drops below what was already notified for that date.
-- Not a log (that is notification_log) — this is the live "what we already sent".
CREATE TABLE target_alert_state (
    routine_id       UUID          NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    flight_date      DATE          NOT NULL,
    fare_type        VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb')),
    notified_amount  NUMERIC(12,2) NOT NULL,
    -- ORIGINAL composition of the alerted price: [{direction, currency, amount}...].
    -- It is what makes "the price dropped" mean price and not exchange rate — an
    -- identical composition never alerts, however much the Real conversion moved (015).
    notified_breakdown JSONB,
    notified_airline VARCHAR(20),
    notified_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (routine_id, flight_date, fare_type)
);

-- ─── unsubscribe_tokens ──────────────────────────────────────────────────────

CREATE TABLE unsubscribe_tokens (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    token       VARCHAR(128) UNIQUE NOT NULL,
    routine_id  UUID         NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    email       VARCHAR(255) NOT NULL,
    is_primary  BOOLEAN      NOT NULL DEFAULT false,
    expires_at  TIMESTAMPTZ  NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ─── indexes ─────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_airports_airline_code ON airports(airline_code);
CREATE INDEX IF NOT EXISTS idx_airports_airport_code ON airports(airport_code);
CREATE INDEX IF NOT EXISTS idx_airports_city        ON airports(city);
CREATE INDEX idx_refresh_token               ON refresh_tokens(token);
CREATE INDEX idx_routines_user_id            ON routines(user_id);
CREATE INDEX idx_routines_is_active          ON routines(is_active);
CREATE INDEX idx_routines_trip_type          ON routines(trip_type);
CREATE INDEX idx_routine_airlines_routine_id ON routine_airlines(routine_id);
CREATE INDEX idx_routine_airlines_airline    ON routine_airlines(airline);
CREATE INDEX idx_routine_pending_routine_id  ON routine_pending_requests(routine_id);
CREATE INDEX idx_flight_offers_routine_id    ON flight_offers(routine_id);
CREATE INDEX idx_flight_offers_date          ON flight_offers(date);
CREATE INDEX idx_flight_offers_scraped_at    ON flight_offers(scraped_at);
CREATE INDEX idx_best_fares_routine_id       ON best_fares(routine_id);
CREATE INDEX idx_best_fares_airline          ON best_fares(routine_id, airline);
CREATE INDEX idx_notif_log_routine_id        ON notification_log(routine_id);
CREATE INDEX idx_notif_log_sent_at           ON notification_log(sent_at);
CREATE INDEX idx_notif_log_lookup            ON notification_log(routine_id, fare_type, type, sent_at DESC);
CREATE INDEX idx_notif_log_airline_lookup    ON notification_log(routine_id, fare_type, airline, sent_at DESC);
CREATE INDEX idx_target_alert_state_flight_date ON target_alert_state(flight_date);
CREATE INDEX idx_pw_reset_token              ON password_reset_tokens(token);
CREATE INDEX idx_unsubscribe_token           ON unsubscribe_tokens(token);

-- ─── scraping_jobs ───────────────────────────────────────────────────────────

CREATE TABLE scraping_jobs (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  airline             VARCHAR(20)   NOT NULL REFERENCES airlines(code),
  origin              VARCHAR(10)   NOT NULL,
  destination         VARCHAR(10)   NOT NULL,
  flight_date         DATE          NOT NULL,

  status              VARCHAR(20)   NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'running', 'success', 'failed', 'dead', 'cancelled')),
  priority            INT           NOT NULL DEFAULT 0,

  retry_count         INT           NOT NULL DEFAULT 0,
  max_retries         INT           NOT NULL DEFAULT 3,
  next_run_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  last_success_at     TIMESTAMPTZ,
  last_failure_at     TIMESTAMPTZ,
  last_error          TEXT,

  running_since       TIMESTAMPTZ,
  running_timeout_min INT           NOT NULL DEFAULT 20,
  -- Set by job.started telemetry (the real start of the scrape). NULL = queued.
  started_at          TIMESTAMPTZ,
  -- Last worker.heartbeat/snapshot that listed this job (lease). Stops advancing
  -- when the worker disappears → the job is reclaimed.
  last_heartbeat_at   TIMESTAMPTZ,

  request_id          UUID,

  -- Collection by PAIR (round-trip): NULL = one-way search; filled = round-trip
  -- search with both dates fixed, to capture the bundle discount.
  return_date         DATE,

  -- Lifecycle, independent of execution status. Set when the route loses its
  -- active routine; NULL = active. Decides whether the job enters dispatch.
  orphaned_at         TIMESTAMPTZ,

  -- Cancellation request recorded; the worker aborts through AbortSignal.
  cancel_requested_at TIMESTAMPTZ,

  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- NULLS NOT DISTINCT: without it every one-way job (return_date NULL) would
  -- become a new row on each upsert, because NULL != NULL.
  CONSTRAINT scraping_jobs_route_key
    UNIQUE NULLS NOT DISTINCT (airline, origin, destination, flight_date, return_date),
  CONSTRAINT scraping_jobs_return_after_outbound_check
    CHECK (return_date IS NULL OR return_date >= flight_date)
);

CREATE INDEX idx_scraping_jobs_status_next_run ON scraping_jobs(status, next_run_at);
CREATE INDEX idx_scraping_jobs_airline_status  ON scraping_jobs(airline, status);
CREATE INDEX idx_scraping_jobs_flight_date     ON scraping_jobs(flight_date);
CREATE INDEX idx_scraping_jobs_request_id      ON scraping_jobs(request_id) WHERE request_id IS NOT NULL;
CREATE INDEX idx_scraping_jobs_return_date     ON scraping_jobs(return_date) WHERE return_date IS NOT NULL;

-- ─── flight_fares ─────────────────────────────────────────────────────────────

CREATE TABLE flight_fares (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  scraping_job_id  UUID          NOT NULL REFERENCES scraping_jobs(id) ON DELETE CASCADE,
  request_id       UUID,

  flight_number    VARCHAR(20),
  flight_date      DATE          NOT NULL,
  is_return        BOOLEAN       NOT NULL DEFAULT FALSE,
  origin           VARCHAR(10)   NOT NULL,
  destination      VARCHAR(10)   NOT NULL,
  airline          VARCHAR(20)   NOT NULL REFERENCES airlines(code),

  departure_time   TIME,
  arrival_time     TIME,
  duration_min     INT,
  stops            INT,
  -- Currency read from the price TEXT in scraping. Required: a fare without one
  -- would be compared against a target in another unit and nothing would complain (015).
  currency         VARCHAR(3)   NOT NULL,

  fare_cash        NUMERIC(10,2),
  fare_pts         NUMERIC(10,0),
  fare_hyb_pts     NUMERIC(10,0),
  fare_hyb_cash    NUMERIC(10,2),

  -- Value in Real FROZEN at collection time (017). Converting on read made the
  -- 30-day baseline move with the day rate — a falling pound looked like "the
  -- flight got cheaper" — and hit the FX API on every history open. With the rate
  -- stored, the pair total fits in SQL even when the legs come from different
  -- markets (BA out of LHR: outbound GBP, inbound BRL).
  fare_cash_brl     NUMERIC(12,2),
  fare_hyb_cash_brl NUMERIC(12,2),
  -- How many BRL one unit of `currency` was worth at collection; 1 if already Real.
  fx_rate           NUMERIC(18,8),
  -- Date of the QUOTE (the ECB publishes on business days), not of the collection.
  fx_rate_date      DATE,

  -- Pair the fare came from. NULL = collected in a loose one-way search, and
  -- therefore NOT usable to price a round-trip.
  return_date      DATE,

  -- Returns are priced in the context of the chosen OUTBOUND (a 1-to-N relation):
  -- on return rows, the outbound flight number that produced that price.
  paired_outbound_flight VARCHAR(20),

  -- Outbound only: the returns exist, but a known limitation hides them (on points
  -- Azul requires a TudoAzul login). Return undefined — the pair is shown without
  -- a total and does not alert. A return that vanished for no reason does NOT get
  -- this mark: that is still corrupted data.
  inbound_unavailable BOOLEAN NOT NULL DEFAULT FALSE,

  -- Pair total, written on both legs of the same RT search.
  bundle_cash      NUMERIC(10,2),
  bundle_pts       NUMERIC(10,0),
  bundle_hyb_pts   NUMERIC(10,0),
  bundle_hyb_cash  NUMERIC(10,2),

  scraped_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_flight_fares_route
  ON flight_fares(airline, origin, destination, flight_date, scraped_at DESC);
CREATE INDEX idx_flight_fares_scraped_at
  ON flight_fares(scraped_at);
CREATE INDEX idx_flight_fares_job
  ON flight_fares(scraping_job_id);
CREATE INDEX idx_flight_fares_request_id
  ON flight_fares(request_id) WHERE request_id IS NOT NULL;

-- Prevents inserting the same flight twice within one RUN (request_id).
-- The discriminator is request_id, not scraping_job_id: with scraping_jobs per
-- route the job is permanent, so scraping_job_id here would freeze the snapshot
-- at the first collection. Snapshots from different runs (price history) are
-- preserved — each run has its own request_id.
CREATE INDEX idx_flight_fares_paired_outbound
  ON flight_fares(request_id, paired_outbound_flight)
  WHERE paired_outbound_flight IS NOT NULL;

CREATE INDEX idx_flight_fares_pair
  ON flight_fares(airline, origin, destination, flight_date, return_date)
  WHERE return_date IS NOT NULL;

-- paired_outbound_flight is part of the key because the SAME return appears in the
-- list of several outbounds, potentially at a different price in each. Without it
-- ON CONFLICT DO NOTHING would keep only the first combination.
CREATE UNIQUE INDEX idx_flight_fares_no_dup
  ON flight_fares(request_id, flight_date, is_return, flight_number, paired_outbound_flight)
  NULLS NOT DISTINCT
  WHERE flight_number IS NOT NULL AND request_id IS NOT NULL;

-- ─── flight_fares_daily ───────────────────────────────────────────────────────

CREATE TABLE flight_fares_daily (
  airline       VARCHAR(20)   NOT NULL REFERENCES airlines(code),
  origin        VARCHAR(10)   NOT NULL,
  destination   VARCHAR(10)   NOT NULL,
  flight_date   DATE          NOT NULL,
  bucket_date   DATE          NOT NULL,
  fare_type     VARCHAR(10)   NOT NULL CHECK (fare_type IN ('cash', 'pts', 'hyb_pts', 'hyb_cash')),

  price_min     NUMERIC(10,2),
  price_max     NUMERIC(10,2),
  price_avg     NUMERIC(10,2),
  sample_count  INT           NOT NULL DEFAULT 0,

  PRIMARY KEY (airline, origin, destination, flight_date, bucket_date, fare_type)
);

-- ─── fare_itineraries ─────────────────────────────────────────────────────────
-- Curated price history. `flight_fares` is the raw collection and is purged at
-- 30 days; this pair of tables is what answers "how did this fare behave over
-- six months" (018).
--
-- The tracked unit is the ITINERARY, not the flight. Measured on collected data:
-- BA247 appears on 3 departure dates between R$690 and R$8,036, so a series
-- keyed by flight number blends November with December; and the same flight on
-- the same day costs 42% less inside a pair (BA246 2026-11-26: R$3,563 loose,
-- R$2,055 within a round-trip), so the trip context is identity, not attribute.
--
-- No user_id anywhere: the identity is the offer, so routines of different users
-- on the same route feed and read the same series — the same reuse as the
-- scraping_jobs dedup by route.

CREATE TABLE fare_itineraries (
  id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  airline                VARCHAR(20)  NOT NULL REFERENCES airlines(code),
  trip_type              VARCHAR(10)  NOT NULL CHECK (trip_type IN ('one_way', 'round_trip')),

  origin                 VARCHAR(10)  NOT NULL,
  destination            VARCHAR(10)  NOT NULL,

  outbound_flight_number VARCHAR(20)  NOT NULL,
  outbound_date          DATE         NOT NULL,
  -- Filled only on round_trip: it is the pair that is priced and displayed, and
  -- the return has no series of its own (the same return costs a different price
  -- under each outbound).
  inbound_flight_number  VARCHAR(20),
  inbound_date           DATE,

  -- Currency last seen for this itinerary; the label of the current price. Each
  -- history segment carries its own, so a switch does not rewrite the past.
  currency               VARCHAR(3)   NOT NULL,

  first_seen_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  -- Last collection that found this itinerary on sale. Drives the monthly
  -- cleanup: an itinerary off the radar takes its history with it.
  last_seen_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),

  -- A one-way with a return leg, or a pair without one, is a broken write, not a
  -- variation to tolerate: the reading side would price a trip that was never sold.
  CONSTRAINT fare_itineraries_trip_shape CHECK (
    (trip_type = 'one_way'    AND inbound_flight_number IS NULL     AND inbound_date IS NULL) OR
    (trip_type = 'round_trip' AND inbound_flight_number IS NOT NULL AND inbound_date IS NOT NULL)
  )
);

-- The identity itself. NULLS NOT DISTINCT so the one-way (both inbound columns
-- NULL) collides with itself instead of inserting a new row per collection —
-- the same technique as idx_flight_fares_no_dup.
CREATE UNIQUE INDEX idx_fare_itineraries_identity
  ON fare_itineraries(airline, trip_type, origin, destination,
                      outbound_flight_number, outbound_date,
                      inbound_flight_number, inbound_date)
  NULLS NOT DISTINCT;

-- Route + outbound window: how the card reads the history of a one-way routine.
CREATE INDEX idx_fare_itineraries_route
  ON fare_itineraries(airline, origin, destination, outbound_date);

-- Pair routine: the return window enters the filter, so it enters the index.
CREATE INDEX idx_fare_itineraries_pair
  ON fare_itineraries(airline, origin, destination, outbound_date, inbound_date)
  WHERE trip_type = 'round_trip';

CREATE INDEX idx_fare_itineraries_last_seen
  ON fare_itineraries(last_seen_at);

-- ─── fare_price_history ───────────────────────────────────────────────────────
-- One row per price CHANGE, not per collection: 71% of the rows collected in the
-- sample repeated the price of the previous run. The segment carries the window
-- it held, which also keeps a real plateau apart from a gap in collection — a
-- distinction a chart of snapshots cannot make.

CREATE TABLE fare_price_history (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  itinerary_id        UUID          NOT NULL REFERENCES fare_itineraries(id) ON DELETE CASCADE,

  -- Currency of THIS segment. Inheriting it from the itinerary is what made
  -- outbound and return show the same label on collections in different markets.
  currency            VARCHAR(3)    NOT NULL,

  amount_cash         NUMERIC(10,2),
  amount_pts          NUMERIC(10,0),
  amount_hyb_pts      NUMERIC(10,0),
  amount_hyb_cash     NUMERIC(10,2),

  -- Value in Real frozen at collection, same contract as flight_fares (017): it
  -- is what lets a six-month chart compare points without the exchange rate of
  -- the day moving the past. NULL when there was no trustworthy quote.
  amount_cash_brl     NUMERIC(12,2),
  amount_hyb_cash_brl NUMERIC(12,2),
  fx_rate             NUMERIC(18,8),
  fx_rate_date        DATE,

  -- The window this price held. `observed_from` is the collection that first saw
  -- it; `last_seen_at` the last one that confirmed it. A price that returns after
  -- a change opens a NEW segment — 700 → 900 → 700 is three, not two.
  observed_from       TIMESTAMPTZ   NOT NULL,
  last_seen_at        TIMESTAMPTZ   NOT NULL,
  -- Collections that confirmed the segment. Separates a plateau measured 40
  -- times from a price seen once and never again.
  observation_count   INT           NOT NULL DEFAULT 1,

  CONSTRAINT fare_price_history_window CHECK (last_seen_at >= observed_from)
);

-- Reading the chart, and finding the current segment to extend on write.
CREATE UNIQUE INDEX idx_fare_price_history_segment
  ON fare_price_history(itinerary_id, observed_from);

CREATE INDEX idx_fare_price_history_recent
  ON fare_price_history(itinerary_id, last_seen_at DESC);

-- ─── analysis_runs ────────────────────────────────────────────────────────────
-- History of analysis runs (one row per scraping_job execution).
-- Route fields are denormalised to survive the scraping_jobs cleanup.

CREATE TABLE analysis_runs (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  scraping_job_id UUID         REFERENCES scraping_jobs(id) ON DELETE SET NULL,
  request_id      UUID         NOT NULL,
  airline         VARCHAR(20)  NOT NULL,
  origin          VARCHAR(10)  NOT NULL,
  destination     VARCHAR(10)  NOT NULL,
  flight_date     DATE         NOT NULL,
  -- Return leg when the run was a round-trip search.
  return_date     DATE,
  status          VARCHAR(20)  NOT NULL DEFAULT 'running'
                  CHECK (status IN ('running', 'success', 'failed', 'dead', 'blocked', 'cancelled')),
  error_message   TEXT,
  fares_found     INT,
  -- Worker that took the run (realtime telemetry).
  worker_id       VARCHAR(40),
  -- Who asked for the cancellation; NULL when it was not cancelled.
  cancelled_by    UUID         REFERENCES users(id) ON DELETE SET NULL,
  started_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  finished_at     TIMESTAMPTZ
);

CREATE INDEX idx_analysis_runs_match
  ON analysis_runs(airline, origin, destination, flight_date, started_at DESC);
CREATE INDEX idx_analysis_runs_request
  ON analysis_runs(request_id);

-- ─── analysis_run_events ──────────────────────────────────────────────────────
-- Timeline of events per request_id, fed by the worker's telemetry.
-- It is what the FRONT consumes to follow the analysis in real time.

CREATE TABLE analysis_run_events (
  id         BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id UUID         NOT NULL,
  seq        INTEGER      NOT NULL,
  ts         TIMESTAMPTZ  NOT NULL DEFAULT now(),
  type       VARCHAR(30)  NOT NULL CHECK (type IN ('queued', 'started', 'progress', 'log', 'finished')),
  level      VARCHAR(10)  CHECK (level IN ('info', 'warn', 'error')),
  payload    JSONB        NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX idx_run_events_request_seq ON analysis_run_events(request_id, seq);
CREATE INDEX        idx_run_events_ts          ON analysis_run_events(ts);

-- ─── updated_at trigger ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_routines_updated_at
    BEFORE UPDATE ON routines
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_best_fares_updated_at
    BEFORE UPDATE ON best_fares
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_scraping_jobs_updated_at
    BEFORE UPDATE ON scraping_jobs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
