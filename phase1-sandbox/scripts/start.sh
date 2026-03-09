#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example. Update credentials before production use."
fi

docker compose up -d

echo "OpenEMR sandbox started on http://localhost:${OPENEMR_PORT:-8080}"
