#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  init_gcp_dicom_store.sh [--config <PATH>] [--project <PROJECT_ID>] [--region <REGION>] [--dataset <DICOM_DATASET_ID>] [--dicom-store <DICOM_STORE_ID>]

Creates a Healthcare DICOM dataset/store for PACS readiness.
This does not deploy a PACS viewer/archive application.
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROJECT="${PROJECT_ID:-}"
REGION="${REGION:-}"
DATASET="${DICOM_DATASET_ID:-}"
DICOM_STORE="${DICOM_STORE_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --dataset) DATASET="$2"; shift 2 ;;
    --dicom-store) DICOM_STORE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
REGION="${REGION:-}"
DATASET="${DATASET:-${DICOM_DATASET_ID:-}}"
DICOM_STORE="${DICOM_STORE:-${DICOM_STORE_ID:-}}"

if [[ -z "$PROJECT" || -z "$REGION" || -z "$DATASET" || -z "$DICOM_STORE" ]]; then
  echo "Missing required values. Provide CLI flags or set PROJECT_ID, REGION, DICOM_DATASET_ID, and DICOM_STORE_ID in config."
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

echo "Creating DICOM dataset if needed..."
if ! gcloud healthcare datasets describe "$DATASET" --location="$REGION" >/dev/null 2>&1; then
  gcloud healthcare datasets create "$DATASET" --location="$REGION"
else
  echo "Dataset already exists: $DATASET"
fi

echo "Creating DICOM store if needed..."
if ! gcloud healthcare dicom-stores describe "$DICOM_STORE" --dataset="$DATASET" --location="$REGION" >/dev/null 2>&1; then
  gcloud healthcare dicom-stores create "$DICOM_STORE" --dataset="$DATASET" --location="$REGION"
else
  echo "DICOM store already exists: $DICOM_STORE"
fi

echo "DICOM preparation complete (PACS-ready infrastructure only)."
