#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Usage on VM1: $0 .env.vm1"
  echo "       on VM2: $0 .env.vm2"
  echo "Or copy .env.example to .env, edit, then: $0 .env"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH"
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst not found (e.g. apt install gettext-base, brew install gettext)"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

REQUIRED=(PARENT_INTERFACE MACVLAN_SUBNET MACVLAN_GATEWAY MACVLAN_NETWORK_NAME
  PIHOLE_IPV4 SERVERIP DNS1 DNS2 TZ WEBPASSWORD ROUTER_ID VRRP_STATE
  VRRP_PRIORITY VRRP_AUTH_PASS UNICAST_SRC_IP UNICAST_PEER_IP VIP_CIDR)
MISSING=()
for v in "${REQUIRED[@]}"; do
  eval "val=\${$v-}"
  if [[ -z "$val" ]]; then MISSING+=("$v"); fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Missing required variables in $ENV_FILE: ${MISSING[*]}"
  exit 1
fi

bash "${PWD}/create_macvlan.sh"

export ROUTER_ID VRRP_STATE VRRP_PRIORITY VRRP_AUTH_PASS UNICAST_SRC_IP UNICAST_PEER_IP VIP_CIDR
envsubst < keepalived.conf.template > keepalived.conf

docker compose --env-file "$ENV_FILE" pull
docker compose --env-file "$ENV_FILE" up -d

echo "Stack is up. Point clients at VIP ${SERVERIP} for DNS."
echo "Pi-hole on this host: http://${PIHOLE_IPV4}/admin (direct) or http://${SERVERIP}/admin when this node holds VIP."
