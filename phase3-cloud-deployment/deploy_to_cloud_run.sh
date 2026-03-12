#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  deploy_to_cloud_run.sh [--config <PATH>] [--project <PROJECT_ID>] [--region <REGION>] [--service <SERVICE_NAME>]

Optional:
  --image <IMAGE_URI>
  --port <CONTAINER_PORT>
  --database <DATABASE_NAME>
  --secret-db-user <SECRET_NAME>
  --secret-db-pass <SECRET_NAME>
  --secret-db-root-pass <SECRET_NAME>
  --secret-sqlconf <SECRET_NAME>
  --use-sqlconf-secret-mount <yes|no>
  --service-account <SERVICE_ACCOUNT_EMAIL>
  --manual-setup <yes|no>
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
SERVICE="${SERVICE_NAME:-}"
IMAGE="${CLOUD_RUN_IMAGE:-openemr/openemr:latest}"
CONTAINER_PORT="${CLOUD_RUN_PORT:-80}"
DATABASE="${MYSQL_DATABASE:-openemr}"
MYSQL_PORT_VAL="${MYSQL_PORT:-3306}"
SECRET_DB_USER_NAME="${SECRET_DB_USER:-openemr-db-user}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS:-openemr-db-pass}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}"
SECRET_SQLCONF_NAME="${SECRET_SQLCONF:-}"
USE_SQLCONF_SECRET_MOUNT_VALUE="${USE_SQLCONF_SECRET_MOUNT:-}"
SQLCONF_MOUNT_PATH_VALUE="${SQLCONF_MOUNT_PATH:-}"
SERVICE_ACCOUNT_VALUE="${CLOUD_RUN_SERVICE_ACCOUNT:-}"
MANUAL_SETUP_VALUE="${MANUAL_SETUP:-yes}"
ALLOW_UNAUTH="${ALLOW_UNAUTHENTICATED:-yes}"
INSTALL_DB_HOST="${INSTALL_DB_TCP_HOST:-127.0.0.1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --port) CONTAINER_PORT="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --secret-db-user) SECRET_DB_USER_NAME="$2"; shift 2 ;;
    --secret-db-pass) SECRET_DB_PASS_NAME="$2"; shift 2 ;;
    --secret-db-root-pass) SECRET_DB_ROOT_PASS_NAME="$2"; shift 2 ;;
    --secret-sqlconf) SECRET_SQLCONF_NAME="$2"; shift 2 ;;
    --use-sqlconf-secret-mount) USE_SQLCONF_SECRET_MOUNT_VALUE="$2"; shift 2 ;;
    --service-account) SERVICE_ACCOUNT_VALUE="$2"; shift 2 ;;
    --manual-setup) MANUAL_SETUP_VALUE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-}"
SERVICE="${SERVICE:-${SERVICE_NAME:-}}"
IMAGE="${IMAGE:-${CLOUD_RUN_IMAGE:-openemr/openemr:latest}}"
CONTAINER_PORT="${CONTAINER_PORT:-${CLOUD_RUN_PORT:-80}}"
DATABASE="${DATABASE:-${MYSQL_DATABASE:-openemr}}"
MYSQL_PORT_VAL="${MYSQL_PORT_VAL:-${MYSQL_PORT:-3306}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER_NAME:-${SECRET_DB_USER:-openemr-db-user}}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS_NAME:-${SECRET_DB_PASS:-openemr-db-pass}}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS_NAME:-${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}}"
SECRET_SQLCONF_NAME="${SECRET_SQLCONF_NAME:-${SECRET_SQLCONF:-openemr-sqlconf}}"
USE_SQLCONF_SECRET_MOUNT_VALUE="${USE_SQLCONF_SECRET_MOUNT_VALUE:-${USE_SQLCONF_SECRET_MOUNT:-no}}"
SQLCONF_MOUNT_PATH_VALUE="${SQLCONF_MOUNT_PATH_VALUE:-${SQLCONF_MOUNT_PATH:-/var/www/localhost/htdocs/openemr/sites/default/sqlconf.php}}"
SERVICE_ACCOUNT_VALUE="${SERVICE_ACCOUNT_VALUE:-${CLOUD_RUN_SERVICE_ACCOUNT:-}}"
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

if [[ -z "$SERVICE_ACCOUNT_VALUE" ]]; then
  PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
  SERVICE_ACCOUNT_VALUE="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
fi

grant_secret_access() {
  local secret_name="$1"
  gcloud secrets add-iam-policy-binding "$secret_name" \
    --member="serviceAccount:${SERVICE_ACCOUNT_VALUE}" \
    --role="roles/secretmanager.secretAccessor" \
    >/dev/null
}

grant_secret_access "$SECRET_DB_USER_NAME"
grant_secret_access "$SECRET_DB_PASS_NAME"
grant_secret_access "$SECRET_DB_ROOT_PASS_NAME"

if is_yes "$USE_SQLCONF_SECRET_MOUNT_VALUE"; then
  if ! gcloud secrets describe "$SECRET_SQLCONF_NAME" >/dev/null 2>&1; then
    echo "Required sqlconf secret not found: ${SECRET_SQLCONF_NAME}" >&2
    echo "Run ./phase3-cloud-deployment/upsert_openemr_sqlconf_secret.sh --config ${CONFIG_FILE}" >&2
    exit 1
  fi
  grant_secret_access "$SECRET_SQLCONF_NAME"
fi

SET_SECRETS_VALUE="MYSQL_USER=${SECRET_DB_USER_NAME}:latest,MYSQL_PASS=${SECRET_DB_PASS_NAME}:latest,MYSQL_ROOT_PASS=${SECRET_DB_ROOT_PASS_NAME}:latest"
if is_yes "$USE_SQLCONF_SECRET_MOUNT_VALUE"; then
  SET_SECRETS_VALUE+=",${SQLCONF_MOUNT_PATH_VALUE}=${SECRET_SQLCONF_NAME}:latest"
fi

DEPLOY_ARGS=(
  --image "$IMAGE"
  --region "$REGION"
  --platform managed
  --port "$CONTAINER_PORT"
  --service-account "$SERVICE_ACCOUNT_VALUE"
  --set-env-vars "OE_MODE=prod,MANUAL_SETUP=${MANUAL_SETUP_VALUE},MYSQL_HOST=${INSTALL_DB_HOST},MYSQL_PORT=${MYSQL_PORT_VAL},MYSQL_DATABASE=${DATABASE}"
  --set-secrets "$SET_SECRETS_VALUE"
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
