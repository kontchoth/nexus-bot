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
