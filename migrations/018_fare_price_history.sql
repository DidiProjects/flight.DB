-- 018 — Curated price history: the tracked itinerary and its price changes.
--
-- `flight_fares` keeps the RAW collection and is purged at 30 days, so nothing
-- in the system can answer "how did this fare behave over six months". These two
-- tables answer it, and they are written from the same ingestion.
--
-- Why an ITINERARY and not a flight: measured on the collected data, airline +
-- flight number does not identify a fare. BA247 appears on 3 departure dates
-- between R$690 and R$8,036 — one series would blend November with December. And
-- the same flight on the same day costs 42% less inside a pair (BA246 2026-11-26:
-- R$3,563 loose, R$2,055 within a round-trip), so the trip context is part of the
-- identity too, not an attribute of it.
--
-- Why price CHANGES and not collections: 71% of the rows collected in the sample
-- repeated the price of the previous run. A segment carries the window it held
-- (`observed_from` → `last_seen_at`), which also keeps a real plateau apart from a
-- gap in collection — a distinction a chart of snapshots cannot make.

-- ─── fare_itineraries ────────────────────────────────────────────────────────

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

-- ─── fare_price_history ──────────────────────────────────────────────────────

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
