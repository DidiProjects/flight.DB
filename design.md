# Design — flight.DB (schema)

Referência das tabelas. Fonte de verdade: `init-scripts/01-schema.sql`. Timezone `America/Sao_Paulo`, extensão `pgcrypto`.

## Auth

### `users`
`id` UUID PK · `email` UNIQUE · `name` · `password_hash` · `role` (`admin`|`user`) · `status` (`pending`|`active`|`suspended`) · `must_change_password` BOOL · `provisional_expires_at` · `created_at`/`updated_at`.
Admin inserido no seed (`02-seed.sh`). `must_change_password=true` bloqueia acesso até troca.

### `refresh_tokens` / `password_reset_tokens`
`id` · `user_id` (FK→users, CASCADE) · `token` UNIQUE · `expires_at` · `used_at` · `created_at`. `refresh_tokens` tem `revoked_at`.

### `unsubscribe_tokens`
`token` UNIQUE · `routine_id` (FK) · `email` · `is_primary` BOOL · `expires_at` · `used_at`. `is_primary=true` → desativa a rotina; `false` → marca o CC como `subscribed:false` em `routines.cc_emails`.

## Catálogo

### `airlines`
`code` PK (ex. `azul`) · `name` · `currency` (default `BRL`) · `active` · `has_cash`/`has_pts`/`has_hyb`. Seed: `azul`.

### `airports`
`airline_code` (FK) + `airport_code` UNIQUE · `name` · `timezone` · `country_code`/`country_name` · `city` · `region` · `currency` NOT NULL. A moeda da rotina é resolvida pela moeda do aeroporto de origem.

## Rotinas

### `routines`
One-way apenas (origem→destino, janela de ida). Ida+volta vira 2 rotinas no front.
`id` · `user_id` (FK) · `name` · `origin`/`destination` CHAR(3) · `outbound_start`/`outbound_end` · `passengers` · `currency` · alvos `target_cash`/`target_pts`/`target_hyb_pts`/`target_hyb_cash` · `margin` (default 0.1) · `priority` (`cash`|`pts`|`hyb`) · `notification_modes` TEXT[] (subconjunto de `{target, scheduled}`, ≥1) · `notification_frequency` (`hourly`|`daily`|`monthly`) · `scheduled_time` (default `20:00`) · `cc_emails` JSONB `[{email, subscribed}]` · `is_active`.
Constraint: se `target` está nos modos, pelo menos um `target_*` deve estar preenchido.

### `routine_airlines`
PK (`routine_id`, `airline`) — companhias por rotina.

### `routine_pending_requests`
PK (`routine_id`, `airline`) · `request_id` · `requested_at` — controle de scrape em andamento por rotina/cia.

## Histórico de preços (PROP-001)

### `scraping_jobs`
Estado do scheduler. UNIQUE (`airline`, `origin`, `destination`, `flight_date`).
`status` (`pending`|`running`|`success`|`failed`|`dead`) · `priority` · `retry_count`/`max_retries` · `next_run_at` · `last_success_at`/`last_failure_at`/`last_error` · `running_since`/`running_timeout_min` · `request_id`.

### `flight_fares`
Tarifas brutas coletadas, 1 por voo por job. `scraping_job_id` (FK CASCADE) · `flight_number`/`flight_date`/`is_return` · `origin`/`destination`/`airline` · `departure_time`/`arrival_time`/`duration_min`/`stops` · `currency` · `fare_cash`/`fare_pts`/`fare_hyb_pts`/`fare_hyb_cash` · `scraped_at`. Índice único impede duplicar o mesmo voo dentro de um job; snapshots em jobs diferentes são permitidos (histórico).

### `flight_fares_daily`
Agregado diário. PK (`airline`, `origin`, `destination`, `flight_date`, `bucket_date`, `fare_type`) com `fare_type` ∈ `cash`/`pts`/`hyb_pts`/`hyb_cash` · `price_min`/`price_max`/`price_avg`/`sample_count`.

### `analysis_runs`
1 linha por execução (dispatch→callback). `scraping_job_id` (FK SET NULL) · `request_id` · rota denormalizada (`airline`/`origin`/`destination`/`flight_date`) · `status` (`running`|`success`|`failed`|`dead`|`blocked`) · `error_message` · `fares_found` · `started_at`/`finished_at`. Denormalizado para sobreviver à limpeza de `scraping_jobs`.

## Notificações e ofertas (legado de avaliação por rotina)

### `flight_offers`
Ofertas associadas a uma rotina. `routine_id` (FK) · dados do voo · `currency` · `fare_*` · `within_target` · `scraped_at`.

### `best_fares`
Melhor tarifa acumulada. UNIQUE (`routine_id`, `airline`, `date`, `is_return`, `fare_type` ∈ `cash`/`pts`/`hyb`) · `amount` · `flight_offer_id` (FK) · `currency` · `analysis_id`.

### `notification_log`
Histórico de emails (anti-spam). `routine_id` · `airline` · `type` (`alert`|`scheduled`) · `fare_type` (`cash`|`pts`|`hyb`) · `outbound_amount`/`return_amount` · `email_to`/`email_cc` · `sent_at`.

## Triggers

`update_updated_at()` atualiza `updated_at` em `users`, `routines`, `best_fares`, `scraping_jobs`.
