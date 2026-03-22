#!/usr/bin/env bash
# Copy each service `.env.example` → `.env` (repo root = stacks/).
# Skips targets that already exist unless you pass --force.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FORCE=0
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
  FORCE=1
fi

DIRS=(macvlan dnscrypt-proxy pihole keepalived nebula-sync)

for d in "${DIRS[@]}"; do
  src="$ROOT/$d/.env.example"
  dst="$ROOT/$d/.env"
  if [[ ! -f "$src" ]]; then
    echo "error: missing $src" >&2
    exit 1
  fi
  if [[ -f "$dst" && "$FORCE" -eq 0 ]]; then
    echo "skip: $dst (exists; use --force to overwrite)"
    continue
  fi
  cp "$src" "$dst"
  echo "created $dst"
done

echo "Done. Edit each .env, render keepalived.conf, then: docker compose --project-directory . up -d"
