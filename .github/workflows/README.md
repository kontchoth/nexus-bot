# GitHub Actions Deployment Inputs

These workflows deploy only the deployable unit whose path changed on a push to
`main`.

## Workflows

- `deploy-signal-sheet-service.yml`
  - deploys `micro-services/signal-sheet-service` to Cloud Run
  - also upserts the Cloud Scheduler jobs for that service
- `deploy-firebase-functions.yml`
  - deploys the Firebase Functions backend in `functions/`

## Required GitHub Secrets

- `GCP_WORKLOAD_IDENTITY_PROVIDER`
  - full Workload Identity Provider resource name
- `GCP_GITHUB_DEPLOYER_SERVICE_ACCOUNT`
  - service account email used by GitHub Actions

## Required GitHub Variables

- `GCP_PROJECT_ID`

## Recommended Variables For Signal Sheet Service

- `GCP_REGION`
- `SIGNAL_SHEET_SERVICE_NAME`
- `SIGNAL_SHEET_SCHEDULER_LOCATION`
- `SIGNAL_SHEET_RUNTIME_SERVICE_ACCOUNT`
- `SIGNAL_SHEET_SCHEDULER_SERVICE_ACCOUNT_EMAIL`
- `SIGNAL_SHEET_TRADIER_SECRET_NAME`
- `SIGNAL_SHEET_SYMBOL`
- `SIGNAL_SHEET_FIRESTORE_COLLECTION`
- `SIGNAL_ENGINE_VERSION`
- `SIGNAL_SHEET_SCHEMA_VERSION`
- `SIGNAL_SHEET_ARTIFACT_BUCKET`
- `SIGNAL_SHEET_ARTIFACT_PUBLIC_BASE_URL`
- `SIGNAL_SHEET_CREATE_SCHEDULER_JOBS`
- `SIGNAL_SHEET_CLOUD_RUN_MEMORY`
- `SIGNAL_SHEET_CLOUD_RUN_CPU`
- `SIGNAL_SHEET_CLOUD_RUN_TIMEOUT`

## Notes

- Cloud Run deploy granularity is one service at a time. For this repo, any change
  under `micro-services/signal-sheet-service/` redeploys only that service.
- Firebase Functions are currently deployed as one functions backend. If you want
  true per-function deploys later, split function ownership more explicitly so the
  workflow can safely map changed files to exported function names.
