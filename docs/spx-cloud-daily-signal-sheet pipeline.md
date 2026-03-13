# NexusBot SPX Daily Signal Sheet Pipeline
## Production Technical Spec

## 1. Purpose

This document defines the production implementation for the SPX Daily Signal Sheet
pipeline in NexusBot.

The goal is to generate one authoritative daily playbook for the active US market
session, store it in Firestore, and expose it to the Flutter app in near real
time without coupling the pipeline to the existing SPX trading/scanner logic.

This replaces the earlier concept memo. It is intended for engineering
implementation, deployment, and operations.

## 2. Scope

This pipeline is responsible for:

- creating a premarket playbook snapshot for the current trading day
- resolving the opening algorithm decision at the cash open
- locking minute-14 reference levels after the first 14 completed 1-minute bars
- refreshing live decision context during the first 35 minutes of the session
- persisting a single Firestore document per market day
- generating scheduled screenshot artifacts from the playbook for daily review and sharing

This pipeline is not responsible for:

- placing trades
- selecting contracts for execution
- sending push notifications directly from the core request path
- replacing the existing `SpxBloc` intraday scanner

Push delivery, if needed, should be an optional downstream integration using the
existing Firebase push sender scaffolding in `functions/`.

## 3. Repo Alignment

This repo already contains relevant scaffolded pieces:

- backend scaffold: `micro-services/signal-sheet-service/`
- Firestore writer: `micro-services/signal-sheet-service/services/playbook_writer.py`
- Tradier client: `micro-services/signal-sheet-service/services/tradier_client.py`
- signal engine scaffold: `micro-services/signal-sheet-service/services/signal_engine.py`
- Flutter model: `lib/models/daily_playbook.dart`
- Flutter screen scaffold: `lib/screens/spx/spx_signal_sheet_screen.dart`

The production design below is intentionally aligned to those files, but it also
calls out the changes still required before the service is safe to ship.

There is currently no server-side screenshot renderer in this repo. Screenshot
generation defined below is therefore a new backend responsibility, not an
existing capability.

## 4. Authoritative Decisions

The following decisions are non-negotiable for production:

| Topic | Decision |
|---|---|
| Product instrument | `SPX` is the display and decision instrument |
| Market calendar | US equities/options trading calendar |
| Trading timezone | `America/New_York` |
| Firestore document id | `YYYY-MM-DD` for the market day in Eastern Time |
| Scheduler timezone | `America/New_York` for every job |
| Source of truth | Firestore `playbooks/{market_date}` |
| Core write model | Idempotent upsert by document id |
| Minute-14 behavior | `min14_high` and `min14_low` are immutable after lock |
| Post-lock extremes | Track separately as live/session fields if needed; do not mutate minute-14 |
| Tiebreaker | DPL is the final directional tiebreaker; neutral DPL means `WAIT` |
| Client date logic | Clients must use Eastern market date, not device-local date and not raw UTC date |
| Screenshot cadence | Generate 3 daily images: premarket, locked-open, final-early-session |

## 5. Production Corrections vs Earlier Draft

The earlier draft had several issues that must not carry into implementation:

- `SPX` and `SPY` were mixed interchangeably. Production must make the instrument
  explicit. If proxy mode is ever used, it must be stored explicitly in the
  document.
- UTC-equivalent cron schedules were hardcoded with `PST`/`EST`. That breaks
  during daylight saving time. All scheduler jobs must use named timezones.
- the premarket generation time overlapped with market open. Production must run
  the premarket snapshot before 09:30 ET.
- `/resolve` must use the official 09:30 ET opening bar, not the latest spot quote
- minute-14 was described as both "locked" and later mutable. Production treats
  minute-14 as immutable.
- the refresh job window in the draft did not match the cron expression
- the React dashboard examples are not relevant to this repo; the consumer in this
  repo is Flutter

## 6. High-Level Architecture

```text
Cloud Scheduler (ET)
    -> Cloud Run: signal-sheet-service
        -> Tradier market data
        -> Firestore playbooks/{market_date}
        -> Screenshot renderer
        -> GCS screenshot artifacts
    -> Flutter app stream / reads
    -> optional downstream push sender
```

### Service Boundary

`signal-sheet-service` is a standalone Cloud Run service. It does not modify the
existing SPX trading engine, scanner loop, or simulator logic inside the Flutter
app.

The screenshot renderer may live inside the same Cloud Run service for v1, but it
must be a separate endpoint and execution phase from the market-data write path.

### Deployment Shape

- runtime: Python 3.11
- platform: Cloud Run
- auth: authenticated invocations only
- storage: Firestore
- secrets: Secret Manager or Cloud Run bound secrets
- deploy script: `micro-services/signal-sheet-service/deploy_gcp.sh`

## 7. Trading Day Model

Every handler must derive the current market date using Eastern Time.

Rules:

- if today is a weekend or market holiday, return a successful `noop`
- if called before a required market phase, return a successful `noop`
- if required data is incomplete, return a successful `noop` and structured log
- only throw an error for genuine system failures: auth failure, Firestore failure,
  Tradier failure beyond retry budget, malformed data, or code exceptions

### Required helper behavior

The service must provide a shared market-session utility that determines:

- `market_date`
- whether today is a trading day
- whether the market is open
- whether enough 1-minute bars exist for the requested phase
- whether the job is running inside its intended time window

Do not scatter timezone logic across endpoints.

## 8. Scheduler Plan

All jobs use timezone `America/New_York`.

| Job | Cron | Target | Purpose |
|---|---|---|---|
| `signal-sheet-generate` | `20 9 * * 1-5` | `POST /generate` | Premarket snapshot before the cash open |
| `signal-sheet-render-premarket` | `21 9 * * 1-5` | `POST /render-snapshot` | Generate premarket screenshot after premarket write |
| `signal-sheet-resolve-open` | `30 9 * * 1-5` | `POST /resolve` | Opening algorithm decision |
| `signal-sheet-lock-minute14` | `44 9 * * 1-5` | `POST /lock-minute14` | Lock first 14 completed 1-minute bars |
| `signal-sheet-render-locked` | `45 9 * * 1-5` | `POST /render-snapshot` | Generate locked minute-14 screenshot |
| `signal-sheet-refresh-1` | `35,40,45,50,55 9 * * 1-5` | `POST /refresh` | Live refresh during opening window |
| `signal-sheet-refresh-2` | `0,5 10 * * 1-5` | `POST /refresh` | Continue refresh through 10:05 ET |
| `signal-sheet-render-final` | `6 10 * * 1-5` | `POST /render-snapshot` | Generate final early-session screenshot |

### Why this schedule

- `09:20 ET` gives a near-open premarket snapshot without racing the open
- `09:21 ET` creates the "before the open" screenshot from finalized premarket data
- `09:30 ET` resolves against the first official opening bar
- `09:44 ET` runs after the `09:43` bar has closed, which gives 14 completed bars
- refresh covers the period where the opening thesis is still developing
- `09:45 ET` creates the first fully actionable screenshot with minute-14 locked
- `10:06 ET` creates the final early-session screenshot after the `10:05 ET` refresh

## 9. Endpoint Contract

### Common requirements

All endpoints must:

- require authenticated invocation from Cloud Scheduler
- verify OIDC token audience against the Cloud Run URL
- verify issuer and allowed service account email
- be idempotent
- log structured fields for every invocation
- return JSON on every path

### Success response

```json
{
  "status": "ok",
  "date": "2026-03-13",
  "phase": "generate",
  "outcome": "updated"
}
```

`outcome` must be one of:

- `updated`
- `noop`

### Error response

```json
{
  "status": "error",
  "code": "tradier_unavailable",
  "message": "Failed to load options chain after retries."
}
```

### Endpoint semantics

#### `POST /generate`

Creates or replaces the premarket snapshot fields for `playbooks/{market_date}`.

Writes:

- meta fields
- prior close
- premarket bias
- GEX summary
- walls
- range estimate
- all 7 baseline signals
- initial `dpl_live`

Does not write:

- official open
- algorithm decision
- minute-14 lock

If the document already exists, this endpoint overwrites premarket-derived fields
and preserves later-phase fields unless explicitly regenerated by operator choice.

#### `POST /resolve`

Uses the official 09:30 ET opening bar, not the latest quote, to resolve the
opening decision.

Writes:

- `official_open`
- `algorithm_step`
- `recommendation`
- `signal_unity`
- `reason`
- `status = "open"`

If the playbook document does not exist yet, return `noop` and log
`missing_generate_phase`.

#### `POST /lock-minute14`

Locks the first 14 completed one-minute bars from 09:30 through 09:43 ET.

Writes:

- `min14_high`
- `min14_low`
- `otm_long_strike`
- `otm_short_strike`
- `status = "locked"`

If fewer than 14 completed bars exist, return `noop`.

#### `POST /refresh`

Refreshes live context during the opening window.

Writes:

- `dpl_live`
- `last_refreshed_at`
- optional live/session extremes
- optional updated `recommendation` and `reason` when a prior `WAIT` can be
  upgraded safely after the open window matures

This endpoint is not limited to DPL only. On gap days, `/refresh` is the place
where a prior `WAIT` can later convert into `GO_LONG` or `GO_SHORT`.

#### `POST /render-snapshot`

Generates a screenshot artifact for the requested phase using the persisted
Firestore playbook as the only source of truth.

Request body:

```json
{
  "phase": "premarket"
}
```

Allowed phases:

- `premarket`
- `locked`
- `final`

Rules:

- do not compute market data in the renderer
- read only from the stored playbook document
- if the document does not yet satisfy the phase requirements, return `ok/noop`
- rendering failure must not block the market-data endpoints
- repeated rendering for the same phase must overwrite the same object path or
  update the same phase metadata cleanly

## 10. Firestore Schema

Collection: `playbooks`

Document id: `market_date` in `America/New_York`, example `2026-03-13`

```typescript
interface DailyPlaybook {
  // Meta
  date: string                     // ET market date, YYYY-MM-DD
  symbol: "SPX"
  source_symbol?: "SPX" | "SPY"
  source_mode?: "direct" | "proxy"
  schema_version: number           // start at 2
  signal_engine_version: string
  generated_at: string             // ISO UTC
  last_refreshed_at: string | null // ISO UTC
  status: "premarket" | "open" | "locked"

  // Session reference
  yesterday_close: number
  official_open?: number | null

  // GEX summary
  net_gex: number
  flip_level: number
  gamma_wall: number
  put_wall: number
  regime: string

  // OI walls and range
  wall_rally: [number, number][]
  wall_drop: [number, number][]
  spx_range_est: number

  // Premarket
  premarket_bias: string
  premarket_price: number

  // Signals
  signals: {
    spy_component: SignalResult
    iToD: SignalResult
    optimized_tod: SignalResult
    tod_gap: SignalResult
    dpl: DPLResult
    ad_6_5: BreadthResult
    dom_gap: SignalResult
  }

  // Algorithm resolution
  algorithm_step: 1 | 2 | 3 | null
  recommendation: "GO_LONG" | "GO_SHORT" | "WAIT" | null
  signal_unity: boolean | null
  reason: string | null

  // Minute-14 immutable lock
  min14_high: number | null
  min14_low: number | null
  otm_long_strike: number | null
  otm_short_strike: number | null

  // Live fields
  dpl_live: DPLResult | null
  live_session_high?: number | null
  live_session_low?: number | null

  // Screenshot artifacts
  screenshots?: {
    premarket?: ScreenshotArtifact | null
    locked?: ScreenshotArtifact | null
    final?: ScreenshotArtifact | null
  }
}

interface SignalResult {
  bias: "bullish" | "bearish" | "neutral"
  value: number
  confidence: number
}

interface DPLResult {
  direction: "LONG" | "SHORT" | "NEUTRAL"
  color: "green" | "red" | "gray"
  separation: number
  is_expanding: boolean
}

interface BreadthResult {
  ratio: number
  bias: "bullish" | "bearish" | "neutral"
  participation: "broad" | "mixed" | "narrow"
}

interface ScreenshotArtifact {
  phase: "premarket" | "locked" | "final"
  generated_at: string
  storage_path: string
  public_url?: string | null
  width: number
  height: number
  template_version: string
}
```

### Schema rules

- `min14_*` values are immutable after `/lock-minute14`
- raw options chains and full minute-bar arrays must not be stored in the top-level
  playbook document
- if raw debug snapshots are needed, store them in a subcollection or only in logs
- additive fields are allowed as long as `lib/models/daily_playbook.dart` remains
  backward compatible
- screenshot metadata belongs in the playbook document, while binary image files
  belong in object storage

## 11. Signal Computation Rules

### 11.1 Baseline definitions

The playbook exposes 7 directional signals plus GEX context.

| Signal | Production rule |
|---|---|
| `spy_component` | Premarket gap/bias relative to previous close. Rename later if direct SPX premarket handling changes. |
| `iToD` | Historical intraday directional tendency by time bucket. |
| `optimized_tod` | Intraday trend/separation model. |
| `tod_gap` | Gap-aware intraday trend blend. |
| `dpl` | Primary tiebreaker using MACD-equivalent separation logic. |
| `ad_6_5` | Breadth signal. Sector ETF breadth proxy is acceptable in v1 if documented as proxy. |
| `dom_gap` | Dominance/gap blend from OI structure and opening context. |

### 11.2 Production posture

Not every scaffolded signal is equally mature today.

For production v1:

- GEX, walls, range estimate, previous close, official open, gap detection, and
  minute-14 are required
- DPL is required
- sector ETF breadth proxy is acceptable if direct breadth feed is unavailable
- `iToD`, `optimized_tod`, `tod_gap`, and `dom_gap` may ship as heuristics, but
  they must be versioned and clearly treated as model outputs, not audited facts

### 11.3 DPL requirement

Production DPL must reuse the same MACD logic used by the existing SPX engine, or
that logic must be extracted into a shared implementation.

The current scaffolded Python MACD math is acceptable for development, but it is
not enough to claim parity with the app's trading logic until the shared source of
truth is explicit.

### 11.4 GEX requirement

The GEX flip level must be based on cumulative GEX sorted by strike, not merely a
sign change in per-strike GEX values.

Production GEX summary must include:

- `net_gex`
- `flip_level`
- `gamma_wall`
- `put_wall`
- `regime`

### 11.5 Range estimate

Use near-dated ATM IV and express the result in SPX points.

If multiple range estimators are later introduced, persist:

- the chosen estimate in `spx_range_est`
- the estimator version in `signal_engine_version`

## 12. Opening Resolution Algorithm

### Inputs

- previous close
- official open from the first 09:30 ET bar
- the 7 signal outputs
- current DPL direction

### Step logic

```text
STEP 1: Significant gap?
  gap_points = abs(official_open - yesterday_close)
  if gap_points > 5:
    recommendation = WAIT
    algorithm_step = 1
    reason = "Gap day. Wait for post-open DPL confirmation."

STEP 2: No significant gap and all 7 signals align?
  if all 7 are bullish:
    recommendation = GO_LONG
    algorithm_step = 2
    signal_unity = true
  if all 7 are bearish:
    recommendation = GO_SHORT
    algorithm_step = 2
    signal_unity = true

STEP 3: Mixed set
  use DPL as tiebreaker
  if DPL == LONG:
    recommendation = GO_LONG
  else if DPL == SHORT:
    recommendation = GO_SHORT
  else:
    recommendation = WAIT
  algorithm_step = 3
  signal_unity = false
```

### Additional production rule

On gap days, `/resolve` should usually emit `WAIT` at 09:30 ET. `/refresh` may
later promote the recommendation once the DPL state is sufficiently formed.

## 13. Minute-14 Lock

The lock occurs after the first 14 completed 1-minute bars of the regular session.

Bars included:

- `09:30`
- `09:31`
- `09:32`
- `09:33`
- `09:34`
- `09:35`
- `09:36`
- `09:37`
- `09:38`
- `09:39`
- `09:40`
- `09:41`
- `09:42`
- `09:43`

At `09:44 ET`, compute:

- `min14_high = max(high of bars 09:30..09:43)`
- `min14_low = min(low of bars 09:30..09:43)`
- `otm_long_strike = min14_low - 50`
- `otm_short_strike = min14_high + 50`

Production rule:

- these values do not change later in the day
- if later session highs/lows are important, store them separately in live fields

## 14. Screenshot Generation

The screenshot shown in your reference should not be treated as a single monolith.
Production should generate 3 distinct daily artifacts.

### 14.1 Required phases

| Phase | Target time | Market state | Intended use |
|---|---|---|---|
| `premarket` | `09:21 ET` | before open | review context before the opening bell |
| `locked` | `09:45 ET` | after minute-14 lock | first actionable image with locked H/L and OTM references |
| `final` | `10:06 ET` | after refresh window | stable early-session summary for archive/share |

### 14.2 What each image should contain

#### Premarket screenshot

Must include:

- market date
- previous close
- premarket bias
- GEX / flip
- gamma regime
- walls
- range estimate
- baseline signal panel

Must not claim:

- minute-14 levels
- locked OTM strikes
- final post-open action certainty

#### Locked screenshot

Must include everything in the premarket image plus:

- official open-aware decision state
- minute-14 high/low
- OTM strike references
- current recommendation and reason

This is the earliest screenshot that can match the structure of your reference in a
credible way.

#### Final screenshot

Must include everything in the locked image plus:

- latest refresh timestamp
- post-open DPL/live confirmation state
- any updated recommendation after the S15-S35 confirmation window

### 14.3 Renderer implementation

Because this repo does not already contain a backend image renderer, v1 should use
a dedicated server-side renderer. The first implementation may render PNG output
directly in Python. An HTML-to-image renderer remains an acceptable later upgrade.

Required behavior:

- read only from the Firestore playbook document
- render one deterministic image per phase
- write the artifact to Cloud Storage
- write screenshot metadata back to Firestore

Do not render screenshots by launching the Flutter app in production Cloud Run.
That is operationally heavier and less predictable than a dedicated backend render
path.

### 14.4 Storage contract

Store image binaries in Cloud Storage at deterministic paths:

```text
gs://<bucket>/signal-sheet/<market_date>/premarket.png
gs://<bucket>/signal-sheet/<market_date>/locked.png
gs://<bucket>/signal-sheet/<market_date>/final.png
```

If access is private, store signed URL metadata or a viewer-service URL rather than
a public URL.

### 14.5 Render idempotency

- a phase render may be rerun safely
- reruns overwrite the same object path
- Firestore metadata should reflect the latest successful render timestamp
- rendering must never mutate the core signal values

### 14.6 Operational rule

If you want the screenshot "daily before the market open", that means the
`premarket` image at `09:21 ET`.

If you want the screenshot that most closely matches your reference image, that is
the `locked` image at `09:45 ET`, with the `final` image at `10:06 ET` serving as
the most complete early-session version

## 15. Data Acquisition and Performance

### 15.1 Shared request plan

Do not let each service method re-fetch the same data independently.

For `/generate`, fetch shared inputs once:

- quote snapshot
- previous close
- expiration list
- limited near-term options chains
- historical bars needed for model inputs
- sector ETF quotes for breadth proxy

Then pass those shared payloads into calculators.

This reduces:

- total latency
- Tradier rate pressure
- inconsistent calculations caused by slightly different snapshots

### 15.2 HTTP client requirements

Before production, replace per-call `httpx.AsyncClient()` creation with a shared,
reused async client and connection pooling.

Requirements:

- request timeout per upstream call
- bounded retries with exponential backoff for transient 429/5xx errors
- structured logging of upstream latency
- graceful `noop` or `WAIT` fallback only where explicitly defined

### 15.3 Time budget

Cloud Run timeout should be set to 60 seconds.

Target latency:

- `/generate` p95 under 20 seconds
- `/resolve`, `/lock-minute14`, `/refresh` p95 under 10 seconds
- `/render-snapshot` p95 under 15 seconds

## 16. Security

### Invocation

- Cloud Scheduler invokes Cloud Run with OIDC
- Cloud Scheduler service account needs `roles/run.invoker`
- Cloud Run must not allow unauthenticated invocations

### Token verification

Production verification must check:

- bearer token presence
- issuer
- audience equals the deployed service URL
- email or principal matches the approved scheduler service account

Generic token validation without audience checking is not enough.

### Secrets

Use:

- `TRADIER_API_KEY`
- optional `POLYGON_API_KEY` if a future breadth source is adopted

Secrets must come from Secret Manager or an equivalent managed secret binding.

## 17. Frontend Consumption

The consumer in this repo is Flutter, not React.

### Required client rule

The app must subscribe using the Eastern market date. Do not derive the document id
using:

- raw `DateTime.now()` in the user's local timezone
- raw UTC date string

If the app cannot reliably compute the Eastern market date, expose the current
`market_date` from the backend or from a lightweight config document.

### Backward compatibility

`lib/models/daily_playbook.dart` already supports the core fields used by this
pipeline. Extra top-level fields may be added safely as long as required existing
fields remain stable.

## 18. Push Notification Boundary

Push is optional and not in the critical path for v1.

If notifications are later added:

- trigger them downstream after Firestore write success
- use the existing sender contract in `functions/index.js`
- use the payload conventions already documented in
  `docs/spx-remote-push-contract.md`
- never make playbook generation depend on FCM success

## 19. Observability

Every request must log:

- `phase`
- `market_date`
- `symbol`
- `source_symbol`
- `status`
- `outcome`
- `duration_ms`
- `tradier_calls`
- `firestore_write`
- `recommendation`
- `algorithm_step`
- `error_code` when applicable

Renderer requests must additionally log:

- `render_phase`
- `template_version`
- `storage_path`
- `render_duration_ms`

### Alerts

Create alerts for:

- two consecutive scheduler failures for the same phase
- missing playbook document after `09:25 ET`
- missing `official_open` after `09:31 ET`
- missing minute-14 lock after `09:45 ET`
- missing `premarket` screenshot after `09:23 ET`
- missing `locked` screenshot after `09:47 ET`
- missing `final` screenshot after `10:08 ET`

## 20. Testing Requirements

### Unit tests

Required for:

- market date and trading-day helpers
- GEX cumulative flip level logic
- range estimator
- opening algorithm resolution
- minute-14 lock computation
- response contract helpers

### Integration tests

Required with mocked Tradier responses and Firestore emulator for:

- `/generate`
- `/resolve`
- `/lock-minute14`
- `/refresh`
- `/render-snapshot`

### Manual smoke tests

Required before production rollout:

1. run service locally against sandbox or recorded fixtures
2. call each endpoint with authenticated request
3. verify Firestore writes for one synthetic market day
4. verify Flutter model deserializes the stored document
5. verify each screenshot phase is written to the expected storage path

## 21. Current Scaffold Gaps to Close Before Production

The current repo scaffold is useful, but it is not production-ready yet.

Must fix before shipping:

1. default symbol handling currently leans `SPY`; production must use `SPX` or
   explicitly declare proxy mode
2. OIDC verification must validate audience and approved caller identity
3. `/resolve` must use official open, not latest spot
4. `/refresh` must be allowed to update decision state, not only `dpl_live`
5. the Tradier client must reuse HTTP connections instead of creating a new client
   per method call
6. market-date and trading-calendar logic must be centralized
7. scaffolded heuristic signals must be versioned and documented as proxies where
   applicable
8. a dedicated screenshot renderer and storage flow must be added
9. deployment config and tests must be added before rollout

## 22. Acceptance Criteria

This pipeline is production-ready when all of the following are true:

- Cloud Scheduler jobs run in `America/New_York`
- every handler is idempotent and authenticated
- non-trading days return `ok/noop`
- `/generate` creates a complete premarket document
- `/resolve` uses official open and writes a decision
- `/lock-minute14` writes immutable minute-14 levels
- `/refresh` updates live DPL and can evolve a prior `WAIT`
- `/render-snapshot` produces `premarket`, `locked`, and `final` PNG artifacts
- Flutter can deserialize and display the stored playbook
- logs and alerts exist for missing daily phases
- unit and integration tests pass

## 23. Implementation Order

Implement in this order:

1. centralize market-date and session-phase utilities
2. harden authentication and response helpers in `micro-services/signal-sheet-service/main.py`
3. refactor `TradierClient` to use shared pooled HTTP client behavior
4. refactor `/generate` so calculators share one fetched market snapshot
5. fix `/resolve` to read official open from intraday bars
6. make `/lock-minute14` immutable and explicit
7. expand `/refresh` to support post-open recommendation updates
8. add the HTML-to-image screenshot renderer and `/render-snapshot`
9. persist screenshot metadata and Cloud Storage paths
10. add unit and integration tests
11. wire Flutter read path using Eastern market date
12. add deployment and alerting configuration

---

Version: `production-spec-v1`
Last updated: `2026-03-13`
