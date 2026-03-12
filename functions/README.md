# NexusBot Cloud Functions

## Available Functions
- `sendSpxOpportunityPush` (callable)
- `sendSpxOpportunityPushHttp` (HTTP, secret-authenticated)

Reads `users/{userId}/push_tokens` (alerts enabled only) and sends SPX opportunity notifications with payloads:

- `spx_opportunities`
- `spx_opportunity:{opportunityId}`

See `../docs/spx-cloud-function-sender.md` for full contract and deploy steps.

Set `SPX_PUSH_DISPATCH_KEY` in `functions/.env` before deploying HTTP sender.

## Spark Plan Fallback
If Cloud Functions deploy is blocked by plan constraints, use local/CI dispatcher:

- `npm run dispatch-spx-push -- --user <firebase_uid> --opportunity-id <id> --service-account <path-to-service-account.json> --project <project-id>`
