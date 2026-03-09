#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  init_gcp_fhir_store.sh [--config <PATH>] [--profile <NAME>] [--project <PROJECT_ID>] [--region <REGION>] [--dataset <DATASET_ID>] [--fhir-store <FHIR_STORE_ID>]

Example:
  ./init_gcp_fhir_store.sh --profile holistic-herbal --project demo-proj
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROFILE=""
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
DATASET="${DATASET_ID:-}"
FHIR_STORE="${FHIR_STORE_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --dataset) DATASET="$2"; shift 2 ;;
    --fhir-store) FHIR_STORE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE" "$PROFILE"
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

gcloud config set project "$PROJECT" >/dev/null

echo "Ensuring APIs are enabled..."
gcloud services enable healthcare.googleapis.com >/dev/null

echo "Creating Healthcare dataset if needed..."
if ! gcloud healthcare datasets describe "$DATASET" --location="$REGION" >/dev/null 2>&1; then
  gcloud healthcare datasets create "$DATASET" --location="$REGION"
else
  echo "Dataset already exists: $DATASET"
fi

echo "Creating FHIR store if needed..."
if ! gcloud healthcare fhir-stores describe "$FHIR_STORE" --dataset="$DATASET" --location="$REGION" >/dev/null 2>&1; then
  gcloud healthcare fhir-stores create "$FHIR_STORE" \
    --dataset="$DATASET" \
    --location="$REGION" \
    --version=R4 \
    --enable-update-create
else
  echo "FHIR store already exists: $FHIR_STORE"
fi

echo "FHIR store initialization complete."
