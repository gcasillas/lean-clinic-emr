#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  upsert_openemr_sqlconf_secret.sh [--config <PATH>] [--project <PROJECT_ID>] [--instance <SQL_INSTANCE>]

Optional:
  --database <DATABASE_NAME>
  --mysql-port <MYSQL_PORT>
  --mysql-host <HOST>
  --secret-db-user <SECRET_NAME>
  --secret-db-pass <SECRET_NAME>
  --secret-sqlconf <SECRET_NAME>

Creates or updates a Secret Manager secret containing OpenEMR sites/default/sqlconf.php
with config=1 so Cloud Run revisions can mount a durable sqlconf.php file.
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROJECT="${PROJECT_ID:-}"
INSTANCE="${SQL_INSTANCE:-}"
DATABASE="${MYSQL_DATABASE:-openemr}"
MYSQL_PORT_VAL="${MYSQL_PORT:-3306}"
MYSQL_HOST_VALUE="${MYSQL_HOST_RUNTIME:-${INSTALL_DB_TCP_HOST:-}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER:-openemr-db-user}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS:-openemr-db-pass}"
SECRET_SQLCONF_NAME="${SECRET_SQLCONF:-openemr-sqlconf}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --mysql-port) MYSQL_PORT_VAL="$2"; shift 2 ;;
    --mysql-host) MYSQL_HOST_VALUE="$2"; shift 2 ;;
    --secret-db-user) SECRET_DB_USER_NAME="$2"; shift 2 ;;
    --secret-db-pass) SECRET_DB_PASS_NAME="$2"; shift 2 ;;
    --secret-sqlconf) SECRET_SQLCONF_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
INSTANCE="${INSTANCE:-${SQL_INSTANCE:-}}"
DATABASE="${DATABASE:-${MYSQL_DATABASE:-openemr}}"
MYSQL_PORT_VAL="${MYSQL_PORT_VAL:-${MYSQL_PORT:-3306}}"
MYSQL_HOST_VALUE="${MYSQL_HOST_VALUE:-${MYSQL_HOST_RUNTIME:-${INSTALL_DB_TCP_HOST:-}}}"
SECRET_DB_USER_NAME="${SECRET_DB_USER_NAME:-${SECRET_DB_USER:-openemr-db-user}}"
SECRET_DB_PASS_NAME="${SECRET_DB_PASS_NAME:-${SECRET_DB_PASS:-openemr-db-pass}}"
SECRET_SQLCONF_NAME="${SECRET_SQLCONF_NAME:-${SECRET_SQLCONF:-openemr-sqlconf}}"

require_var PROJECT
require_var INSTANCE
require_var SECRET_DB_USER_NAME
require_var SECRET_DB_PASS_NAME
require_var SECRET_SQLCONF_NAME

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable secretmanager.googleapis.com sqladmin.googleapis.com >/dev/null

if [[ -z "$MYSQL_HOST_VALUE" ]]; then
  connection_name="$(gcloud sql instances describe "$INSTANCE" --format='value(connectionName)')"
  if [[ -z "$connection_name" ]]; then
    echo "Unable to resolve Cloud SQL connection name for instance: $INSTANCE" >&2
    exit 1
  fi
  MYSQL_HOST_VALUE="/cloudsql/${connection_name}"
fi

DB_USER="$(gcloud secrets versions access latest --secret="$SECRET_DB_USER_NAME")"
DB_PASS="$(gcloud secrets versions access latest --secret="$SECRET_DB_PASS_NAME")"

if [[ -z "$DB_USER" || -z "$DB_PASS" ]]; then
  echo "DB user/password secrets cannot be empty." >&2
  exit 1
fi

php_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\'/\\\'}"
  printf '%s' "$value"
}

host_esc="$(php_escape "$MYSQL_HOST_VALUE")"
port_esc="$(php_escape "$MYSQL_PORT_VAL")"
user_esc="$(php_escape "$DB_USER")"
pass_esc="$(php_escape "$DB_PASS")"
dbase_esc="$(php_escape "$DATABASE")"

sqlconf_payload="<?php

//  OpenEMR
//  MySQL Config

\$host   = '${host_esc}';
\$port   = '${port_esc}';
\$login  = '${user_esc}';
\$pass   = '${pass_esc}';
\$dbase  = '${dbase_esc}';

\$sqlconf = [];
global \$sqlconf;
\$sqlconf[\"host\"]= \$host;
\$sqlconf[\"port\"] = \$port;
\$sqlconf[\"login\"] = \$login;
\$sqlconf[\"pass\"] = \$pass;
\$sqlconf[\"dbase\"] = \$dbase;

//////////////////////////
//////////////////////////
//////////////////////////
//////DO NOT TOUCH THIS///
\$config = 1; /////////////
//////////////////////////
//////////////////////////
//////////////////////////
"

if gcloud secrets describe "$SECRET_SQLCONF_NAME" >/dev/null 2>&1; then
  printf '%s' "$sqlconf_payload" | gcloud secrets versions add "$SECRET_SQLCONF_NAME" --data-file=- >/dev/null
  echo "Updated secret version: ${SECRET_SQLCONF_NAME}"
else
  printf '%s' "$sqlconf_payload" | gcloud secrets create "$SECRET_SQLCONF_NAME" --replication-policy=automatic --data-file=- >/dev/null
  echo "Created secret: ${SECRET_SQLCONF_NAME}"
fi

echo "sqlconf secret ready for mount at runtime."
