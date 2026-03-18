#!/bin/bash
# NexusBot — signal-sheet-service deploy to Cloud Run
# Prerequisites: gcloud CLI authenticated, Docker, project configured

set -euo pipefail

PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project)}"
REGION="${REGION:-us-central1}"
SERVICE="signal-sheet-service"
IMAGE="gcr.io/${PROJECT}/${SERVICE}"
ENV="${1:-prod}"

echo "══════════════════════════════════════════"
echo " NexusBot deploy  env=${ENV}  project=${PROJECT}"
echo "══════════════════════════════════════════"

# ── 0. Enable required APIs (idempotent) ──────────────────────────────────────
echo "→ Enabling required GCP APIs..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  --project="$PROJECT" \
  --quiet

# ── 1. One-time: store secrets in Secret Manager ──────────────────────────────
if ! gcloud secrets describe tradier-api-key --project="$PROJECT" &>/dev/null; then
  echo "Secret tradier-api-key not found. Creating..."
  if [[ -z "${TRADIER_API_KEY:-}" ]]; then
    echo "ERROR: TRADIER_API_KEY env var must be set to create the secret." >&2
    exit 1
  fi
  echo -n "$TRADIER_API_KEY" | \
    gcloud secrets create tradier-api-key \
      --data-file=- \
      --project="$PROJECT"
fi

if ! gcloud secrets describe replay-secret --project="$PROJECT" &>/dev/null; then
  echo "Secret replay-secret not found. Creating..."
  # Generate a random 32-char hex secret if REPLAY_SECRET env var not provided
  _replay_val="${REPLAY_SECRET:-$(openssl rand -hex 16)}"
  echo -n "$_replay_val" | \
    gcloud secrets create replay-secret \
      --data-file=- \
      --project="$PROJECT"
  echo "  → replay-secret created. Value: $_replay_val (save this — needed to call /replay)"
fi

# Grant the default Cloud Run compute SA access to both secrets
_COMPUTE_SA="${PROJECT_NUMBER:-$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')}-compute@developer.gserviceaccount.com"
for secret in tradier-api-key replay-secret; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --project="$PROJECT" \
    --member="serviceAccount:${_COMPUTE_SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet
done

# ── 2. Build and push Docker image ────────────────────────────────────────────
echo "→ Building ${IMAGE}:${ENV}..."
gcloud builds submit \
  --tag "${IMAGE}:${ENV}" \
  --project "$PROJECT" \
  .

# ── 3. Deploy Cloud Run service ───────────────────────────────────────────────
echo "→ Deploying Cloud Run service ${SERVICE}..."
gcloud run deploy "$SERVICE" \
  --image "${IMAGE}:${ENV}" \
  --region "$REGION" \
  --project "$PROJECT" \
  --platform managed \
  --no-allow-unauthenticated \
  --timeout 60s \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 3 \
  --set-env-vars "\
SERVICE_URL=$(gcloud run services describe $SERVICE --region=$REGION --project=$PROJECT --format='value(status.url)' 2>/dev/null || echo ''),\
SCHEDULER_SA=signal-sheet-scheduler@${PROJECT}.iam.gserviceaccount.com,\
SCREENSHOT_BUCKET=nexus-bot-screenshots-${PROJECT},\
LOG_LEVEL=INFO" \
  --set-secrets "TRADIER_API_KEY=tradier-api-key:latest,REPLAY_SECRET=replay-secret:latest"

# ── 4. Capture service URL ────────────────────────────────────────────────────
SERVICE_URL=$(gcloud run services describe "$SERVICE" \
  --region="$REGION" --project="$PROJECT" \
  --format="value(status.url)")

echo ""
echo "→ Updating SERVICE_URL env var now that URL is known..."
gcloud run services update "$SERVICE" \
  --region "$REGION" \
  --project "$PROJECT" \
  --update-env-vars "SERVICE_URL=${SERVICE_URL}"

# ── 5. Create / update Cloud Scheduler jobs ───────────────────────────────────
echo "→ Applying Cloud Scheduler jobs..."

SA="signal-sheet-scheduler@${PROJECT}.iam.gserviceaccount.com"

# Create the scheduler SA if it doesn't exist
if ! gcloud iam service-accounts describe "$SA" --project="$PROJECT" &>/dev/null; then
  gcloud iam service-accounts create signal-sheet-scheduler \
    --display-name="Signal Sheet Scheduler" \
    --project="$PROJECT"
  gcloud run services add-iam-policy-binding "$SERVICE" \
    --region="$REGION" \
    --project="$PROJECT" \
    --member="serviceAccount:${SA}" \
    --role="roles/run.invoker"
fi

_upsert_job() {
  local name="$1" schedule="$2" path="$3" body="${4:-{}}"
  if gcloud scheduler jobs describe "$name" --location="$REGION" --project="$PROJECT" &>/dev/null; then
    gcloud scheduler jobs update http "$name" \
      --location="$REGION" --project="$PROJECT" \
      --schedule="$schedule" \
      --uri="${SERVICE_URL}${path}" \
      --http-method=POST \
      --oidc-service-account-email="$SA" \
      --oidc-token-audience="$SERVICE_URL" \
      --time-zone="America/New_York" \
      --message-body="$body" \
      --update-headers "Content-Type=application/json"
  else
    gcloud scheduler jobs create http "$name" \
      --location="$REGION" --project="$PROJECT" \
      --schedule="$schedule" \
      --uri="${SERVICE_URL}${path}" \
      --http-method=POST \
      --oidc-service-account-email="$SA" \
      --oidc-token-audience="$SERVICE_URL" \
      --time-zone="America/New_York" \
      --message-body="$body" \
      --headers "Content-Type=application/json"
  fi
}

# All 8 jobs from spec §8 — timezone: America/New_York
_upsert_job "signal-sheet-generate"          "20 9 * * 1-5"        "/generate"
_upsert_job "signal-sheet-render-premarket"  "21 9 * * 1-5"        "/render-snapshot"  '{"phase":"premarket"}'
_upsert_job "signal-sheet-resolve-open"      "30 9 * * 1-5"        "/resolve"
_upsert_job "signal-sheet-lock-minute14"     "44 9 * * 1-5"        "/lock-minute14"
_upsert_job "signal-sheet-render-locked"     "45 9 * * 1-5"        "/render-snapshot"  '{"phase":"locked"}'
_upsert_job "signal-sheet-refresh-1"         "35,40,45,50,55 9 * * 1-5"  "/refresh"
_upsert_job "signal-sheet-refresh-2"         "0,5 10 * * 1-5"      "/refresh"
_upsert_job "signal-sheet-render-final"      "6 10 * * 1-5"        "/render-snapshot"  '{"phase":"final"}'

echo ""
echo "══════════════════════════════════════════"
echo " Deploy complete ✅"
echo " Service URL: ${SERVICE_URL}"
echo ""
echo "Smoke test:"
echo "  curl -s ${SERVICE_URL}/health"
echo "══════════════════════════════════════════"
