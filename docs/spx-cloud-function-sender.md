# SPX Cloud Function Push Sender

## Overview
This repo now includes Firebase Cloud Function senders for SPX opportunity push fanout:

- Function names:
  - `sendSpxOpportunityPush` (callable)
  - `sendSpxOpportunityPushHttp` (HTTP + secret)
- Runtime: Node.js 20
- Source: `functions/index.js`

This setup does not require Google Secret Manager, so it can run without Blaze-specific secret-manager setup.

It sends notifications to device tokens in Firestore path:

- `users/{userId}/push_tokens/{token}`

Only token docs with `alertsEnabled == true` are targeted.

## Auth Rules
Callable (`sendSpxOpportunityPush`) caller must be:

1. the same user (`request.auth.uid == userId`), or
2. an admin caller with custom claim `admin: true`.

Otherwise, callable returns `permission-denied`.

HTTP (`sendSpxOpportunityPushHttp`) caller must provide secret key via one of:

- `x-spx-dispatch-key: <secret>`
- `Authorization: Bearer <secret>`

Secret is loaded from function environment variable:

- `SPX_PUSH_DISPATCH_KEY`

## Input Contract
Payload mirrors `docs/spx-remote-push-contract.md`.

Required:

- `userId` (string)
- one of:
  - `payload`, or
  - `opportunityId`, or
  - `target=spx_opportunities`

Optional:

- `title` (string)
- `body` (string)
- `platform` (`android|ios|macos|web|windows|linux|fuchsia`)
- `dryRun` (bool)

Payload behavior:

- `payload=spx_opportunities` routes to list.
- `payload=spx_opportunity:{opportunityId}` routes to focused opportunity.
- if `opportunityId` is provided and payload is missing, payload is derived automatically.

## Response Shape
Returns summary object:

- `attempted`
- `success`
- `failed`
- `invalidTokensRemoved`
- `messageIds` (FCM message IDs)
- `errors` (token-level failure details)

## Invalid Token Cleanup
On non-dry-run sends, tokens are deleted from Firestore when FCM returns:

- `messaging/invalid-registration-token`
- `messaging/registration-token-not-registered`

## Local Setup
From repo root:

1. `cd functions`
2. `npm install`
3. `npx firebase login`
4. `npx firebase use nexusbot-5edeb` (or your target project)
5. `npm run serve`

Set HTTP dispatch secret:

1. `cp .env.example .env`
2. Edit `.env` and set `SPX_PUSH_DISPATCH_KEY`

## Deploy
From `functions/` directory:

1. `npm install`
2. Ensure `.env` contains `SPX_PUSH_DISPATCH_KEY`
3. `npm run deploy`

or from repo root:

- `npx firebase deploy --only functions`

## Example Callable Data
```json
{
  "userId": "<firebase_uid>",
  "opportunityId": "opp_123456",
  "title": "SPX Opportunity Found",
  "body": "SPX 0XXC05800000 · 7DTE",
  "dryRun": false
}
```

## Example HTTP Request
```bash
curl -X POST "https://us-central1-<project-id>.cloudfunctions.net/sendSpxOpportunityPushHttp" \
  -H "Content-Type: application/json" \
  -H "x-spx-dispatch-key: <SPX_PUSH_DISPATCH_KEY>" \
  -d '{
    "userId": "<firebase_uid>",
    "opportunityId": "opp_123456",
    "title": "SPX Opportunity Found",
    "body": "SPX 0XXC05800000 · 7DTE",
    "dryRun": false
  }'
```

Equivalent explicit payload:

```json
{
  "userId": "<firebase_uid>",
  "payload": "spx_opportunity:opp_123456",
  "title": "SPX Opportunity Found",
  "body": "SPX 0XXC05800000 · 7DTE"
}
```

## Helper Script
You can invoke the HTTP sender with:

- `scripts/send_spx_push_function.sh`

Example:

```bash
scripts/send_spx_push_function.sh \
  --project nexusbot-5edeb \
  --user <firebase_uid> \
  --secret <SPX_PUSH_DISPATCH_KEY> \
  --opportunity-id opp_123456 \
  --title "SPX Opportunity Found" \
  --body "SPX 0XXC05800000 · 7DTE"
```
