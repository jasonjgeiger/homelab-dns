#!/usr/bin/env bash
# DNS HA stack: no root compose.yml — this script merges fragment compose files and runs them
# with a single project name. Use: ./stack.sh init | up | down | trash | wipe | pull | …
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME=pihole

die() { echo "error: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing '$1' in PATH"; }

stack_compose() {
  # No --project-directory: bind mounts in each -f file resolve from that file's directory (Compose spec).
  docker compose \
    -p "$PROJECT_NAME" \
    -f "$ROOT/macvlan/compose.yml" \
    -f "$ROOT/dnscrypt-proxy/compose.yml" \
    -f "$ROOT/pihole/compose.yml" \
    -f "$ROOT/keepalived/compose.yml" \
    -f "$ROOT/nebula-sync/compose.yml" \
    --env-file "$ROOT/macvlan/.env" \
    --env-file "$ROOT/dnscrypt-proxy/.env" \
    --env-file "$ROOT/pihole/.env" \
    --env-file "$ROOT/nebula-sync/.env" \
    "$@"
}

preflight_env_files() {
  for f in macvlan/.env dnscrypt-proxy/.env pihole/.env nebula-sync/.env; do
    [[ -f "$ROOT/$f" ]] || die "missing $f — run: $0 init"
  done
}

preflight_env() {
  preflight_env_files
  [[ -f "$ROOT/keepalived/keepalived.conf" ]] || die "missing keepalived/keepalived.conf — run: $0 init"
}

cmd_up() {
  require_cmd docker
  preflight_env
  # Order: internal DNS first, then Pi-hole (depends on dnscrypt), then keepalived (uses pihole netns), then nebula.
  echo "==> dnscrypt-proxy (and project networks)"
  stack_compose up -d dnscrypt-proxy
  echo "==> pihole"
  stack_compose up -d pihole
  echo "==> keepalived"
  stack_compose up -d keepalived
  echo "==> nebula-sync"
  stack_compose up -d nebula-sync
  echo "Done. docker compose -p $PROJECT_NAME ps"
}

stack_down() {
  if [[ -f "$ROOT/macvlan/.env" && -f "$ROOT/pihole/.env" ]]; then
    stack_compose down --remove-orphans
  else
    echo "warn: missing some .env files; running: docker compose -p $PROJECT_NAME down" >&2
    docker compose -p "$PROJECT_NAME" down --remove-orphans
  fi
}

parse_yes_flag() {
  local a
  for a in "$@"; do
    case $a in --yes|-y) return 0 ;; esac
  done
  return 1
}

# Remove project containers, networks, declared/anonymous volumes for this stack, and images used only by these services.
stack_purge() {
  local f
  for f in macvlan/.env dnscrypt-proxy/.env pihole/.env nebula-sync/.env; do
    [[ -f "$ROOT/$f" ]] || die "missing $f — cannot run compose teardown. Use '$0 down' or restore .env from *.env.example"
  done
  echo "==> docker compose down --remove-orphans -v --rmi all (project $PROJECT_NAME only)"
  stack_compose down --remove-orphans -v --rmi all
}

cmd_trash() {
  require_cmd docker
  if ! parse_yes_flag "$@"; then
    read -r -p "Remove stack '$PROJECT_NAME' (containers, project networks/volumes, service images)? [y/N] " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || { echo "Aborted."; exit 0; }
  fi
  stack_purge
  echo "Done (trash). Host bind mounts (e.g. pihole data dirs) are unchanged."
}

cmd_wipe() {
  require_cmd docker
  if ! parse_yes_flag "$@"; then
    read -r -p "Wipe: purge stack '$PROJECT_NAME' (same as trash) AND delete local */.env + keepalived/keepalived.conf? [y/N] " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || { echo "Aborted."; exit 0; }
  fi
  stack_purge
  echo "==> Removing local env and rendered keepalived config"
  rm -f \
    "$ROOT/macvlan/.env" \
    "$ROOT/dnscrypt-proxy/.env" \
    "$ROOT/pihole/.env" \
    "$ROOT/keepalived/.env" \
    "$ROOT/nebula-sync/.env" \
    "$ROOT/keepalived/keepalived.conf"
  echo "Done (wipe). Run: $0 init && $0 up"
}

# --- init (interactive env + keepalived.conf) ---

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

ipv4_basic() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }

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

cmd_init() {
  local FORCE=0
  [[ "${2:-}" == "--force" || "${2:-}" == "-f" ]] && FORCE=1

  require_cmd envsubst

  echo "=== Homelab DNS stack — env setup ==="
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
  local webpass vrrp_secret my_pihole state priority src_ip peer_unicast router_id

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
    echo "warn: password contains '|' — nebula-sync delimiter; edit nebula-sync/.env manually." >&2
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
  echo "Wrote env files and keepalived/keepalived.conf."
  echo "This node: ${role} (${state}). Start stack: $0 up"
}

usage() {
  cat <<EOF
Usage: $0 <command>

  init [--force]   Interactive prompts → writes */.env and keepalived/keepalived.conf
  up               Start stack (dnscrypt-proxy → pihole → keepalived → nebula-sync)
  down             Stop and remove containers/networks for this project
  trash [--yes]    compose down for project $PROJECT_NAME: containers, networks, volumes (-v), images (--rmi all)
  wipe [--yes]     Same as trash + delete all */.env and keepalived/keepalived.conf in repo
  pull             Pull images
  ps | logs | config   Pass-through to docker compose (same project + files)

  --yes / -y       Skip confirmation for trash / wipe

Project name: $PROJECT_NAME (fixed for consistent container names)
EOF
}

case "${1:-}" in
  init) cmd_init "$@" ;;
  up) cmd_up ;;
  down)
    require_cmd docker
    stack_down
    ;;
  trash)
    shift
    cmd_trash "$@"
    ;;
  wipe)
    shift
    cmd_wipe "$@"
    ;;
  pull) require_cmd docker; preflight_env_files; stack_compose pull ;;
  ps|logs|config|exec|restart|stop|start)
    require_cmd docker
    preflight_env_files
    stack_compose "$@"
    ;;
  ""|-h|--help) usage ;;
  *) die "unknown command: $1 (try $0 --help)" ;;
esac
