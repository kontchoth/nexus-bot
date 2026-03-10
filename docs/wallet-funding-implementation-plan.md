# Wallet Funding Implementation Plan

## Goal
Allow users to deposit money into the app and use it for in-app transactions in a safe, auditable, and compliant way.

## Scope
- In scope: user funding, wallet balances, transaction usage, reconciliation, controls, and rollout plan.
- Out of scope (first version): margin/credit, interest-bearing balances, international rails.

## Guiding Principles
- Never treat a single balance field as source of truth.
- Use a ledger-first architecture (double-entry).
- Separate pending funds from available funds.
- Make all money mutations idempotent and traceable.
- Ship behind feature flags and staged limits.

## High-Level Architecture
1. Client (Flutter app)
- Add Money / Withdraw / Wallet History UI.
- Display `available`, `pending`, and recent ledger events.

2. Backend Money Service
- Handles funding intents, payment webhooks, ledger posting, holds, captures, releases.
- Owns wallet account and transaction state machine.

3. Payments + Verification Providers
- Payment rail provider (ACH + card).
- Bank account linking provider (if ACH pull).
- KYC/identity + sanctions screening provider.

4. Data Store
- Wallet accounts, ledger entries, payment events, holds, and reconciliation records.

## Compliance and Risk Requirements (Must-Have Before Launch)
1. KYC status required before enabling funding.
2. Sanctions screening + country restrictions.
3. Velocity limits (daily/weekly deposit and spend limits).
4. Device/account risk checks and fraud signals.
5. Explicit user disclosures, ToS, and consent records.
6. Audit logging for all privileged/admin actions.

## Domain Model (Suggested)
1. `wallet_accounts`
- `id`, `user_id`, `currency`, `status`, `created_at`

2. `ledger_entries`
- `id`, `wallet_account_id`, `entry_type` (`debit`/`credit`), `amount`, `currency`
- `reference_type`, `reference_id`, `idempotency_key`, `created_at`

3. `wallet_balances`
- `wallet_account_id`, `available_amount`, `pending_amount`, `updated_at`

4. `payment_intents`
- `id`, `user_id`, `provider`, `provider_ref`, `amount`, `currency`, `status`
- `failure_reason`, `created_at`, `updated_at`

5. `funding_holds`
- `id`, `wallet_account_id`, `amount`, `status`, `expires_at`, `reference_id`

6. `webhook_events`
- `id`, `provider`, `event_id`, `payload_hash`, `processed_at`, `status`

7. `reconciliation_runs`
- `id`, `provider`, `run_date`, `status`, `discrepancy_count`, `notes`

## Core State Machines
1. Funding Intent
- `created -> pending -> settled -> available`
- `pending -> failed`
- `settled -> reversed` (chargeback/ACH return path)

2. Spend Flow
- `requested -> hold_created -> captured` (on execution)
- `hold_created -> released` (cancel/failure/timeout)

## API Plan (First Iteration)
1. `POST /wallet/funding-intents`
- Create deposit intent, validate limits/KYC, return client action details.

2. `POST /wallet/funding-intents/{id}/confirm`
- Optional confirmation endpoint (provider dependent).

3. `GET /wallet/balance`
- Returns `available` and `pending`.

4. `GET /wallet/transactions`
- Paged ledger history for UI.

5. `POST /wallet/holds`
- Create hold before trade/transaction execution.

6. `POST /wallet/holds/{id}/capture`
- Capture held amount on successful transaction.

7. `POST /wallet/holds/{id}/release`
- Release hold on cancel/fail.

8. `POST /webhooks/payments`
- Verify signature, deduplicate event, update intent + ledger atomically.

## Ledger Rules
1. Deposit created
- Credit `pending`.

2. Deposit settled
- Debit `pending`, credit `available`.

3. Hold created
- Debit `available`, credit `held`.

4. Hold captured
- Debit `held`, credit `spent` (or transaction sink account).

5. Hold released
- Debit `held`, credit `available`.

6. Reversal/chargeback
- Debit `available` (or negative balance policy), credit `reversal`.

## Flutter App Plan
1. Add Wallet screens
- `Add Money`, `Withdraw`, `Wallet Activity`.

2. Add funding UI
- Amount input, payment method picker, status banners.

3. Add balance surfaces
- `Available` and `Pending` shown where transactions are initiated.

4. Add error/retry UX
- Pending/failure states with actionable next steps.

5. Add feature flag gating
- Funding features disabled until backend/compliance ready.

## Security Controls
1. Webhook signature verification.
2. Strict idempotency keys for all money mutations.
3. Encrypted secrets and key rotation.
4. Least-privilege service credentials.
5. Structured audit logs and immutable event trail.

## Reconciliation and Operations
1. Daily provider-vs-ledger reconciliation job.
2. Alerting on mismatch, stale pending intents, webhook failure spikes.
3. Admin tooling for read-only transaction inspection.
4. Manual intervention workflow for dispute/reversal events.

## Rollout Plan
1. Phase 0: Design + compliance review + provider setup.
2. Phase 1: Ledger + webhook pipeline + sandbox tests.
3. Phase 2: Internal dogfood with low limits.
4. Phase 3: External beta (small cohort, strict velocity caps).
5. Phase 4: Gradual production ramp with monitoring gates.

## Acceptance Criteria
1. Every balance change is backed by ledger entries.
2. No duplicate money movement under retries/webhook replays.
3. Pending vs available is always correct across app and backend.
4. Funding failures and reversals are reflected within SLA.
5. Reconciliation completes daily with zero unresolved critical discrepancies.

## Open Decisions to Resolve Before Build
1. Provider stack selection (payments, bank linking, KYC).
2. Custodial vs non-custodial legal model.
3. Negative balance policy for reversals.
4. Withdrawal eligibility window and anti-fraud hold period.
5. Country/state launch matrix and restrictions.

## Suggested Implementation Order (Engineering)
1. Finalize data model and migrations.
2. Implement ledger engine + idempotency utilities.
3. Build funding intent endpoints.
4. Build webhook ingestion and event processor.
5. Add hold/capture/release endpoints.
6. Integrate Flutter wallet/funding UI.
7. Add reconciliation jobs and operational alerts.
8. Add feature flag + staged rollout controls.
