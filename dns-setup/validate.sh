#!/usr/bin/env bash
# Validates repo layout and Docker Compose with both node env files.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ERR=0

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "MISSING: $1"
    ERR=1
  fi
}

for f in "$ROOT/compose.yml" \
         "$ROOT/dnscrypt-proxy/compose.yml" "$ROOT/pihole-core/compose.yml" "$ROOT/keepalived/compose.yml" \
         "$SCRIPT_DIR/check_pihole.sh" "$SCRIPT_DIR/notify.sh" "$SCRIPT_DIR/keepalived.conf.template" \
         "$SCRIPT_DIR/create_macvlan.sh" "$SCRIPT_DIR/deploy.sh" \
         "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env.vm1" "$SCRIPT_DIR/.env.vm2" \
         "$SCRIPT_DIR/etc-dnscrypt-proxy/dnscrypt-proxy.toml"; do
  require_file "$f"
done

if ! command -v envsubst >/dev/null 2>&1; then
  echo "WARN: envsubst not found — install gettext to run full validation"
else
  for envf in .env.vm1 .env.vm2; do
    set -a
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/$envf"
    set +a
    export ROUTER_ID VRRP_STATE VRRP_PRIORITY VRRP_AUTH_PASS UNICAST_SRC_IP UNICAST_PEER_IP VIP_CIDR
    tmp="/tmp/keepalived.validate.$$.$envf"
    envsubst < "$SCRIPT_DIR/keepalived.conf.template" > "$tmp"
    if grep -q '\${' "$tmp" 2>/dev/null; then
      echo "FAIL: unreplaced placeholders in keepalived render for $envf"
      ERR=1
    fi
    rm -f "$tmp"
  done
  echo "OK: keepalived.conf.template renders for .env.vm1 and .env.vm2 (no stray \${...})"
fi

if command -v docker >/dev/null 2>&1; then
  set -a
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/.env.vm1"
  set +a
  export ROUTER_ID VRRP_STATE VRRP_PRIORITY VRRP_AUTH_PASS UNICAST_SRC_IP UNICAST_PEER_IP VIP_CIDR
  envsubst < "$SCRIPT_DIR/keepalived.conf.template" > "$SCRIPT_DIR/keepalived.conf"
  COMPOSE_BASE=(docker compose
    -f "$ROOT/dnscrypt-proxy/compose.yml"
    -f "$ROOT/pihole-core/compose.yml"
    -f "$ROOT/keepalived/compose.yml")
  if (cd "$ROOT" && "${COMPOSE_BASE[@]}" --env-file "$SCRIPT_DIR/.env.vm1" config >/dev/null 2>&1); then
    echo "OK: docker compose config (.env.vm1)"
  else
    echo "FAIL: docker compose config (.env.vm1)"
    ERR=1
  fi
  if (cd "$ROOT" && "${COMPOSE_BASE[@]}" --env-file "$SCRIPT_DIR/.env.vm2" config >/dev/null 2>&1); then
    echo "OK: docker compose config (.env.vm2)"
  else
    echo "FAIL: docker compose config (.env.vm2)"
    ERR=1
  fi
else
  echo "SKIP: docker not in PATH (compose config not checked)"
fi

if [[ $ERR -eq 0 ]]; then
  echo "Validation finished: all checks passed."
else
  echo "Validation finished with errors."
fi
exit "$ERR"
