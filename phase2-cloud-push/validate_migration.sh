#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  validate_migration.sh [--config <PATH>] [--project <PROJECT_ID>] [--region <REGION>] [--dataset <DATASET_ID>] [--fhir-store <FHIR_STORE_ID>]
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
DATASET="${DATASET_ID:-}"
FHIR_STORE="${FHIR_STORE_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --dataset) DATASET="$2"; shift 2 ;;
    --fhir-store) FHIR_STORE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-}"
DATASET="${DATASET:-${DATASET_ID:-}}"
FHIR_STORE="${FHIR_STORE:-${FHIR_STORE_ID:-}}"

if [[ -z "$PROJECT" || -z "$REGION" || -z "$DATASET" || -z "$FHIR_STORE" ]]; then
  echo "Missing required values. Provide CLI flags or set PROJECT_ID, REGION, DATASET_ID, and FHIR_STORE_ID in config."
  usage
  exit 1
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI is required"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required"
  exit 1
fi

TOKEN="$(gcloud auth print-access-token)"
BASE_URL="https://healthcare.googleapis.com/v1/projects/${PROJECT}/locations/${REGION}/datasets/${DATASET}/fhirStores/${FHIR_STORE}/fhir"

count_resource() {
  local type="$1"
  local url="${BASE_URL}/${type}?_count=0"
  local total
  total="$(curl -sS -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/fhir+json" "${url}" | grep -o '"total"[[:space:]]*:[[:space:]]*[0-9]*' | head -n1 | grep -o '[0-9]*' || true)"

  if [[ -z "$total" ]]; then
    echo "${type}: unable to determine count"
  else
    echo "${type}: ${total}"
  fi
}

echo "Validating resources in FHIR store ${FHIR_STORE}..."
count_resource "Patient"
count_resource "Encounter"
count_resource "Observation"
count_resource "CarePlan"
