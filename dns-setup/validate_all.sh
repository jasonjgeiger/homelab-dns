#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE="$(cd "$(dirname "$0")" && pwd)"
echo "=== dns stack ==="
bash "$NODE/validate.sh"
echo "=== nebula-sync ==="
bash "$ROOT/nebula-sync/validate.sh"
echo "=== all OK ==="
