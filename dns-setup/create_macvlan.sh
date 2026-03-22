#!/usr/bin/env bash
set -euo pipefail
# Uses env from deploy.sh (set -a source) or defaults below.
PARENT_INTERFACE="${PARENT_INTERFACE:-eth0}"
SUBNET="${MACVLAN_SUBNET:-192.168.100.0/24}"
GATEWAY="${MACVLAN_GATEWAY:-192.168.100.1}"
NETWORK_NAME="${MACVLAN_NETWORK_NAME:-pihole_macvlan}"

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Docker network '$NETWORK_NAME' already exists."
  exit 0
fi

docker network create --driver macvlan \
  --subnet="$SUBNET" \
  --gateway="$GATEWAY" \
  --opt parent="$PARENT_INTERFACE" \
  "$NETWORK_NAME"
echo "Created macvlan network '$NETWORK_NAME' (parent=$PARENT_INTERFACE)."
