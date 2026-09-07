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
`code` PK (ex. `azul`) · `name` · `currency` (opcional, sem default) · `active` · `has_cash`/`has_pts`/`has_hyb`. Seed: `azul` com `currency='BRL'`.
`batch_size` (migration 020): quantos itens cabem numa sessão de navegador desta companhia. `1` = uma sessão por item, o comportamento anterior ao lote. Sobe por companhia, com medição — o custo por item é estrutural e diferente em cada uma.
`currency` é opcional por companhia: quando preenchido (ex. Latam/Azul, sempre BRL) tem **prioridade máxima** na resolução da moeda da rotina; quando `NULL`, a moeda é resolvida dinamicamente.

### `airports`
`airline_code` (FK) + `airport_code` UNIQUE · `name` · `timezone` · `country_code`/`country_name` · `city` · `region` · `currency` NOT NULL. A moeda da rotina é resolvida, em ordem: (1) `airlines.currency`, se definida; (2) `flight_fares.currency` de um job já coletado para o trajeto/companhia; (3) moeda do aeroporto de ORIGEM; (4) indefinida.

### `markets` / `market_countries` / `airline_markets` (migration 019)

Mapa de mercado: quais companhias fazem sentido para um trajeto, por **direito de
tráfego**. Companhia estrangeira não opera doméstico em outro país — cabotagem é
restrição legal, e a exceção é o mercado único europeu (é por isso que a Ryanair,
irlandesa, pode voar MAD-BCN).

- **`markets`** — `code` PK · `name`. Um mercado é um conjunto de países com
  cabotagem livre entre si; país isolado é mercado de um país só, sem caso
  especial no modelo nem na consulta. Seed: `br`, `cl`, `pe`, `co`, `ec`, `gb`,
  `eee`.
- **`market_countries`** — PK (`market_code` FK, `country_code`). `country_code`
  sempre minúsculo, com CHECK: a caixa de `airports.country_code` da GOL está em
  MAIÚSCULA e o resto em minúscula, então toda comparação precisa de `lower()`
  dos dois lados. `eee` = os 27 da UE mais Islândia, Liechtenstein e Noruega — o
  Reino Unido **não** está lá (Brexit), e é por isso que a BA não opera mais
  doméstico na Itália.
- **`airline_markets`** — PK (`airline_code` FK, `market_code` FK). N-para-N: a
  Ryanair pertence ao `eee` pelo AOC irlandês E ao `gb` pelo AOC britânico
  separado que mantém desde o Brexit; a LATAM são cinco companhias nacionais num
  grupo.

**Fail-closed:** companhia sem linha em `airline_markets` nunca é candidata para
trajeto nenhum. Em troca, companhia **ativa** sem mercado é erro de configuração.

Não é inferível do dado que existe — é fato jurídico, e entra escrito à mão. Duas
alternativas foram testadas e reprovadas: derivar país-sede pela contagem de
aeroportos faz BA e LATAM parecerem americanas (a cauda de destinos bilhetáveis é
dominada pelos EUA), e ordenar por tamanho de rede acerta 2 de 4 rotas conhecidas.

**O seed vincula só companhia que existe naquele banco.** `airlines` é dado
operacional: o único cadastro automático do projeto é o da `azul`
(`init-scripts/02-seed.sh`), e as demais entram por ambiente. A lista cravada
derrubava a migration inteira num banco que não tivesse todas — medido em
produção em 2026-08-27, que não tem a `gol`. Quem cadastra a companhia cadastra o
mercado dela junto, como o `02-seed.sh` já faz com a `azul`.

**O que o mapa não responde:** ele diz *"pode voar"*, não *"vende"*. A Ryanair é
candidata em MAD-BCN e não vende esse par. Quem responde isso é a
`route_airline_coverage` com a escada de rebaixamento — desenhada em
`flight-monitoring.IA/design/selecao-automatica-de-companhias.md`, ainda não
implementada.

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
`batch_id` (migration 020, FK SET NULL): lote a que o item pertence. Enquanto ele apontar para lote **vivo** (`dispatched`/`running`/`closing`), o item não pode ser reclamado pelo dispatcher — é o predicado que garante que operação em lote é tratada em lote, e vale tanto em `claimNextJob` quanto em `claimNextJobForRoutine` (o caminho do disparo manual).

### `scraping_batches` (migration 020)
Itens da mesma rota+companhia executados numa **sessão de navegador só**. A chave é a rota, e não a rotina, porque `scraping_jobs` deduplica por rota (migration 002): o job é propriedade do trajeto.

`airline`/`origin`/`destination` · `status` (`dispatched`|`running`|`closing`|`completed`|`aborted`|`superseded`|`expired`) · `item_count`/`received_count` · `close_reason` · `superseded_by` · `attempt` · `created_at`/`closed_at`.

Três coisas que o desenho depende:
- **`item_count` decrementa** quando um item é cancelado no meio da corrida. Sem isso `received_count` nunca alcança e o lote só fecharia pelo backstop de tempo.
- **Índice único parcial** `uq_scraping_batches_rota_viva`: no máximo um lote vivo por rota+companhia, garantido pelo banco. Dois disparos manuais simultâneos na mesma rota são um caso real, e dois lotes concorrentes produzem duas sessões do mesmo IP no mesmo site — medido na BA em 2026-08-24, as duas voltaram `BLOCKED` juntas.
- **`attempt`**: o lote de retentativa é formado com os itens que falharam no lote anterior, com backoff **de lote**. Item que falha não volta à fila sozinho.

### `flight_fares`
Tarifas brutas coletadas, 1 por voo por execução. `scraping_job_id` (FK CASCADE) · `request_id` (execução que coletou) · `flight_number`/`flight_date`/`is_return` · `origin`/`destination`/`airline` · `departure_time`/`arrival_time`/`duration_min`/`stops` · `currency` · `fare_cash`/`fare_pts`/`fare_hyb_pts`/`fare_hyb_cash` · `fare_cash_brl`/`fare_hyb_cash_brl`/`fx_rate`/`fx_rate_date` · `scraped_at`. **Valor em Real congelado na coleta (migration 017):** a conversão acontece uma vez, na ingestão da análise, e a taxa fica gravada na linha. Antes era feita na leitura — o que batia na API de câmbio a cada abertura de histórico e fazia a régua de 30 dias mudar com a cotação do dia. Também é o que permite somar as duas pernas de um par cujas pernas vêm de mercados diferentes (BA saindo de LHR: ida GBP, volta BRL); antes as queries de par exigiam `i.currency = o.currency` e descartavam esses pares inteiros. Linha sem cotação no momento entra com `fare_cash_brl` NULL e fica de fora das somas em Real, em vez de somar moedas. Índice único (`request_id`, `flight_date`, `is_return`, `flight_number`) impede duplicar o mesmo voo dentro de uma execução; snapshots de execuções diferentes são preservados (histórico). **Importante:** o discriminador é `request_id`, não `scraping_job_id` — com `scraping_jobs` por rota (migration 002) o job é permanente, então a chave de dedup precisa ser por execução para não congelar o snapshot na primeira coleta (migration 003). As leituras de "snapshot mais recente por data" também agrupam por `request_id`.

### `flight_fares_daily`
Agregado diário. PK (`airline`, `origin`, `destination`, `flight_date`, `bucket_date`, `fare_type`) com `fare_type` ∈ `cash`/`pts`/`hyb_pts`/`hyb_cash` · `price_min`/`price_max`/`price_avg`/`sample_count`. **Hoje é write-only:** o `aggregateToDailyBucket` do scheduler escreve todo dia e nenhuma query do flight.API lê. Não tem `currency` (mistura mercados na mesma média) nem `return_date` (par não existe nela) — foi o que motivou `fare_itineraries`/`fare_price_history` em 018.

### `fare_itineraries` / `fare_price_history`
Histórico de preços curado (migration 018), a fonte do gráfico de até 6 meses. `flight_fares` é a coleta bruta e é purgada aos 30 dias; estas duas sobrevivem.

A unidade rastreada é o **itinerário**, não o voo. Medido nos dados coletados: `BA247` aparece em 3 datas de partida entre R$ 690 e R$ 8.036 — série por código do voo misturaria novembro com dezembro. E o mesmo voo, no mesmo dia, custa 42% menos dentro de um par (`BA246` 2026-11-26: R$ 3.563 solto, R$ 2.055 em ida-e-volta) — o contexto da viagem é identidade, não atributo.

`fare_itineraries`: índice único (`airline`, `trip_type`, `origin`, `destination`, `outbound_flight_number`, `outbound_date`, `inbound_flight_number`, `inbound_date`) com `NULLS NOT DISTINCT`, para a ida simples (duas colunas de volta nulas) colidir consigo mesma. `CHECK` de forma garante que `round_trip` tem as duas pernas e `one_way` não tem nenhuma. `last_seen_at` é o parâmetro da limpeza mensal — itinerário fora do radar leva o histórico junto, via `ON DELETE CASCADE`. **Sem `user_id`:** a identidade é a oferta, então rotinas de usuários diferentes na mesma rota alimentam e leem a mesma série, igual ao dedup de `scraping_jobs` por rota.

`fare_price_history`: 1 linha por **mudança** de preço, não por coleta — 71% das linhas coletadas na amostra repetiam o preço da execução anterior. O segmento carrega a janela que valeu (`observed_from` → `last_seen_at`) e `observation_count`, o que separa platô real de buraco de coleta. Preço que volta depois de mudar abre segmento novo (700 → 900 → 700 são três). `amount_cash_brl`/`fx_rate`/`fx_rate_date` seguem o contrato de 017: Real congelado na coleta, para o gráfico de 6 meses não se mexer com a cotação do dia. **É essa coluna que a série lê** — o dashboard inteiro fala Real. Ler `amount_cash` (moeda coletada) deixava a linha do gráfico em GBP ao lado de estatísticas em BRL, as duas rotuladas com o mesmo símbolo.

### `analysis_runs`
1 linha por execução (dispatch→callback). `scraping_job_id` (FK SET NULL) · `request_id` · rota denormalizada (`airline`/`origin`/`destination`/`flight_date`) · `status` (`running`|`success`|`failed`|`dead`|`blocked`|`cancelled`) · `error_message` · `fares_found` · `batch_id` (020) · `started_at`/`finished_at`. Denormalizado para sobreviver à limpeza de `scraping_jobs`.

## Notificações e ofertas (legado de avaliação por rotina)

### `flight_offers`
Ofertas associadas a uma rotina. `routine_id` (FK) · dados do voo · `currency` · `fare_*` · `within_target` · `scraped_at`.

### `best_fares`
Melhor tarifa acumulada. UNIQUE (`routine_id`, `airline`, `date`, `is_return`, `fare_type` ∈ `cash`/`pts`/`hyb`) · `amount` · `flight_offer_id` (FK) · `currency` · `analysis_id`.

### `notification_log`
Histórico de emails (anti-spam). `routine_id` · `airline` · `type` (`alert`|`scheduled`) · `fare_type` (`cash`|`pts`|`hyb`) · `outbound_amount`/`return_amount` · `email_to`/`email_cc` · `sent_at`.

### `target_alert_state`
Watermark do alerta `target` por célula do grid. PK (`routine_id`, `flight_date`, `fare_type` ∈ `cash`/`pts`/`hyb`) · `notified_amount` (melhor preço já alertado para aquela data) · `notified_airline` · `notified_at`/`updated_at`. Fonte de verdade do anti-repetição: o alerta só re-dispara quando o melhor preço de uma data cai abaixo do `notified_amount` daquela data (upsert monotônico-descendente). Limpeza diária remove `flight_date < CURRENT_DATE`; `ON DELETE CASCADE` cobre rotina removida.

## Triggers

`update_updated_at()` atualiza `updated_at` em `users`, `routines`, `best_fares`, `scraping_jobs`.
