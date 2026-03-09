#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  configure_cloud_emr.sh [--config <PATH>] [--profile <NAME>] [--project <PROJECT_ID>] [--region <REGION>] [--service <SERVICE_NAME>] [--instance <SQL_INSTANCE>]

Optional:
  --database <DATABASE_NAME>
  --mysql-host <HOST>
  --manual-setup <yes|no>
  --secret-db-user <SECRET_NAME>
  --secret-db-pass <SECRET_NAME>
  --secret-db-root-pass <SECRET_NAME>
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROFILE=""
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
SERVICE="${SERVICE_NAME:-}"
INSTANCE="${SQL_INSTANCE:-}"
DATABASE="${MYSQL_DATABASE:-openemr}"
MYSQL_PORT_VAL="${MYSQL_PORT:-3306}"
MANUAL_SETUP_VALUE="${MANUAL_SETUP:-yes}"
MYSQL_HOST_VALUE="${MYSQL_HOST_RUNTIME:-${INSTALL_DB_TCP_HOST:-}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER:-openemr-db-user}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS:-openemr-db-pass}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --mysql-host) MYSQL_HOST_VALUE="$2"; shift 2 ;;
    --manual-setup) MANUAL_SETUP_VALUE="$2"; shift 2 ;;
    --secret-db-user) SECRET_DB_USER_NAME="$2"; shift 2 ;;
    --secret-db-pass) SECRET_DB_PASS_NAME="$2"; shift 2 ;;
    --secret-db-root-pass) SECRET_DB_ROOT_PASS_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE" "$PROFILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-}"
SERVICE="${SERVICE:-${SERVICE_NAME:-}}"
INSTANCE="${INSTANCE:-${SQL_INSTANCE:-}}"
DATABASE="${DATABASE:-${MYSQL_DATABASE:-openemr}}"
MYSQL_PORT_VAL="${MYSQL_PORT_VAL:-${MYSQL_PORT:-3306}}"
MANUAL_SETUP_VALUE="${MANUAL_SETUP_VALUE:-${MANUAL_SETUP:-yes}}"
MYSQL_HOST_VALUE="${MYSQL_HOST_VALUE:-${MYSQL_HOST_RUNTIME:-${INSTALL_DB_TCP_HOST:-}}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER_NAME:-${SECRET_DB_USER:-openemr-db-user}}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS_NAME:-${SECRET_DB_PASS:-openemr-db-pass}}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS_NAME:-${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}}"

if [[ -z "$PROJECT" || -z "$REGION" || -z "$SERVICE" || -z "$INSTANCE" ]]; then
  echo "Missing required values. Provide CLI flags or set PROJECT_ID, REGION, SERVICE_NAME, and SQL_INSTANCE in config."
  usage
  exit 1
fi

gcloud config set project "$PROJECT" >/dev/null

CONNECTION_NAME="$(gcloud sql instances describe "$INSTANCE" --format='value(connectionName)')"
if [[ -z "$CONNECTION_NAME" ]]; then
  echo "Unable to resolve Cloud SQL connection name for instance: $INSTANCE"
  exit 1
fi

if [[ -z "$MYSQL_HOST_VALUE" ]]; then
  MYSQL_HOST_VALUE="/cloudsql/${CONNECTION_NAME}"
fi

gcloud run services update "$SERVICE" \
  --project "$PROJECT" \
  --region "$REGION" \
  --add-cloudsql-instances "$CONNECTION_NAME" \
  --set-env-vars="OE_MODE=prod,MANUAL_SETUP=${MANUAL_SETUP_VALUE},MYSQL_HOST=${MYSQL_HOST_VALUE},MYSQL_PORT=${MYSQL_PORT_VAL},MYSQL_DATABASE=${DATABASE}" \
  --set-secrets="MYSQL_USER=${SECRET_DB_USER_NAME}:latest,MYSQL_PASS=${SECRET_DB_PASS_NAME}:latest,MYSQL_ROOT_PASS=${SECRET_DB_ROOT_PASS_NAME}:latest"

echo "Cloud Run service updated with Cloud SQL connector and Secret Manager bindings."
