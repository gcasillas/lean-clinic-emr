#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  bootstrap_new_clinic_deployment.sh [--config <PATH>] [--profile <NAME>]

Orchestrates a new clinic deployment using profile-driven defaults:
  1) Rotate DB credentials in Secret Manager
  2) Provision Cloud SQL and DB users
  3) Deploy OpenEMR to Cloud Run
  4) Attach Cloud SQL connector and secret bindings
  5) Initialize FHIR store
  6) Run smoke tests

Flags:
  --skip-fhir      Skip FHIR store initialization
  --skip-smoke     Skip deployment smoke tests
EOF
}

CONFIG_FILE="${ROOT_DIR}/.env"
PROFILE=""
SKIP_FHIR=false
SKIP_SMOKE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --skip-fhir) SKIP_FHIR=true; shift 1 ;;
    --skip-smoke) SKIP_SMOKE=true; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE" "$PROFILE"
require_var PROJECT_ID
require_var REGION
require_var SERVICE_NAME
require_var SQL_INSTANCE

COMMON_ARGS=(--config "$CONFIG_FILE")
if [[ -n "$PROFILE" ]]; then
  COMMON_ARGS+=(--profile "$PROFILE")
fi

echo "[1/6] Rotating DB secrets"
"${ROOT_DIR}/phase3-cloud-deployment/rotate_db_secrets.sh" "${COMMON_ARGS[@]}"

echo "[2/6] Provisioning Cloud SQL"
"${ROOT_DIR}/phase3-cloud-deployment/setup_cloud_sql.sh" "${COMMON_ARGS[@]}"

echo "[3/6] Deploying Cloud Run service"
"${ROOT_DIR}/phase3-cloud-deployment/deploy_to_cloud_run.sh" "${COMMON_ARGS[@]}"

echo "[4/6] Configuring Cloud Run with Cloud SQL connector"
"${ROOT_DIR}/phase3-cloud-deployment/configure_cloud_emr.sh" "${COMMON_ARGS[@]}"

if [[ "$SKIP_FHIR" == false ]]; then
  echo "[5/6] Initializing FHIR store"
  "${ROOT_DIR}/phase2-cloud-push/init_gcp_fhir_store.sh" "${COMMON_ARGS[@]}"
else
  echo "[5/6] Skipped FHIR initialization"
fi

if [[ "$SKIP_SMOKE" == false ]]; then
  echo "[6/6] Running smoke tests"
  "${ROOT_DIR}/phase3-cloud-deployment/smoke_test_deployment.sh" "${COMMON_ARGS[@]}"
else
  echo "[6/6] Skipped smoke tests"
fi

echo "Bootstrap completed. If installer TCP access was enabled, run phase3-cloud-deployment/harden_cloud_sql_network.sh after setup is finished."
