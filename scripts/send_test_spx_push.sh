#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/send_test_spx_push.sh \
    --project <firebase-project-id> \
    --token <device-fcm-token> \
    --access-token <oauth-access-token> \
    [--mode opportunity|list] \
    [--opportunity-id <id>] \
    [--title <title>] \
    [--body <body>]

Notes:
  - --mode defaults to "opportunity".
  - For --mode opportunity, --opportunity-id is required.
  - Access token must include scope:
      https://www.googleapis.com/auth/firebase.messaging

Example:
  scripts/send_test_spx_push.sh \
    --project my-firebase-project \
    --token eXampleDeviceToken \
    --access-token "$(gcloud auth print-access-token)" \
    --mode opportunity \
    --opportunity-id opp_123456
EOF
}

PROJECT_ID=""
FCM_TOKEN=""
ACCESS_TOKEN=""
MODE="opportunity"
OPPORTUNITY_ID=""
TITLE=""
BODY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ID="${2:-}"
      shift 2
      ;;
    --token)
      FCM_TOKEN="${2:-}"
      shift 2
      ;;
    --access-token)
      ACCESS_TOKEN="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --opportunity-id)
      OPPORTUNITY_ID="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --body)
      BODY="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ID" || -z "$FCM_TOKEN" || -z "$ACCESS_TOKEN" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ "$MODE" != "opportunity" && "$MODE" != "list" ]]; then
  echo "--mode must be 'opportunity' or 'list'." >&2
  exit 1
fi

if [[ "$MODE" == "opportunity" && -z "$OPPORTUNITY_ID" ]]; then
  echo "--opportunity-id is required when --mode opportunity." >&2
  exit 1
fi

if [[ -z "$TITLE" ]]; then
  if [[ "$MODE" == "opportunity" ]]; then
    TITLE="SPX Opportunity Found"
  else
    TITLE="SPX Opportunities"
  fi
fi

if [[ -z "$BODY" ]]; then
  if [[ "$MODE" == "opportunity" ]]; then
    BODY="Opportunity ${OPPORTUNITY_ID} is ready for review."
  else
    BODY="New opportunities are waiting for review."
  fi
fi

if [[ "$MODE" == "opportunity" ]]; then
  PAYLOAD="spx_opportunity:${OPPORTUNITY_ID}"
  EXTRA_DATA=",\"opportunityId\":\"${OPPORTUNITY_ID}\""
else
  PAYLOAD="spx_opportunities"
  EXTRA_DATA=",\"target\":\"spx_opportunities\""
fi

REQUEST_JSON=$(cat <<EOF
{
  "message": {
    "token": "${FCM_TOKEN}",
    "notification": {
      "title": "${TITLE}",
      "body": "${BODY}"
    },
    "data": {
      "payload": "${PAYLOAD}",
      "title": "${TITLE}",
      "body": "${BODY}"${EXTRA_DATA}
    }
  }
}
EOF
)

echo "Sending test push:"
echo "  project: ${PROJECT_ID}"
echo "  mode:    ${MODE}"
echo "  payload: ${PAYLOAD}"

curl --fail --show-error --silent \
  -X POST \
  "https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json; charset=UTF-8" \
  -d "${REQUEST_JSON}" | sed 's/^/FCM response: /'

echo
echo "Done."
