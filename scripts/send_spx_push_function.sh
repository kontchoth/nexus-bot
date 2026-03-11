#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID=""
REGION="us-central1"
USER_ID=""
SECRET=""
PAYLOAD=""
OPPORTUNITY_ID=""
TARGET=""
TITLE="SPX Opportunity Found"
BODY="New SPX opportunity is available."
DRY_RUN="false"
PLATFORM=""

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") \
    --project <project-id> \
    --user <firebase-uid> \
    --secret <dispatch-secret> \
    [--region <region>] \
    [--payload spx_opportunities|spx_opportunity:<id>] \
    [--opportunity-id <id>] \
    [--target spx_opportunities] \
    [--title <title>] \
    [--body <body>] \
    [--dry-run true|false] \
    [--platform android|ios|macos|web|windows|linux|fuchsia]

Notes:
  - You must provide one of: --payload, --opportunity-id, or --target.
  - Endpoint called: https://<region>-<project>.cloudfunctions.net/sendSpxOpportunityPushHttp
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ID="$2"; shift 2 ;;
    --region)
      REGION="$2"; shift 2 ;;
    --user)
      USER_ID="$2"; shift 2 ;;
    --secret)
      SECRET="$2"; shift 2 ;;
    --payload)
      PAYLOAD="$2"; shift 2 ;;
    --opportunity-id)
      OPPORTUNITY_ID="$2"; shift 2 ;;
    --target)
      TARGET="$2"; shift 2 ;;
    --title)
      TITLE="$2"; shift 2 ;;
    --body)
      BODY="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN="$2"; shift 2 ;;
    --platform)
      PLATFORM="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "$PROJECT_ID" || -z "$USER_ID" || -z "$SECRET" ]]; then
  echo "Error: --project, --user, and --secret are required." >&2
  usage
  exit 1
fi

if [[ -z "$PAYLOAD" && -z "$OPPORTUNITY_ID" && -z "$TARGET" ]]; then
  echo "Error: provide one of --payload, --opportunity-id, or --target." >&2
  usage
  exit 1
fi

if [[ "$DRY_RUN" != "true" && "$DRY_RUN" != "false" ]]; then
  echo "Error: --dry-run must be true or false." >&2
  exit 1
fi

URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/sendSpxOpportunityPushHttp"

json_escape() {
  node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"
}

PAYLOAD_JSON=""
if [[ -n "$PAYLOAD" ]]; then
  PAYLOAD_JSON=",\"payload\":$(json_escape "$PAYLOAD")"
fi

OPP_JSON=""
if [[ -n "$OPPORTUNITY_ID" ]]; then
  OPP_JSON=",\"opportunityId\":$(json_escape "$OPPORTUNITY_ID")"
fi

TARGET_JSON=""
if [[ -n "$TARGET" ]]; then
  TARGET_JSON=",\"target\":$(json_escape "$TARGET")"
fi

PLATFORM_JSON=""
if [[ -n "$PLATFORM" ]]; then
  PLATFORM_JSON=",\"platform\":$(json_escape "$PLATFORM")"
fi

REQUEST_BODY="{\"userId\":$(json_escape "$USER_ID"),\"title\":$(json_escape "$TITLE"),\"body\":$(json_escape "$BODY"),\"dryRun\":$DRY_RUN${PAYLOAD_JSON}${OPP_JSON}${TARGET_JSON}${PLATFORM_JSON}}"

curl -sS -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "x-spx-dispatch-key: $SECRET" \
  --data "$REQUEST_BODY"

echo
