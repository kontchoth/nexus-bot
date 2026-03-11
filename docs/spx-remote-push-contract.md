# SPX Remote Push Contract

## Scope
This contract defines how server-side senders should target NexusBot users with SPX opportunity push notifications, including payload conventions that map to in-app deep links.

## Device Token Registry
The mobile app registers FCM tokens in Firestore:

- Collection path: `users/{userId}/push_tokens/{token}`
- Fields:
  - `token` (string)
  - `alertsEnabled` (bool)
  - `platform` (`android|ios|macos|web|windows|linux|fuchsia`)
  - `createdAt` (server timestamp)
  - `updatedAt` (server timestamp)

Server senders should:

1. Read tokens under `users/{userId}/push_tokens`.
2. Filter to `alertsEnabled == true`.
3. Send one message per token.
4. Remove or disable invalid tokens based on FCM error responses.

## Payload Contract
The app supports two SPX routing payloads:

- `spx_opportunities`
  - opens SPX Activity > Opportunities list
- `spx_opportunity:{opportunityId}`
  - opens SPX Activity > Opportunities and focuses the specific opportunity context

Message fields (FCM `data`) accepted by app:

- `payload` (preferred)
- `opportunityId` (fallback: app derives `payload = spx_opportunity:{opportunityId}`)
- `target=spx_opportunities` (fallback list route)
- `title` (optional fallback for foreground rendering)
- `body` (optional fallback for foreground rendering)

## FCM HTTP v1 Example (Opportunity-Specific)
```json
{
  "message": {
    "token": "<DEVICE_FCM_TOKEN>",
    "notification": {
      "title": "SPX Opportunity Found",
      "body": "SPX 0XXC05800000 · 7DTE"
    },
    "data": {
      "payload": "spx_opportunity:opp_123456",
      "opportunityId": "opp_123456",
      "title": "SPX Opportunity Found",
      "body": "SPX 0XXC05800000 · 7DTE"
    }
  }
}
```

## FCM HTTP v1 Example (List Route)
```json
{
  "message": {
    "token": "<DEVICE_FCM_TOKEN>",
    "notification": {
      "title": "SPX Opportunities",
      "body": "New opportunities are waiting for review."
    },
    "data": {
      "payload": "spx_opportunities",
      "target": "spx_opportunities",
      "title": "SPX Opportunities",
      "body": "New opportunities are waiting for review."
    }
  }
}
```

## Local Test Sender
Use:

- Script: `scripts/send_test_spx_push.sh`
- It sends FCM HTTP v1 requests with either list payload or opportunity payload.

Required inputs:

- Firebase project id
- Device FCM token
- OAuth bearer token for `https://www.googleapis.com/auth/firebase.messaging`

## Backend Recommendations

1. Sign each outbound send with service-account credentials.
2. Include `payload` explicitly (avoid relying only on title matching).
3. Use `opportunityId` whenever possible for deterministic deep links.
4. Log message id, token, and opportunity id for delivery audit.
5. Retry transient errors with exponential backoff; prune permanently invalid tokens.

## In-Repo Sender Scaffolding
This repo includes Firebase Cloud Functions sender scaffolding:

- `functions/index.js`
  - `sendSpxOpportunityPush` (callable)
  - `sendSpxOpportunityPushHttp` (HTTP + secret auth)
- HTTP auth key env var: `SPX_PUSH_DISPATCH_KEY` (`functions/.env`)
- helper docs: `docs/spx-cloud-function-sender.md`
- helper invoke script: `scripts/send_spx_push_function.sh`
