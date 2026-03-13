#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE_DIR="$ROOT_DIR/micro-services/signal-sheet-service"

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-signal-sheet-service}"
SCHEDULER_LOCATION="${SCHEDULER_LOCATION:-$REGION}"
RUNTIME_SERVICE_ACCOUNT="${RUNTIME_SERVICE_ACCOUNT:-}"
SCHEDULER_SERVICE_ACCOUNT_EMAIL="${SCHEDULER_SERVICE_ACCOUNT_EMAIL:-}"
TRADIER_SECRET_NAME="${TRADIER_SECRET_NAME:-}"
ENVIRONMENT="${ENVIRONMENT:-production}"
SIGNAL_SYMBOL="${SIGNAL_SYMBOL:-SPX}"
FIRESTORE_COLLECTION="${FIRESTORE_COLLECTION:-playbooks}"
SIGNAL_ENGINE_VERSION="${SIGNAL_ENGINE_VERSION:-v1}"
SIGNAL_SHEET_SCHEMA_VERSION="${SIGNAL_SHEET_SCHEMA_VERSION:-2}"
SIGNAL_SHEET_ARTIFACT_BUCKET="${SIGNAL_SHEET_ARTIFACT_BUCKET:-}"
SIGNAL_SHEET_ARTIFACT_PUBLIC_BASE_URL="${SIGNAL_SHEET_ARTIFACT_PUBLIC_BASE_URL:-}"
CREATE_SCHEDULER_JOBS="${CREATE_SCHEDULER_JOBS:-true}"
CLOUD_RUN_MEMORY="${CLOUD_RUN_MEMORY:-1Gi}"
CLOUD_RUN_CPU="${CLOUD_RUN_CPU:-1}"
CLOUD_RUN_TIMEOUT="${CLOUD_RUN_TIMEOUT:-60s}"

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env var: $name" >&2
    exit 1
  fi
}

bool_is_true() {
  [[ "${1,,}" == "true" ]]
}

join_env_vars() {
  local IFS=,
  echo "$*"
}

upsert_http_job() {
  local job_name="$1"
  local schedule="$2"
  local uri="$3"
  local description="$4"
  local body="${5:-}"

  local cmd=()
  if gcloud scheduler jobs describe "$job_name" \
    --project "$PROJECT_ID" \
    --location "$SCHEDULER_LOCATION" >/dev/null 2>&1; then
    cmd=(gcloud scheduler jobs update http "$job_name")
  else
    cmd=(gcloud scheduler jobs create http "$job_name")
  fi

  cmd+=(
    --project "$PROJECT_ID"
    --location "$SCHEDULER_LOCATION"
    --schedule "$schedule"
    --time-zone "America/New_York"
    --uri "$uri"
    --http-method POST
    --headers "Content-Type=application/json"
    --attempt-deadline "60s"
    --description "$description"
    --oidc-service-account-email "$SCHEDULER_SERVICE_ACCOUNT_EMAIL"
    --oidc-token-audience "$SERVICE_URL"
  )

  if [[ -n "$body" ]]; then
    cmd+=(--message-body "$body")
  fi

  "${cmd[@]}"
}

require_var PROJECT_ID

if bool_is_true "$CREATE_SCHEDULER_JOBS"; then
  require_var SCHEDULER_SERVICE_ACCOUNT_EMAIL
fi

echo "Deploying Cloud Run service from: $SERVICE_DIR"

common_env_vars=(
  "ENVIRONMENT=$ENVIRONMENT"
  "SIGNAL_SYMBOL=$SIGNAL_SYMBOL"
  "FIRESTORE_COLLECTION=$FIRESTORE_COLLECTION"
  "SIGNAL_ENGINE_VERSION=$SIGNAL_ENGINE_VERSION"
  "SIGNAL_SHEET_SCHEMA_VERSION=$SIGNAL_SHEET_SCHEMA_VERSION"
)

if [[ -n "$SCHEDULER_SERVICE_ACCOUNT_EMAIL" ]]; then
  common_env_vars+=("SCHEDULER_SERVICE_ACCOUNT_EMAIL=$SCHEDULER_SERVICE_ACCOUNT_EMAIL")
fi
if [[ -n "$SIGNAL_SHEET_ARTIFACT_BUCKET" ]]; then
  common_env_vars+=("SIGNAL_SHEET_ARTIFACT_BUCKET=$SIGNAL_SHEET_ARTIFACT_BUCKET")
fi
if [[ -n "$SIGNAL_SHEET_ARTIFACT_PUBLIC_BASE_URL" ]]; then
  common_env_vars+=("SIGNAL_SHEET_ARTIFACT_PUBLIC_BASE_URL=$SIGNAL_SHEET_ARTIFACT_PUBLIC_BASE_URL")
fi

deploy_cmd=(
  gcloud run deploy "$SERVICE_NAME"
  --project "$PROJECT_ID"
  --region "$REGION"
  --source "$SERVICE_DIR"
  --cpu "$CLOUD_RUN_CPU"
  --memory "$CLOUD_RUN_MEMORY"
  --timeout "$CLOUD_RUN_TIMEOUT"
  --no-allow-unauthenticated
  --set-env-vars "$(join_env_vars "${common_env_vars[@]}")"
)

if [[ -n "$RUNTIME_SERVICE_ACCOUNT" ]]; then
  deploy_cmd+=(--service-account "$RUNTIME_SERVICE_ACCOUNT")
fi
if [[ -n "$TRADIER_SECRET_NAME" ]]; then
  deploy_cmd+=(--set-secrets "TRADIER_API_KEY=${TRADIER_SECRET_NAME}:latest")
fi

"${deploy_cmd[@]}"

SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --format 'value(status.url)')"

if [[ -z "$SERVICE_URL" ]]; then
  echo "Failed to resolve Cloud Run service URL for $SERVICE_NAME" >&2
  exit 1
fi

echo "Resolved service URL: $SERVICE_URL"

update_env_vars=("${common_env_vars[@]}" "OIDC_AUDIENCE=$SERVICE_URL")
gcloud run services update "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --update-env-vars "$(join_env_vars "${update_env_vars[@]}")" >/dev/null

if ! bool_is_true "$CREATE_SCHEDULER_JOBS"; then
  echo "Skipping Cloud Scheduler job management because CREATE_SCHEDULER_JOBS=$CREATE_SCHEDULER_JOBS"
  exit 0
fi

echo "Upserting Cloud Scheduler jobs in $SCHEDULER_LOCATION"

upsert_http_job "signal-sheet-generate" "20 9 * * 1-5" \
  "$SERVICE_URL/generate" \
  "Generate premarket signal-sheet playbook"

upsert_http_job "signal-sheet-render-premarket" "21 9 * * 1-5" \
  "$SERVICE_URL/render-snapshot" \
  "Render premarket signal-sheet snapshot" \
  '{"phase":"premarket"}'

upsert_http_job "signal-sheet-resolve-open" "30 9 * * 1-5" \
  "$SERVICE_URL/resolve" \
  "Resolve opening algorithm state"

upsert_http_job "signal-sheet-lock-minute14" "44 9 * * 1-5" \
  "$SERVICE_URL/lock-minute14" \
  "Lock minute-14 reference levels"

upsert_http_job "signal-sheet-render-locked" "45 9 * * 1-5" \
  "$SERVICE_URL/render-snapshot" \
  "Render locked signal-sheet snapshot" \
  '{"phase":"locked"}'

upsert_http_job "signal-sheet-refresh-1" "35,40,45,50,55 9 * * 1-5" \
  "$SERVICE_URL/refresh" \
  "Refresh opening-window live signal-sheet state"

upsert_http_job "signal-sheet-refresh-2" "0,5 10 * * 1-5" \
  "$SERVICE_URL/refresh" \
  "Refresh late opening-window live signal-sheet state"

upsert_http_job "signal-sheet-render-final" "6 10 * * 1-5" \
  "$SERVICE_URL/render-snapshot" \
  "Render final early-session signal-sheet snapshot" \
  '{"phase":"final"}'

echo "Deployment complete."
echo "Cloud Run URL: $SERVICE_URL"
