#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
echo "=== pihole ==="
bash "$ROOT/pihole/validate.sh"
echo "=== nebula-sync ==="
bash "$ROOT/nebula-sync/validate.sh"
echo "=== all OK ==="
