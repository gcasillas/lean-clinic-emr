#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  configure_cloud_emr.sh [--config <PATH>] [--project <PROJECT_ID>] [--region <REGION>] [--service <SERVICE_NAME>] [--instance <SQL_INSTANCE>]

Optional:
  --database <DATABASE_NAME>
  --mysql-host <HOST>
  --manual-setup <yes|no>
  --secret-db-user <SECRET_NAME>
  --secret-db-pass <SECRET_NAME>
  --secret-db-root-pass <SECRET_NAME>
  --secret-sqlconf <SECRET_NAME>
  --use-sqlconf-secret-mount <yes|no>
  --service-account <SERVICE_ACCOUNT_EMAIL>
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
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
SECRET_SQLCONF_NAME="${SECRET_SQLCONF:-}"
USE_SQLCONF_SECRET_MOUNT_VALUE="${USE_SQLCONF_SECRET_MOUNT:-}"
SQLCONF_MOUNT_PATH_VALUE="${SQLCONF_MOUNT_PATH:-}"
SERVICE_ACCOUNT_VALUE="${CLOUD_RUN_SERVICE_ACCOUNT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
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
    --secret-sqlconf) SECRET_SQLCONF_NAME="$2"; shift 2 ;;
    --use-sqlconf-secret-mount) USE_SQLCONF_SECRET_MOUNT_VALUE="$2"; shift 2 ;;
    --service-account) SERVICE_ACCOUNT_VALUE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
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
SECRET_SQLCONF_NAME="${SECRET_SQLCONF_NAME:-${SECRET_SQLCONF:-openemr-sqlconf}}"
USE_SQLCONF_SECRET_MOUNT_VALUE="${USE_SQLCONF_SECRET_MOUNT_VALUE:-${USE_SQLCONF_SECRET_MOUNT:-no}}"
SQLCONF_MOUNT_PATH_VALUE="${SQLCONF_MOUNT_PATH_VALUE:-${SQLCONF_MOUNT_PATH:-/var/www/localhost/htdocs/openemr/sites/default/sqlconf.php}}"
SERVICE_ACCOUNT_VALUE="${SERVICE_ACCOUNT_VALUE:-${CLOUD_RUN_SERVICE_ACCOUNT:-}}"

if [[ -z "$PROJECT" || -z "$REGION" || -z "$SERVICE" || -z "$INSTANCE" ]]; then
  echo "Missing required values. Provide CLI flags or set PROJECT_ID, REGION, SERVICE_NAME, and SQL_INSTANCE in config."
  usage
  exit 1
fi

gcloud config set project "$PROJECT" >/dev/null

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
  --service-account "$SERVICE_ACCOUNT_VALUE" \
  --add-cloudsql-instances "$CONNECTION_NAME" \
  --set-env-vars="OE_MODE=prod,MANUAL_SETUP=${MANUAL_SETUP_VALUE},MYSQL_HOST=${MYSQL_HOST_VALUE},MYSQL_PORT=${MYSQL_PORT_VAL},MYSQL_DATABASE=${DATABASE}" \
  --set-secrets="$SET_SECRETS_VALUE"

echo "Cloud Run service updated with Cloud SQL connector and Secret Manager bindings."
