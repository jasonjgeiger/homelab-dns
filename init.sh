#!/usr/bin/env bash
# Interactive setup: prompts for primary/peer, IPs, web password, VRRP secret; writes
# macvlan, dnscrypt-proxy, pihole, keepalived, nebula-sync .env and keepalived/keepalived.conf.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FORCE=0
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
  FORCE=1
fi

die() { echo "error: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing '$1' in PATH"; }

# Dotenv-safe double-quoted value (escape \ and ").
quote_env_value() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

prompt_nonempty() {
  local label=$1
  local var=$2
  local val
  while true; do
    read -r -p "$label: " val
    if [[ -n "${val// /}" ]]; then
      printf -v "$var" '%s' "$val"
      return 0
    fi
    echo "  (required)"
  done
}

prompt_secret() {
  local label=$1
  local var=$2
  local val val2
  while true; do
    read -r -s -p "$label: " val
    echo
    read -r -s -p "Confirm: " val2
    echo
    if [[ -n "$val" && "$val" == "$val2" ]]; then
      printf -v "$var" '%s' "$val"
      return 0
    fi
    echo "  Passwords must match and be non-empty."
  done
}

prompt_choice() {
  local label=$1
  local var=$2
  local val
  while true; do
    read -r -p "$label [primary/peer]: " val
    val=${val,,}
    case $val in
      primary|p|1|master) printf -v "$var" '%s' primary; return 0 ;;
      peer|backup|b|2|secondary) printf -v "$var" '%s' peer; return 0 ;;
      *) echo "  Enter 'primary' (MASTER) or 'peer' (BACKUP)." ;;
    esac
  done
}

ipv4_basic() {
  [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]
}

validate_ipv4() {
  ipv4_basic "$1" || die "invalid IPv4: $1"
  local oIFS=$IFS IFS=.
  local -a p=($1)
  IFS=$oIFS
  local b
  for b in "${p[@]}"; do
    (( b >= 0 && b <= 255 )) || die "invalid IPv4 octet: $1"
  done
}

main() {
  require_cmd envsubst

  echo "=== Homelab DNS stack — first-time env setup ==="
  echo

  if [[ "$FORCE" -eq 0 ]]; then
    local existing=0
    for d in macvlan dnscrypt-proxy pihole keepalived nebula-sync; do
      [[ -f "$ROOT/$d/.env" ]] && existing=1
    done
    [[ -f "$ROOT/keepalived/keepalived.conf" ]] && existing=1
    if [[ "$existing" -eq 1 ]]; then
      read -r -p "Some .env or keepalived.conf already exist. Overwrite? [y/N]: " ans
      [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || { echo "Aborted."; exit 0; }
    fi
  fi

  local role primary_ip peer_ip vip vip_cidr subnet gateway iface tz
  local webpass vrrp_secret my_pihole state priority peer_ip_for_vrrp src_ip peer_unicast router_id

  prompt_choice "Which server is this node" role
  prompt_nonempty "Primary node Pi-hole IP (macvlan)" primary_ip
  prompt_nonempty "Peer node Pi-hole IP (macvlan)" peer_ip
  validate_ipv4 "$primary_ip"
  validate_ipv4 "$peer_ip"
  [[ "$primary_ip" != "$peer_ip" ]] || die "primary and peer Pi-hole IPs must differ"

  prompt_nonempty "VIP for client DNS (same on both nodes)" vip
  validate_ipv4 "$vip"

  read -r -p "VIP CIDR suffix [24]: " vip_suffix
  [[ -z "$vip_suffix" ]] && vip_suffix=24
  vip_cidr="${vip}/${vip_suffix}"

  prompt_nonempty "Macvlan LAN subnet (e.g. 192.168.100.0/24)" subnet
  prompt_nonempty "Macvlan LAN gateway IP" gateway
  validate_ipv4 "$gateway"

  read -r -p "Host NIC for macvlan parent [eth0]: " iface
  [[ -z "$iface" ]] && iface=eth0

  read -r -p "Timezone [America/Los_Angeles]: " tz
  [[ -z "$tz" ]] && tz=America/Los_Angeles

  echo
  prompt_secret "Pi-hole web / API password (same on both nodes)" webpass
  prompt_secret "keepalived VRRP shared secret (same on both nodes)" vrrp_secret

  if [[ "$role" == primary ]]; then
    my_pihole=$primary_ip
    state=MASTER
    priority=110
    src_ip=$primary_ip
    peer_unicast=$peer_ip
    router_id=PIHOLE_PRIMARY
  else
    my_pihole=$peer_ip
    state=BACKUP
    priority=100
    src_ip=$peer_ip
    peer_unicast=$primary_ip
    router_id=PIHOLE_PEER
  fi

  local web_q vrrp_q
  web_q=$(quote_env_value "$webpass")
  vrrp_q=$(quote_env_value "$vrrp_secret")

  mkdir -p "$ROOT/macvlan" "$ROOT/dnscrypt-proxy" "$ROOT/pihole" "$ROOT/keepalived" "$ROOT/nebula-sync"

  cat >"$ROOT/macvlan/.env" <<EOF
PARENT_INTERFACE=${iface}
MACVLAN_SUBNET=${subnet}
MACVLAN_GATEWAY=${gateway}
EOF

  cat >"$ROOT/dnscrypt-proxy/.env" <<EOF
TZ=${tz}
EOF

  cat >"$ROOT/pihole/.env" <<EOF
PIHOLE_IPV4=${my_pihole}
SERVERIP=${vip}
DNS1=10.0.1.2#5300
DNS2=no
TZ=${tz}
WEBPASSWORD=${web_q}
EOF

  cat >"$ROOT/keepalived/.env" <<EOF
ROUTER_ID=${router_id}
VRRP_STATE=${state}
VRRP_PRIORITY=${priority}
VRRP_AUTH_PASS=${vrrp_q}
UNICAST_SRC_IP=${src_ip}
UNICAST_PEER_IP=${peer_unicast}
VIP_CIDR=${vip_cidr}
EOF

  # nebula-sync: PRIMARY = source of truth (primary node's Pi-hole). | still must not appear in the password.
  local neb_pri neb_rep
  neb_pri=$(quote_env_value "http://${primary_ip}|${webpass}")
  neb_rep=$(quote_env_value "http://${peer_ip}|${webpass}")
  cat >"$ROOT/nebula-sync/.env" <<EOF
PRIMARY=${neb_pri}
REPLICAS=${neb_rep}

FULL_SYNC=true
RUN_GRAVITY=true
CRON=*/15 * * * *
TZ=${tz}
EOF
  if [[ "$webpass" == *"|"* ]]; then
    echo "warn: password contains '|' — nebula-sync uses '|' as delimiter; edit nebula-sync/.env manually." >&2
  fi

  export ROUTER_ID=$router_id
  export VRRP_STATE=$state
  export VRRP_PRIORITY=$priority
  export VRRP_AUTH_PASS=$vrrp_secret
  export UNICAST_SRC_IP=$src_ip
  export UNICAST_PEER_IP=$peer_unicast
  export VIP_CIDR=$vip_cidr

  envsubst <"$ROOT/keepalived/keepalived.conf.template" >"$ROOT/keepalived/keepalived.conf"

  echo
  echo "Wrote:"
  echo "  macvlan/.env  dnscrypt-proxy/.env  pihole/.env  keepalived/.env  nebula-sync/.env"
  echo "  keepalived/keepalived.conf"
  echo
  echo "This node: ${role} (${state}, priority ${priority}), Pi-hole ${my_pihole}"
  echo "Run on the other node with the same inputs except choose the other role (primary vs peer)."
  echo "Then: docker compose --project-directory \"$ROOT\" up -d"
}

main "$@"
