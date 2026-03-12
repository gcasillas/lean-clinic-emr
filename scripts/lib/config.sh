#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

_load_env_file() {
  local env_file="$1"
  if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    source "$env_file"
  fi
}

load_config() {
  local config_file="${1:-$ROOT_DIR/.env}"

  if [[ -f "$config_file" ]]; then
    _load_env_file "$config_file"
  fi
}

require_var() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required variable: $key" >&2
    exit 1
  fi
}

is_yes() {
  local value="${1:-}"
  [[ "$value" == "yes" || "$value" == "true" || "$value" == "1" ]]
}
