# SPX Learning Agent Plan

## Goal
- Capture every SPX trade decision and outcome in a structured dataset.
- Use that dataset to continuously improve future entry/exit decisions.
- Keep human control and hard risk limits in place.

## What Is Implemented Now (Data Foundation)
- `SpxBloc` now records a journal entry on position open (manual + auto scanner).
- `SpxBloc` records a journal exit on manual close, stop-loss, take-profit, and expiry.
- Records include:
  - contract context (`symbol`, `side`, `strike`, `expiry`, `dteEntry`, `dteExit`)
  - decision rationale (`entrySource`, `entryReasonCode`, `entryReasonText`, `signalScore`, `signalDetails`)
  - PnL outcomes (`entryPremium`, `exitPremium`, `pnlUsd`, `pnlPct`)
  - market context (`spotEntry/Exit`, `ivRankEntry/Exit`, `dataMode`)
  - term-policy context (`termMode`, `termExactDte`, `termMinDte`, `termMaxDte`)
- Storage path:
  - local: `SharedPreferences` (fast fallback)
  - cloud: Firestore collection `users/{userId}/spx_trade_journal`
- Data tooling now available:
  - filterable journal queries (`closed/open`, date range, symbol/side/source/reason)
  - canonical reason-code taxonomy for entry/exit events
  - export to CSV/JSONL for model training pipelines
  - post-trade review labels (`good_setup` | `bad_setup` | `neutral`) + analyst notes
  - feature-engineered CSV export for direct model ingestion
  - SPX Journal screen in-app for review and quick export

## Learning Agent Architecture

### 1) Data Ingestion Layer
- Source: `spx_trade_journal` records.
- Trigger: on each entry/exit write.
- Validation:
  - reject malformed rows (`tradeId`, timestamps, premiums required)
  - enforce canonical reason codes
  - enforce numeric ranges (DTE, IV rank, pnl%)

### 2) Feature Pipeline
- Build model-ready features from each completed trade:
  - entry features: delta, gamma, theta, vega, IV rank, DTE, signal details
  - regime features: session time bucket, day-of-week, market-hours flag, data mode
  - policy features: term filter mode/range active at trade time
- Build labels:
  - `win_flag` (pnlUsd > 0)
  - `pnl_pct`
  - `max_adverse_excursion` and `max_favorable_excursion` (phase 2)

### 3) Model Layer (Start Simple)
- Begin with interpretable models:
  - logistic regression for win probability
  - gradient boosting regressor for expected `pnl_pct`
- Output:
  - entry score (0-100)
  - confidence bucket (low/medium/high)
  - reason attribution (top factors)

### 4) Decision Layer
- Agent does not directly place trades at first.
- Agent proposes:
  - top candidate contracts
  - confidence
  - expected pnl range
  - recommended exit policy (target/stop/time stop)
- Existing hard guards remain authoritative:
  - per-trade notional cap
  - portfolio cap
  - side and DTE concentration caps

### 5) Feedback + Evaluation
- Daily and weekly evaluation jobs:
  - precision/recall for profitable entries
  - realized pnl vs baseline scanner
  - calibration drift by DTE bucket and side
- Deploy only if:
  - evaluation window is statistically meaningful
  - model outperforms baseline with risk-adjusted metrics

## Delayed and Validated Entry Plan

### Feature Goal
- Let users control how quickly a discovered option can be entered.
- Preserve user control by default, while allowing auto-buy flows when enabled.
- Log all non-executed opportunities so users can review what was missed.

### User Settings (New)
- `opportunityExecutionMode`
  - `manual_confirm` (default)
  - `auto_after_delay`
  - `auto_immediate`
- `entryDelaySeconds` (used only for `auto_after_delay`)
- `validationWindowSeconds` (used only for `manual_confirm`)
- `notificationsEnabled`
- `maxSlippagePct` (execution guardrail)

### Opportunity Lifecycle
States:
- `found`: scanner/agent finds a candidate.
- `alerted`: notification sent to user.
- `pending_user`: waiting for user approval/rejection.
- `pending_delay`: waiting for auto-delay timer to complete.
- `approved`: user explicitly approved.
- `rejected`: user explicitly rejected.
- `executed`: order filled (or submitted successfully, depending on broker semantics).
- `missed`: not executed before timeout or blocked by guardrails.

Transitions:
- `found -> alerted`
- `alerted -> pending_user` for `manual_confirm`
- `alerted -> pending_delay` for `auto_after_delay`
- `alerted -> executed` for `auto_immediate` (after guard checks)
- `pending_user -> approved -> executed`
- `pending_user -> rejected`
- `pending_user -> missed` (validation timeout)
- `pending_delay -> executed` (timer complete + guard checks pass)
- `pending_delay -> missed` (cancelled/timeout/guard failure)

### Execution Rules
1. Option found:
   - persist opportunity record immediately.
   - send user notification.
   - load user settings and branch flow.
2. Manual confirm:
   - show validation UI with countdown (`validationWindowSeconds`).
   - execute only when user taps approve.
3. Auto after delay:
   - schedule execution at `now + entryDelaySeconds`.
   - allow user cancel before timer expiry.
4. Auto immediate:
   - run pre-trade checks and execute immediately.
5. Before every execution:
   - re-check quote freshness.
   - re-check slippage vs `maxSlippagePct`.
   - re-check current hard risk limits and market-open status.
   - if any check fails, mark `missed`, do not place order.

### Notification and UX Requirements
- On opportunity detection, send alert with deep link to review page.
- Review page must show:
  - contract details (symbol/side/strike/expiry)
  - premium snapshot and current quote
  - score/rationale from scanner/agent
  - countdown and current execution mode
  - actions: `Approve`, `Reject`, and `Cancel Auto` when relevant
- If user does not validate before timeout, close opportunity as `missed`.

### Missed Opportunity Logging
Store missed records with reason codes:
- `user_rejected`
- `user_timeout`
- `delay_cancelled`
- `price_moved_slippage`
- `risk_guard_failed`
- `market_closed`
- `quote_stale`

Include:
- opportunity snapshot at find time
- terminal reason code
- final quote context at decision time
- time-to-decision metadata

### Data Model Additions
- New collection/table: `spx_opportunity_journal`
- Core fields:
  - `opportunityId`, `createdAt`, `updatedAt`, `status`
  - `symbol`, `side`, `strike`, `expiry`, `dte`, `premiumAtFind`
  - `signalScore`, `signalDetails`, `entryReasonCode`, `entrySource`
  - `executionModeAtDecision`, `entryDelaySeconds`, `validationWindowSeconds`
  - `notificationSentAt`, `userAction`, `userActionAt`
  - `executedTradeId` (nullable)
  - `missedReasonCode` (nullable)

### Rollout Phases (Feature-Specific)
1. Phase A: Data + settings foundation
   - add settings schema and persistence
   - create `spx_opportunity_journal` write path
2. Phase B: Manual confirmation flow
   - add alert + in-app review + approve/reject + timeout-to-missed
3. Phase C: Delayed auto-buy
   - add timer-based executor + cancel path
4. Phase D: Auto-immediate and analytics
   - enable guarded immediate execution
   - add Missed Opportunities review and performance reports

### Implementation Progress (Current)
- Completed: settings schema + persistence (`spxOpportunityExecutionMode`, delay, validation window, slippage, alerts).
- Completed: opportunity lifecycle journal (`found`, `alerted`, `pending_user`, `pending_delay`, `executed`, `missed`, `rejected`) with local + Firestore repositories.
- Completed: SPX orchestration branches for manual confirm, auto-after-delay, and auto-immediate with guardrail checks before execution.
- Completed: pending actions (`Approve`, `Reject`, `Cancel Auto`) and timeout/missed reason logging.
- Completed: in-app opportunities UI (pending + missed), summary metrics, and deep-link handling from local/remote notification payloads.
- Completed: remote push contract doc + test sender script (`docs/spx-remote-push-contract.md`, `scripts/send_test_spx_push.sh`).
- Completed: automated tests for opportunity repository and SPX lifecycle branches.
- Completed: lifecycle coverage for `user_rejected` and `delay_cancelled` missed-reason paths.
- Completed: serialized per-opportunity journal writes in `SpxBloc` to prevent async status regression (for example `executed` overwritten by older `alerted` writes).
- Completed: backend sender scaffold via Firebase Cloud Functions (`sendSpxOpportunityPush`, `sendSpxOpportunityPushHttp`) with token fanout and invalid-token cleanup.
- Completed: replaced Secret Manager dependency with env-based HTTP dispatch key (`functions/.env`) to avoid Blaze-only secret setup.
- Completed: Spark-compatible fallback sender (`functions/scripts/dispatch_spx_push.js`) for push fanout without Cloud Functions deploy.
- Remaining: run end-to-end device validation with chosen sender path (Functions on Blaze, or local/CI dispatcher on Spark).

## Tradier Sandbox Token Support Plan

### Current Gap
- `SpxOptionsService` already supports both Tradier base URLs:
  - sandbox: `https://sandbox.tradier.com/v1`
  - production: `https://api.tradier.com/v1`
- The app does not currently expose that choice end to end.
- `SpxBloc` hard-codes `useSandbox: false` in both constructor and token hot-swap flow.
- Secure storage only keeps one generic token key (`tradier_api_token`), so there is no explicit environment pairing.
- Settings UI only asks for a token; it does not let the user choose whether that token is for sandbox or production.
- Startup restore in `main.dart` reloads only the token, so the app cannot reliably reconstruct the correct Tradier endpoint.

### Desired Behavior
- User can choose Tradier environment: `sandbox` or `production`.
- App stores the selected environment in app preferences.
- App stores Tradier tokens in secure storage only, not in Firestore or shared preferences.
- App can keep separate sandbox and production tokens so switching environments does not overwrite the other token.
- SPX live-data service is rebuilt with the correct endpoint whenever:
  - app starts
  - settings change
  - token changes
  - environment changes
- Logs and UI clearly indicate whether the app is using:
  - Tradier sandbox
  - Tradier production
  - simulator fallback

### Proposed Data Model
- Add a simple environment value:
  - `sandbox`
  - `production`
- Persist selected environment in `AppPreferences` as `spxTradierEnvironment`.
- Replace the single token storage approach with separate secure-storage keys:
  - `tradier_api_token_sandbox`
  - `tradier_api_token_production`
- Keep legacy read support for `tradier_api_token` during migration.

### Implementation Breakdown

#### 1. Settings and persistence
- File: `lib/services/app_settings_repository.dart`
- Add `spxTradierEnvironment` to `AppPreferences`, local preferences keys, and Firebase sync.
- Normalize invalid values to `sandbox` or `production` with a safe default.
- Recommendation: default to `sandbox` for first-time setup because it is the safer path for testing.

#### 2. Secure storage strategy
- Files:
  - `lib/main.dart`
  - `lib/screens/settings_screen.dart`
- Introduce separate secure-storage keys per Tradier environment.
- On save:
  - write token to the key for the currently selected environment
  - do not copy tokens into Firestore-backed settings
- On load:
  - read selected environment from app preferences
  - load token from the matching secure-storage key

#### 3. Legacy migration
- Files:
  - `lib/main.dart`
  - `lib/screens/settings_screen.dart`
- Migration rules:
  - if legacy key `tradier_api_token` exists and env-specific key is missing, copy the legacy token into the selected environment key
  - prefer selected environment if already stored
  - if no environment exists yet, assume `sandbox` for a newly entered token and assume `production` only for existing upgraded installs if that reduces surprise for current users
- After successful migration, stop reading the legacy key except as fallback.

#### 4. SPX state and events
- Files:
  - `lib/blocs/spx/spx_event.dart`
  - `lib/blocs/spx/spx_state.dart`
  - `lib/blocs/spx/spx_bloc.dart`
- Extend SPX state to track selected Tradier environment.
- Replace token-only update flow with an environment-aware credentials update.
- Preferred event shape:
  - `UpdateTradierCredentials(token, environment)`
- Rebuild `SpxOptionsService` with:
  - `apiToken: token`
  - `useSandbox: environment == sandbox`
- Update startup logs so they explicitly say:
  - `Connected to Tradier sandbox`
  - `Connected to Tradier production`
  - `Running in simulation mode`

#### 5. Startup restore path
- File: `lib/main.dart`
- When authenticated shell starts:
  - load `AppPreferences`
  - read `spxTradierEnvironment`
  - load token for that environment from secure storage
  - initialize `SpxBloc` with both values or dispatch one environment-aware event before first refresh
- Avoid a startup race where the app initializes against production first and only later switches to sandbox.

#### 6. Settings UI
- File: `lib/screens/settings_screen.dart`
- Add a visible environment selector above the token field:
  - `Sandbox`
  - `Production`
- Show environment-specific helper text and token status.
- When the user switches environment:
  - update preferences immediately
  - reload the token field from the matching secure-storage key
  - reconfigure `SpxBloc`
- Update save/clear copy to mention the active environment so the action is unambiguous.

#### 7. Observability and UX
- Files:
  - `lib/blocs/spx/spx_bloc.dart`
  - relevant SPX screens
- Surface current source more precisely than generic `live`:
  - live + sandbox
  - live + production
  - simulator
- Improve failure logs for the common mismatch case:
  - sandbox token against production endpoint
  - production token against sandbox endpoint
- Keep simulator fallback behavior unchanged so the app remains usable if auth fails.

### Testing Plan

#### Unit tests
- `AppPreferences` load/save round-trip for `spxTradierEnvironment`
- legacy token migration behavior
- environment selector normalization
- `SpxBloc` rebuilds `SpxOptionsService` with `useSandbox: true` for sandbox
- `SpxBloc` rebuilds `SpxOptionsService` with `useSandbox: false` for production

#### Widget or integration tests
- Settings screen shows and persists environment selector
- switching environment reloads the matching token into the field
- saving sandbox token does not overwrite production token
- app startup restores sandbox environment and token correctly

#### Manual validation
- Save sandbox token, restart app, confirm logs show sandbox endpoint
- Switch to production with no token, confirm simulator fallback
- Save production token, switch back to sandbox, confirm original sandbox token is still present

### Rollout Sequence
1. Add preferences + secure-storage keys + migration helpers.
2. Add SPX event/state wiring for environment-aware credentials.
3. Update startup restore in `main.dart` to avoid wrong-endpoint boot.
4. Update Settings UI and user-facing copy.
5. Add tests for persistence, migration, and bloc reconfiguration.
6. Run on-device validation with a real sandbox token.

### Acceptance Criteria
- A sandbox Tradier token can be saved and reused after app restart.
- SPX requests go to `sandbox.tradier.com` when sandbox is selected.
- Production and sandbox tokens do not overwrite each other.
- The app no longer hard-codes production in SPX token update flows.
- Simulator fallback still works when no valid token is present.

## ITM / ATM Contract Targeting Plan

### Goal
- Let SPX users intentionally target:
  - `ATM` (at the money)
  - `ITM` (in the money)
  - `OTM` / out of the money
- Keep current behavior as the default so existing scanner flows do not change unexpectedly.
- Avoid selecting deep ITM or far OTM contracts that would sharply distort premium, delta, and fill quality.

### Current Gap
- `OptionsContract` does not expose moneyness as a first-class property.
- The chain UI has an `ATM` visual hint only; it is calculated inline in `spx_chain_screen.dart` and not reusable by scanner logic.
- There is no `ITM` label in the chain or dashboard signals.
- Scanner selection currently filters by:
  - side
  - signal quality
  - risk guards
  - but not explicit moneyness preference
- Current scoring rewards the `0.20–0.45` delta zone, which tends to bias toward near-ATM or OTM contracts and can under-rank ITM contracts.

### Proposed Product Behavior
- Add a user-selectable SPX contract targeting mode:
  - `delta_zone` (default, current behavior)
  - `atm`
  - `near_itm`
  - `near_otm`
  - `atm_or_near_itm`
- Optional phase 2:
  - `atm_or_near_otm`
  - `atm_itm_otm_ranked`
- `near_itm` should mean the nearest 1-2 strikes in the money, not any depth of ITM.
- `near_otm` should mean the nearest 1-2 strikes out of the money, not far lottery-ticket contracts.
- Manual chain browsing should show clear `ITM`, `ATM`, and `OTM` tags.
- Auto-scanner and dashboard signal lists should rank or filter contracts according to the selected targeting mode.

### Definitions
- Calls:
  - `ITM`: strike < spot
  - `ATM`: closest strike to spot within ATM tolerance
  - `OTM`: strike > spot
- Puts:
  - `ITM`: strike > spot
  - `ATM`: closest strike to spot within ATM tolerance
  - `OTM`: strike < spot
- ATM tolerance:
  - start with the current practical SPX rule of nearest strike / about 5 points
  - phase 2: derive from actual chain strike spacing instead of hard-coding

### Data Model Additions
- File: `lib/models/spx_models.dart`
- Add moneyness enum:
  - `itm`
  - `atm`
  - `otm`
- Add reusable contract helpers:
  - `moneynessForSpot(double spot)`
  - `strikeDistanceFromSpot(double spot)`
  - `isAtmForSpot(double spot)`
  - `isNearItmForSpot(double spot, {int maxSteps = 1})`
  - `isNearOtmForSpot(double spot, {int maxSteps = 1})`
- Keep these derived from current spot so live and simulated chains behave consistently.

### Settings and Persistence
- Files:
  - `lib/services/app_settings_repository.dart`
  - `lib/screens/settings_screen.dart`
- Add new preference:
  - `spxContractTargetingMode`
- Optional follow-up preference:
  - `spxNearItmMaxSteps` (default `1`)
- Persist locally and in Firebase like the existing SPX term/execution settings.

### Selection Logic Changes

#### 1. Manual chain selection
- File: `lib/screens/spx/spx_chain_screen.dart`
- Replace inline ATM detection with shared contract moneyness helpers.
- Show reusable badges:
  - `ITM`
  - `ATM`
  - `OTM`
- Optional phase 2:
  - add filter chips to show only `ATM`, `ITM`, or `All`

#### 2. Dashboard top signals
- File: `lib/screens/spx/spx_dashboard_screen.dart`
- Rank the signal list using selected targeting mode.
- If mode is `atm`, prioritize the strike closest to spot.
- If mode is `near_itm`, prioritize the first ITM strike, then second ITM strike if enabled.
- If mode is `near_otm`, prioritize the first OTM strike, then second OTM strike if enabled.

#### 3. Auto-scanner execution
- File: `lib/blocs/spx/spx_bloc.dart`
- Before scanner opens a contract, filter or sort candidates by targeting mode.
- Recommended rule:
  - first pass: only matching contracts for selected mode
  - fallback pass: use current `delta_zone` behavior if no candidates match
- This avoids empty scanner behavior while still honoring user intent.

### Scoring and Risk Adjustments
- Files:
  - `lib/services/spx/spx_options_service.dart`
  - `lib/services/spx/spx_options_simulator.dart`
  - `lib/blocs/spx/spx_bloc.dart`
- Current scoring gives a point for the target delta zone only.
- Update scoring so that:
  - `delta_zone` mode keeps current weights
  - `atm` mode rewards nearest-to-spot contracts
  - `near_itm` mode rewards shallow ITM contracts without promoting deep ITM names
  - `near_otm` mode rewards shallow OTM contracts without promoting far OTM contracts
- Add extra premium guard for ITM mode:
  - reject contracts whose notional exceeds existing per-trade caps
  - optionally cap intrinsic-heavy contracts if they exceed a configurable max premium
- Add extra distance guard for OTM mode:
  - reject contracts beyond a configurable strike-step or percent-from-spot threshold
  - keep scanner from drifting into very low-delta contracts just because premium is cheap

### Journal and Analytics
- Files:
  - SPX trade journal write paths in `SpxBloc`
  - export services
- Add to journal/export context:
  - `contractMoneynessAtEntry`
  - `contractMoneynessAtExit`
  - `strikeDistanceFromSpotEntry`
  - `strikeDistanceFromSpotExit`
  - `contractTargetingMode`
- This is needed to compare ATM vs ITM performance later in the learning agent.

### Testing Plan

#### Unit tests
- `OptionsContract` moneyness classification for:
  - calls
  - puts
  - exact ATM boundary
- settings round-trip for `spxContractTargetingMode`
- scanner candidate selection honors:
  - `atm`
  - `near_itm`
  - `near_otm`
  - fallback to current mode when no match exists

#### Widget tests
- Chain rows display correct `ITM` / `ATM` / `OTM` badges.
- Settings screen persists the selected targeting mode.
- Dashboard signal list reorders when targeting mode changes.

#### Manual validation
- With calls selected and spot near a strike boundary:
  - verify nearest strike is tagged `ATM`
  - verify first strike below spot is tagged `ITM`
- With puts selected:
  - verify classification flips correctly
- Run scanner in `atm` and `near_itm` modes and confirm selected contracts change as expected.
- Run scanner in `near_otm` mode and confirm it chooses the first out-of-the-money strike instead of far OTM contracts.

### Rollout Sequence
1. Add reusable moneyness helpers to `OptionsContract`.
2. Add settings persistence for contract targeting mode.
3. Update chain UI badges to use shared moneyness logic.
4. Update dashboard signal ranking and auto-scanner candidate selection.
5. Add journal/export fields for moneyness and targeting mode.
6. Validate premium/risk behavior for shallow ITM and shallow OTM contracts.

### Acceptance Criteria
- Users can choose `ATM`, `near ITM`, or `near OTM` contract targeting from Settings.
- Chain and dashboard visibly show contract moneyness.
- Auto-scanner honors the selected targeting mode.
- Deep ITM contracts are not accidentally preferred over shallow ITM contracts.
- Far OTM contracts are not accidentally preferred over shallow OTM contracts.
- Trade journal captures moneyness and targeting mode for later model analysis.

### Engineering Task Breakdown
1. Settings domain
   - add new settings model/repository fields
   - expose controls in Settings screen
2. Opportunity domain
   - add `SpxOpportunity` model + repository (local + Firestore sync)
   - add status transition helpers and reason-code constants
3. SPX bloc orchestration
   - on candidate found: persist + notify + branch execution mode
   - add timeout and delayed-execution handlers
   - add approve/reject/cancel events
4. Execution service
   - centralize pre-trade guard checks
   - return explicit failure reason for missed logging
5. UI
   - add Opportunity Review screen
   - add Missed Opportunities list/detail screen
6. Analytics
   - add summary cards: found, executed, missed by reason, avg decision latency
7. Testing
   - unit tests for lifecycle transitions and settings branches
   - bloc tests for manual/auto-delay/auto-immediate paths
   - integration tests for timeout, cancel, and missed logging

## Rollout Plan

### Phase 0 (Now)
- Complete dataset capture and cloud sync.
- Add read/report endpoint for export (CSV/BigQuery-ready JSON).

### Phase 1
- Build trade journal dashboard:
  - filters by DTE range, side, reason code, data mode
  - win rate and pnl by bucket
- Add reason code taxonomy and enforce it.

### Phase 2
- Add feature materialization job + offline trainer.
- Generate daily model artifact and store metadata/version.

### Phase 3
- Shadow mode:
  - model scores opportunities
  - no execution changes
  - compare model picks vs scanner picks

### Phase 4
- Controlled assist mode:
  - model adjusts ranking only
  - execution still bounded by hard risk rules
  - explicit kill switch in settings

## Immediate Next Tasks
1. Add `TradeJournalExportService` (Firestore -> CSV/JSONL).
2. Add `reasonCode` constants/enums to prevent free-text drift.
3. Add `closedOnly` and date-range query helpers in repository.
4. Add a simple “Journal” screen for manual review and labeling.
5. Add nightly aggregate job (Cloud Function or scheduled backend task).
6. Add delayed/validated entry settings and `spx_opportunity_journal` model.
7. Implement notification + manual validation flow with timeout-to-missed.
8. Implement `auto_after_delay` executor with cancel and guard re-checks.
9. Add Missed Opportunities UI and missed-reason analytics.

## Implementation Progress (Current Branch)
- Completed:
  - Opportunity execution settings added and persisted (`manual_confirm`, `auto_after_delay`, `auto_immediate`, delay/validation/slippage).
  - `notificationsEnabled` is now enforced for SPX opportunity alerts (alerts stream + `notificationSentAt` behavior).
  - `spx_opportunity_journal` model/repository added with local + Firestore sync.
  - Scanner lifecycle logging added (`found` -> `alerted` -> pending/terminal transitions).
  - Manual approval/rejection with timeout-to-missed flow implemented.
  - Delayed auto-execution implemented with guard re-checks.
  - Cancel-auto path implemented for delayed opportunities (`delay_cancelled` missed reason).
  - Opportunities review UI added with pending actions and missed/rejected history.
  - Opportunity analytics summary added (found/pending/executed/missed, avg decision latency, top missed reasons).
  - Quote-freshness guard added before execution (`quote_stale` when contract quote age exceeds execution staleness threshold).
  - In-app deep link behavior added: SPX opportunity-found alerts include a `Review` action that opens SPX Activity > Opportunities.
  - Device-level local notifications added for SPX opportunity alerts while app is backgrounded, with payload routing to Opportunities.
  - Opportunity-specific local notification payloads added (`spx_opportunity:{id}`) and routed to focused opportunity context.
  - Remote push scaffold added: FCM token registration in Firestore (`users/{userId}/push_tokens/{token}`), foreground message surfacing, and opened-notification payload routing.
  - Rich deep links from remote/system payloads now route into opportunity-specific review context.
- In progress / remaining:
  - Remote push producer pipeline (server-side sender + authenticated dispatch) for opportunity alerts when app process is not active.
  - Broader automated tests for lifecycle transitions and branch coverage.
  - Added baseline repository tests for opportunity journal filters/upsert/normalization.
