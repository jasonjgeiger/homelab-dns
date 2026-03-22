#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
ERR=0
[[ -f compose.yml ]] || { echo "MISSING: compose.yml"; exit 1; }
[[ -f .env.example ]] || { echo "MISSING: .env.example"; exit 1; }

TMP_ENV=$(mktemp)
trap 'rm -f "$TMP_ENV"' EXIT
cp .env.example "$TMP_ENV"

if command -v docker >/dev/null 2>&1; then
  if docker compose --env-file "$TMP_ENV" config >/dev/null 2>&1; then
    echo "OK: nebula-sync docker compose config"
  else
    echo "FAIL: nebula-sync docker compose config"
    ERR=1
  fi
else
  echo "SKIP: docker not in PATH"
fi
exit "$ERR"
