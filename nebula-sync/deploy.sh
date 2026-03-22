#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example — set PRIMARY / REPLICAS passwords, then re-run."
  exit 1
fi
docker compose up -d
