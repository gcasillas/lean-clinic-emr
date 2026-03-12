#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage:
  harden_cloud_sql_network.sh [--config <PATH>] [--project <PROJECT_ID>] [--instance <SQL_INSTANCE>]

Removes temporary 0.0.0.0/0 authorized network rules while preserving other configured CIDRs.
EOF
}

CONFIG_FILE="${SCRIPT_DIR}/../.env"
PROJECT="${PROJECT_ID:-}"
INSTANCE="${SQL_INSTANCE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --profile) echo "Warning: --profile is deprecated and ignored." >&2; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

load_config "$CONFIG_FILE"
PROJECT="${PROJECT:-${PROJECT_ID:-}}"
INSTANCE="${INSTANCE:-${SQL_INSTANCE:-}}"

require_var PROJECT
require_var INSTANCE

gcloud config set project "$PROJECT" >/dev/null

mapfile -t networks < <(gcloud sql instances describe "$INSTANCE" --format='value(settings.ipConfiguration.authorizedNetworks[].value)')

if [[ ${#networks[@]} -eq 0 ]]; then
  echo "No authorized networks configured."
  exit 0
fi

filtered=()
removed_open_rule=false
for cidr in "${networks[@]}"; do
  if [[ "$cidr" == "0.0.0.0/0" ]]; then
    removed_open_rule=true
    continue
  fi
  filtered+=("$cidr")
done

if [[ "$removed_open_rule" == false ]]; then
  echo "No 0.0.0.0/0 rule found; no changes made."
  exit 0
fi

if [[ ${#filtered[@]} -eq 0 ]]; then
  gcloud sql instances patch "$INSTANCE" --clear-authorized-networks --quiet >/dev/null
else
  joined="$(IFS=,; echo "${filtered[*]}")"
  gcloud sql instances patch "$INSTANCE" --authorized-networks="$joined" --quiet >/dev/null
fi

echo "Removed temporary 0.0.0.0/0 Cloud SQL network rule."
