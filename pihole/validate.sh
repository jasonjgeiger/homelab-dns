#!/usr/bin/env bash
# Validates repo layout and Docker Compose with both node env files.
set -euo pipefail
cd "$(dirname "$0")"
ERR=0

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "MISSING: $1"
    ERR=1
  fi
}

for f in compose.yml check_pihole.sh notify.sh keepalived.conf.template create_macvlan.sh deploy.sh \
         .env.example .env.vm1 .env.vm2 etc-dnscrypt-proxy/dnscrypt-proxy.toml; do
  require_file "$f"
done

if ! command -v envsubst >/dev/null 2>&1; then
  echo "WARN: envsubst not found — install gettext to run full validation"
else
  for envf in .env.vm1 .env.vm2; do
    set -a
    # shellcheck disable=SC1090
    source "$envf"
    set +a
    export ROUTER_ID VRRP_STATE VRRP_PRIORITY VRRP_AUTH_PASS UNICAST_SRC_IP UNICAST_PEER_IP VIP_CIDR
    tmp="/tmp/keepalived.validate.$$.$envf"
    envsubst < keepalived.conf.template > "$tmp"
    if grep -q '\${' "$tmp" 2>/dev/null; then
      echo "FAIL: unreplaced placeholders in keepalived render for $envf"
      ERR=1
    fi
    rm -f "$tmp"
  done
  echo "OK: keepalived.conf.template renders for .env.vm1 and .env.vm2 (no stray \${...})"
fi

if command -v docker >/dev/null 2>&1; then
  # keepalived.conf required for volume mount
  set -a
  # shellcheck disable=SC1090
  source .env.vm1
  set +a
  export ROUTER_ID VRRP_STATE VRRP_PRIORITY VRRP_AUTH_PASS UNICAST_SRC_IP UNICAST_PEER_IP VIP_CIDR
  envsubst < keepalived.conf.template > keepalived.conf
  if docker compose --env-file .env.vm1 config >/dev/null 2>&1; then
    echo "OK: docker compose config (.env.vm1)"
  else
    echo "FAIL: docker compose config (.env.vm1)"
    ERR=1
  fi
  if docker compose --env-file .env.vm2 config >/dev/null 2>&1; then
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
