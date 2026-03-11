# NexusBot Cloud Functions

## Available Functions
- `sendSpxOpportunityPush` (callable)
- `sendSpxOpportunityPushHttp` (HTTP, secret-authenticated)

Reads `users/{userId}/push_tokens` (alerts enabled only) and sends SPX opportunity notifications with payloads:

- `spx_opportunities`
- `spx_opportunity:{opportunityId}`

See `../docs/spx-cloud-function-sender.md` for full contract and deploy steps.

Set `SPX_PUSH_DISPATCH_KEY` in `functions/.env` before deploying HTTP sender.
