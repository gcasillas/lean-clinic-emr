#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  setup_cloud_sql.sh [--config <PATH>] [--project <PROJECT_ID>] [--region <REGION>] [--instance <INSTANCE_NAME>]

Optional:
  --tier <DB_TIER>
  --database <DATABASE_NAME>
  --secret-db-user <SECRET_NAME>
  --secret-db-pass <SECRET_NAME>
  --secret-db-root-pass <SECRET_NAME>
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
INSTANCE="${SQL_INSTANCE:-}"
TIER="${CLOUD_SQL_TIER:-db-custom-1-3840}"
DATABASE="${MYSQL_DATABASE:-openemr}"
SECRET_DB_USER_NAME="${SECRET_DB_USER:-openemr-db-user}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS:-openemr-db-pass}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --secret-db-user) SECRET_DB_USER_NAME="$2"; shift 2 ;;
    --secret-db-pass) SECRET_DB_PASS_NAME="$2"; shift 2 ;;
    --secret-db-root-pass) SECRET_DB_ROOT_PASS_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-}"
INSTANCE="${INSTANCE:-${SQL_INSTANCE:-}}"
TIER="${TIER:-${CLOUD_SQL_TIER:-db-custom-1-3840}}"
DATABASE="${DATABASE:-${MYSQL_DATABASE:-openemr}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER_NAME:-${SECRET_DB_USER:-openemr-db-user}}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS_NAME:-${SECRET_DB_PASS:-openemr-db-pass}}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS_NAME:-${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}}"

if [[ -z "$PROJECT" || -z "$REGION" || -z "$INSTANCE" ]]; then
  echo "Missing required values. Provide CLI flags or set PROJECT_ID, REGION, and SQL_INSTANCE in config."
  usage
  exit 1
fi

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable sqladmin.googleapis.com secretmanager.googleapis.com >/dev/null

DB_USER="$(gcloud secrets versions access latest --secret="$SECRET_DB_USER_NAME")"
DB_PASS="$(gcloud secrets versions access latest --secret="$SECRET_DB_PASS_NAME")"
DB_ROOT_PASS="$(gcloud secrets versions access latest --secret="$SECRET_DB_ROOT_PASS_NAME")"

if [[ -z "$DB_USER" || -z "$DB_PASS" || -z "$DB_ROOT_PASS" ]]; then
  echo "Secret values for DB credentials cannot be empty."
  exit 1
fi

if gcloud sql instances describe "$INSTANCE" >/dev/null 2>&1; then
  echo "Cloud SQL instance already exists: $INSTANCE"
else
  gcloud sql instances create "$INSTANCE" \
    --database-version=MYSQL_8_0 \
    --tier="$TIER" \
    --region="$REGION" \
    --storage-size=20GB \
    --storage-type=SSD \
    --availability-type=zonal
fi

if ! gcloud sql databases describe "$DATABASE" --instance="$INSTANCE" >/dev/null 2>&1; then
  gcloud sql databases create "$DATABASE" --instance="$INSTANCE"
else
  echo "Database already exists: $DATABASE"
fi

if gcloud sql users describe root --host=% --instance="$INSTANCE" >/dev/null 2>&1; then
  gcloud sql users set-password root --host=% --instance="$INSTANCE" --password="$DB_ROOT_PASS" >/dev/null
else
  gcloud sql users create root --host=% --instance="$INSTANCE" --password="$DB_ROOT_PASS" >/dev/null
fi

if gcloud sql users describe "$DB_USER" --host=% --instance="$INSTANCE" >/dev/null 2>&1; then
  gcloud sql users set-password "$DB_USER" --host=% --instance="$INSTANCE" --password="$DB_PASS" >/dev/null
else
  gcloud sql users create "$DB_USER" --host=% --instance="$INSTANCE" --password="$DB_PASS" >/dev/null
fi

echo "Cloud SQL setup complete with Secret Manager-backed credentials."
