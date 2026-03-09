#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  deploy_to_cloud_run.sh [--config <PATH>] [--profile <NAME>] [--project <PROJECT_ID>] [--region <REGION>] [--service <SERVICE_NAME>]

Optional:
  --image <IMAGE_URI>
  --database <DATABASE_NAME>
  --secret-db-user <SECRET_NAME>
  --secret-db-pass <SECRET_NAME>
  --secret-db-root-pass <SECRET_NAME>
  --manual-setup <yes|no>
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROFILE=""
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
SERVICE="${SERVICE_NAME:-}"
IMAGE="${CLOUD_RUN_IMAGE:-openemr/openemr:latest}"
DATABASE="${MYSQL_DATABASE:-openemr}"
MYSQL_PORT_VAL="${MYSQL_PORT:-3306}"
SECRET_DB_USER_NAME="${SECRET_DB_USER:-openemr-db-user}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS:-openemr-db-pass}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}"
MANUAL_SETUP_VALUE="${MANUAL_SETUP:-yes}"
ALLOW_UNAUTH="${ALLOW_UNAUTHENTICATED:-yes}"
INSTALL_DB_HOST="${INSTALL_DB_TCP_HOST:-127.0.0.1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --secret-db-user) SECRET_DB_USER_NAME="$2"; shift 2 ;;
    --secret-db-pass) SECRET_DB_PASS_NAME="$2"; shift 2 ;;
    --secret-db-root-pass) SECRET_DB_ROOT_PASS_NAME="$2"; shift 2 ;;
    --manual-setup) MANUAL_SETUP_VALUE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE" "$PROFILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-}"
SERVICE="${SERVICE:-${SERVICE_NAME:-}}"
IMAGE="${IMAGE:-${CLOUD_RUN_IMAGE:-openemr/openemr:latest}}"
DATABASE="${DATABASE:-${MYSQL_DATABASE:-openemr}}"
MYSQL_PORT_VAL="${MYSQL_PORT_VAL:-${MYSQL_PORT:-3306}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER_NAME:-${SECRET_DB_USER:-openemr-db-user}}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS_NAME:-${SECRET_DB_PASS:-openemr-db-pass}}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS_NAME:-${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}}"
MANUAL_SETUP_VALUE="${MANUAL_SETUP_VALUE:-${MANUAL_SETUP:-yes}}"
ALLOW_UNAUTH="${ALLOW_UNAUTH:-${ALLOW_UNAUTHENTICATED:-yes}}"
INSTALL_DB_HOST="${INSTALL_DB_HOST:-${INSTALL_DB_TCP_HOST:-127.0.0.1}}"

if [[ -z "$PROJECT" || -z "$REGION" || -z "$SERVICE" ]]; then
  echo "Missing required values. Provide CLI flags or set PROJECT_ID, REGION, and SERVICE_NAME in config."
  usage
  exit 1
fi

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable run.googleapis.com artifactregistry.googleapis.com >/dev/null

DEPLOY_ARGS=(
  --image "$IMAGE"
  --region "$REGION"
  --platform managed
  --set-env-vars "OE_MODE=prod,MANUAL_SETUP=${MANUAL_SETUP_VALUE},MYSQL_HOST=${INSTALL_DB_HOST},MYSQL_PORT=${MYSQL_PORT_VAL},MYSQL_DATABASE=${DATABASE}"
  --set-secrets "MYSQL_USER=${SECRET_DB_USER_NAME}:latest,MYSQL_PASS=${SECRET_DB_PASS_NAME}:latest,MYSQL_ROOT_PASS=${SECRET_DB_ROOT_PASS_NAME}:latest"
)

if is_yes "$ALLOW_UNAUTH"; then
  DEPLOY_ARGS+=(--allow-unauthenticated)
else
  DEPLOY_ARGS+=(--no-allow-unauthenticated)
fi

gcloud run deploy "$SERVICE" \
  "${DEPLOY_ARGS[@]}"

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')"
echo "Cloud Run deployed: ${URL}"
