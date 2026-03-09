#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  rotate_db_secrets.sh [--config <PATH>] [--profile <NAME>] [--project <PROJECT_ID>]

Optional:
  --secret-db-user <SECRET_NAME>
  --secret-db-pass <SECRET_NAME>
  --secret-db-root-pass <SECRET_NAME>
  --db-user <DB_USER>
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROFILE=""
PROJECT="${PROJECT_ID:-}"
SECRET_DB_USER_NAME="${SECRET_DB_USER:-openemr-db-user}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS:-openemr-db-pass}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}"
DB_USER_VALUE="${DB_USER:-openemr}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --secret-db-user) SECRET_DB_USER_NAME="$2"; shift 2 ;;
    --secret-db-pass) SECRET_DB_PASS_NAME="$2"; shift 2 ;;
    --secret-db-root-pass) SECRET_DB_ROOT_PASS_NAME="$2"; shift 2 ;;
    --db-user) DB_USER_VALUE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE" "$PROFILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER_NAME:-${SECRET_DB_USER:-openemr-db-user}}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS_NAME:-${SECRET_DB_PASS:-openemr-db-pass}}"
SECRET_DB_ROOT_PASS_NAME="${SECRET_DB_ROOT_PASS_NAME:-${SECRET_DB_ROOT_PASS:-openemr-db-root-pass}}"
DB_USER_VALUE="${DB_USER_VALUE:-${DB_USER:-openemr}}"

require_var PROJECT

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable secretmanager.googleapis.com >/dev/null

generate_secret() {
  tr -dc 'A-Za-z0-9!@#%+=' </dev/urandom | head -c 32
}

upsert_secret() {
  local name="$1"
  local value="$2"
  if gcloud secrets describe "$name" >/dev/null 2>&1; then
    printf "%s" "$value" | gcloud secrets versions add "$name" --data-file=- >/dev/null
  else
    printf "%s" "$value" | gcloud secrets create "$name" --replication-policy=automatic --data-file=- >/dev/null
  fi
}

DB_PASS_VALUE="$(generate_secret)"
DB_ROOT_PASS_VALUE="$(generate_secret)"

upsert_secret "$SECRET_DB_USER_NAME" "$DB_USER_VALUE"
upsert_secret "$SECRET_DB_PASS_NAME" "$DB_PASS_VALUE"
upsert_secret "$SECRET_DB_ROOT_PASS_NAME" "$DB_ROOT_PASS_VALUE"

echo "Rotated secrets: $SECRET_DB_USER_NAME, $SECRET_DB_PASS_NAME, $SECRET_DB_ROOT_PASS_NAME"
