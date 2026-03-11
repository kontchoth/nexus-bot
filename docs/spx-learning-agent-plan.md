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
- Remaining: deploy functions and execute end-to-end device validation with real broker execution path.

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
