# SPX Push Sender (Functions + Spark Fallback)

## Important Constraint
If deploy shows:

- `artifactregistry.googleapis.com can't be enabled`
- `project must be on the Blaze plan`

then Cloud Functions deployment is blocked on your current plan.

Use the Spark-compatible fallback below to send production pushes without deploying functions.

## Option A: Cloud Functions (requires Blaze)
Functions in `functions/index.js`:

- `sendSpxOpportunityPush` (callable)
- `sendSpxOpportunityPushHttp` (HTTP + key from env var `SPX_PUSH_DISPATCH_KEY`)

Deploy path:

1. `cd functions`
2. `npm install`
3. `cp .env.example .env`
4. set `SPX_PUSH_DISPATCH_KEY` in `.env`
5. `npx firebase deploy --only functions`

## Option B: Spark-Compatible Local/CI Dispatcher
Use local script (no Functions deploy required):

- `functions/scripts/dispatch_spx_push.js`

It reads:

- Firestore token registry: `users/{userId}/push_tokens`
- filters `alertsEnabled == true`
- optional platform filter
- sends FCM via Admin SDK
- prunes invalid tokens (unless disabled)

### Setup
1. `cd functions`
2. `npm install`
3. provide credentials:
   - either `--service-account /path/to/service-account.json`
   - or `GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`

### Example
```bash
cd /Users/hermann/working-copy/hintekk/mobile/nexus-bot/functions
npm run dispatch-spx-push -- \
  --project nexusbot-5edeb \
  --user <firebase_uid> \
  --opportunity-id opp_123456 \
  --title "SPX Opportunity Found" \
  --body "SPX 0XXC05800000 · 7DTE" \
  --service-account /absolute/path/service-account.json
```

### Alternative Payload Forms
- list route:
  - `--payload spx_opportunities`
  - or `--target spx_opportunities`
- focused route:
  - `--payload spx_opportunity:<id>`
  - or `--opportunity-id <id>`

### Optional Flags
- `--platform android|ios|macos|web|windows|linux|fuchsia`
- `--dry-run true|false`
- `--prune-invalid true|false`

## Payload Contract
Accepted payloads remain:

- `spx_opportunities`
- `spx_opportunity:{opportunityId}`

See `docs/spx-remote-push-contract.md` for full contract.
