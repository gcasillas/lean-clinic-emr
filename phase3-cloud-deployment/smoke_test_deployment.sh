#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  smoke_test_deployment.sh [--config <PATH>] [--project <PROJECT_ID>] [--region <REGION>] [--service <SERVICE_NAME>] [--instance <SQL_INSTANCE>]

Checks:
  1) Cloud SQL instance state
  2) Cloud Run latest revision readiness
  3) Installer mode env state
  4) Basic API endpoint response
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
SERVICE="${SERVICE_NAME:-}"
INSTANCE="${SQL_INSTANCE:-}"
API_ENDPOINT="${OPENEMR_SMOKE_ENDPOINT:-/apis/default/api/}"
SECRET_DB_USER_NAME="${SECRET_DB_USER:-openemr-db-user}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS:-openemr-db-pass}"
MYSQL_PORT_VAL="${MYSQL_PORT:-3306}"
INSTALL_DB_HOST="${INSTALL_DB_TCP_HOST:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --api-endpoint) API_ENDPOINT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-}"
SERVICE="${SERVICE:-${SERVICE_NAME:-}}"
INSTANCE="${INSTANCE:-${SQL_INSTANCE:-}}"
API_ENDPOINT="${API_ENDPOINT:-${OPENEMR_SMOKE_ENDPOINT:-/apis/default/api/}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER_NAME:-${SECRET_DB_USER:-openemr-db-user}}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS_NAME:-${SECRET_DB_PASS:-openemr-db-pass}}"
MYSQL_PORT_VAL="${MYSQL_PORT_VAL:-${MYSQL_PORT:-3306}}"
INSTALL_DB_HOST="${INSTALL_DB_HOST:-${INSTALL_DB_TCP_HOST:-}}"

require_var PROJECT
require_var REGION
require_var SERVICE
require_var INSTANCE

gcloud config set project "$PROJECT" >/dev/null

service_json="$(gcloud run services describe "$SERVICE" --region "$REGION" --format=json)"

echo "[1/4] Cloud SQL instance status"
sql_state="$(gcloud sql instances describe "$INSTANCE" --format='value(state)')"
echo "Cloud SQL state: ${sql_state}"
if [[ "$sql_state" != "RUNNABLE" ]]; then
  echo "Cloud SQL instance is not RUNNABLE"
  exit 1
fi

echo "[2/4] Cloud Run latest revision readiness"
latest_ready_revision="$(printf '%s' "$service_json" | jq -r '.status.latestReadyRevisionName // empty')"
latest_created_revision="$(printf '%s' "$service_json" | jq -r '.status.latestCreatedRevisionName // empty')"
echo "Latest ready revision: ${latest_ready_revision}"
echo "Latest created revision: ${latest_created_revision}"
if [[ -z "$latest_ready_revision" || "$latest_ready_revision" != "$latest_created_revision" ]]; then
  echo "Cloud Run service is not ready"
  exit 1
fi

connection_name="$(gcloud sql instances describe "$INSTANCE" --format='value(connectionName)')"
attached_connection="$(printf '%s' "$service_json" | jq -r '.spec.template.metadata.annotations["run.googleapis.com/cloudsql-instances"] // empty')"
if [[ -n "$connection_name" && "$attached_connection" != *"$connection_name"* ]]; then
  echo "Cloud Run service is missing expected Cloud SQL connector binding: ${connection_name}"
  exit 1
fi

echo "[3/4] Installer mode state"
manual_setup="$(printf '%s' "$service_json" | jq -r '.spec.template.spec.containers[0].env[]? | select(.name == "MANUAL_SETUP") | .value' | head -n 1)"
if [[ -z "$manual_setup" ]]; then
  echo "MANUAL_SETUP not explicitly set on service"
else
  echo "MANUAL_SETUP=${manual_setup}"
fi

echo "[4/4] Basic API smoke test"
service_url="$(printf '%s' "$service_json" | jq -r '.status.url // empty')"
http_code="$(curl -sS -o /dev/null -w "%{http_code}" "${service_url}${API_ENDPOINT}")"
echo "GET ${service_url}${API_ENDPOINT} -> HTTP ${http_code}"

if [[ "$http_code" -eq 200 || "$http_code" -eq 302 || "$http_code" -eq 401 || "$http_code" -eq 403 ]]; then
  echo "Smoke test passed."
elif [[ "$http_code" -eq 500 && "$API_ENDPOINT" == "/apis/default/api/" ]]; then
  echo "Smoke test warning: API returned 500, which can be expected before OpenEMR installer completion."
else
  echo "Unexpected API status code: ${http_code}"
  exit 1
fi

if [[ -n "$INSTALL_DB_HOST" && -x "$(command -v mysqladmin || true)" ]]; then
  echo "Optional DB TCP reachability check"
  db_user="$(gcloud secrets versions access latest --secret="$SECRET_DB_USER_NAME")"
  db_pass="$(gcloud secrets versions access latest --secret="$SECRET_DB_PASS_NAME")"
  if mysqladmin ping -h "$INSTALL_DB_HOST" -P "$MYSQL_PORT_VAL" -u"$db_user" "-p$db_pass" --connect-timeout=5 --silent; then
    echo "DB TCP host reachable: ${INSTALL_DB_HOST}:${MYSQL_PORT_VAL}"
  else
    echo "DB TCP reachability check failed for ${INSTALL_DB_HOST}:${MYSQL_PORT_VAL}"
    exit 1
  fi
fi
