#!/usr/bin/env bash
# Homelab DNS stack: root compose.yml + .env — see ./stack.sh --help
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME=pihole
COMPOSE_FILE="$ROOT/compose.yml"
ENV_FILE="$ROOT/.env"
KEEPALIVED_TEMPLATE="$ROOT/keepalived/keepalived.conf.template"
KEEPALIVED_CONF="$ROOT/keepalived/assets/keepalived.conf"

die() { echo "error: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing '$1' in PATH"; }

stack_compose() {
  docker compose \
    --project-directory "$ROOT" \
    -p "$PROJECT_NAME" \
    -f "$COMPOSE_FILE" \
    --env-file "$ENV_FILE" \
    "$@"
}

unquote_env_val() {
  local val=$1
  if [[ ${#val} -ge 2 && "${val:0:1}" == '"' && "${val: -1}" == '"' ]]; then
    val="${val:1:${#val}-2}"
    val="${val//\\\"/\"}"
    val="${val//\\\\/\\}"
  fi
  printf '%s' "$val"
}

# Compose .env format — do not `source` whole file (DNS1 contains #).
load_vrrp_env_from_dotenv() {
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    key="${line%%=*}"
    [[ "$key" == "$line" ]] && continue
    val="${line#"${key}="}"
    case "$key" in
      ROUTER_ID|VRRP_STATE|VRRP_PRIORITY|VRRP_AUTH_PASS|UNICAST_SRC_IP|UNICAST_PEER_IP|VIP_CIDR)
        val=$(unquote_env_val "$val")
        printf -v val_q '%q' "$val"
        eval "export ${key}=${val_q}"
        ;;
    esac
  done <"$ENV_FILE"
}

render_keepalived_conf() {
  require_cmd envsubst
  [[ -f "$ENV_FILE" ]] || die "missing .env"
  load_vrrp_env_from_dotenv
  local missing=()
  [[ -n "${ROUTER_ID:-}" ]] || missing+=(ROUTER_ID)
  [[ -n "${VRRP_STATE:-}" ]] || missing+=(VRRP_STATE)
  [[ -n "${VRRP_PRIORITY:-}" ]] || missing+=(VRRP_PRIORITY)
  [[ -n "${VRRP_AUTH_PASS:-}" ]] || missing+=(VRRP_AUTH_PASS)
  [[ -n "${UNICAST_SRC_IP:-}" ]] || missing+=(UNICAST_SRC_IP)
  [[ -n "${UNICAST_PEER_IP:-}" ]] || missing+=(UNICAST_PEER_IP)
  [[ -n "${VIP_CIDR:-}" ]] || missing+=(VIP_CIDR)
  ((${#missing[@]} == 0)) || die ".env missing keepalived vars: ${missing[*]}"
  mkdir -p "$ROOT/keepalived/assets"
  envsubst <"$KEEPALIVED_TEMPLATE" >"$KEEPALIVED_CONF"
}

preflight_env_files() {
  [[ -f "$ENV_FILE" ]] || die "missing .env — run: $0 init or cp .env.example .env"
}

preflight_env() {
  preflight_env_files
  render_keepalived_conf
}

cmd_up() {
  require_cmd docker
  preflight_env
  # compose.yml orders services via depends_on + service_healthy; no per-service up needed.
  echo "==> docker compose up -d (project $PROJECT_NAME)"
  stack_compose up -d
  echo "Done. Check status: $0 ps"
}

stack_down() {
  if [[ -f "$ENV_FILE" ]]; then
    stack_compose down --remove-orphans
  else
    echo "warn: missing .env; running: docker compose -p $PROJECT_NAME down" >&2
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

# Compose down only removes networks listed in the current file; older keys (e.g. pihole_internal) leave orphans like pihole_pihole_internal.
prune_project_networks() {
  local id name
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! docker network rm "$id" 2>/dev/null; then
      echo "warn: could not remove network id=$id (still attached? docker network inspect $id)" >&2
    fi
  done < <(docker network ls --filter "label=com.docker.compose.project=$PROJECT_NAME" -q)

  # Legacy names from earlier compose (bridge was pihole_internal → pihole_pihole_internal)
  for name in "${PROJECT_NAME}_${PROJECT_NAME}_internal" "${PROJECT_NAME}_default"; do
    docker network rm "$name" 2>/dev/null || true
  done
}

stack_purge() {
  [[ -f "$ENV_FILE" ]] || die "missing .env — cannot run compose teardown. Use '$0 down' or restore from .env.example"
  echo "==> docker compose down --remove-orphans -v --rmi all (project $PROJECT_NAME only)"
  stack_compose down --remove-orphans -v --rmi all
  echo "==> prune leftover Docker networks for project $PROJECT_NAME (labels + legacy names)"
  prune_project_networks
}

cmd_trash() {
  require_cmd docker
  if ! parse_yes_flag "$@"; then
    read -r -p "Remove stack '$PROJECT_NAME' (containers, project networks/volumes, service images)? [y/N] " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || { echo "Aborted."; exit 0; }
  fi
  stack_purge
  echo "Done (trash). Host bind mounts (e.g. etc-pihole) are unchanged."
}

cmd_wipe() {
  require_cmd docker
  if ! parse_yes_flag "$@"; then
    read -r -p "Wipe: purge stack '$PROJECT_NAME' (same as trash) AND delete .env + keepalived/assets/keepalived.conf? [y/N] " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || { echo "Aborted."; exit 0; }
  fi
  stack_purge
  echo "==> Removing .env and rendered keepalived/assets/keepalived.conf"
  rm -f "$ENV_FILE" "$KEEPALIVED_CONF"
  echo "Done (wipe). Run: $0 init && $0 up"
}

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
    [[ -f "$ENV_FILE" ]] && existing=1
    [[ -f "$KEEPALIVED_CONF" ]] && existing=1
    if [[ "$existing" -eq 1 ]]; then
      read -r -p ".env or keepalived/assets/keepalived.conf already exist. Overwrite? [y/N]: " ans
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

  mkdir -p "$ROOT/etc-pihole" "$ROOT/etc-dnsmasq.d" "$ROOT/etc-dnscrypt-proxy" "$ROOT/keepalived/assets"

  local neb_pri neb_rep
  neb_pri=$(quote_env_value "http://${primary_ip}|${webpass}")
  neb_rep=$(quote_env_value "http://${peer_ip}|${webpass}")

  cat >"$ENV_FILE" <<EOF
PARENT_INTERFACE=${iface}
MACVLAN_SUBNET=${subnet}
MACVLAN_GATEWAY=${gateway}
PIHOLE_IPV4=${my_pihole}
SERVERIP=${vip}
DNS1=10.0.1.2#5300
DNS2=no
TZ=${tz}
WEBPASSWORD=${web_q}
PRIMARY=${neb_pri}
REPLICAS=${neb_rep}
FULL_SYNC=true
RUN_GRAVITY=true
CRON="*/15 * * * *"
ROUTER_ID=${router_id}
VRRP_STATE=${state}
VRRP_PRIORITY=${priority}
VRRP_AUTH_PASS=${vrrp_q}
UNICAST_SRC_IP=${src_ip}
UNICAST_PEER_IP=${peer_unicast}
VIP_CIDR=${vip_cidr}
EOF
  if [[ "$webpass" == *"|"* ]]; then
    echo "warn: password contains '|' — nebula-sync delimiter; edit .env PRIMARY/REPLICAS manually." >&2
  fi

  render_keepalived_conf

  echo
  echo "Wrote .env and keepalived/assets/keepalived.conf."
  echo "This node: ${role} (${state}). Start stack: $0 up"
}

usage() {
  cat <<EOF
Usage: $0 <command>

  init [--force]   Interactive prompts → .env + keepalived/assets/keepalived.conf
  render-keepalived   Rebuild keepalived/assets/keepalived.conf from .env
  up               docker compose up -d (depends_on + pihole healthcheck in compose.yml)
  down             Stop/remove project $PROJECT_NAME
  trash [--yes]    compose down -v --rmi all for this project
  wipe [--yes]     trash + remove .env and keepalived/assets/keepalived.conf
  pull             Pull images
  ps | logs | config | …   Compose passthrough

Compose: $COMPOSE_FILE  env: $ENV_FILE  project: $PROJECT_NAME
EOF
}

case "${1:-}" in
  init) cmd_init "$@" ;;
  render-keepalived)
    require_cmd envsubst
    preflight_env_files
    render_keepalived_conf
    echo "Wrote $KEEPALIVED_CONF"
    ;;
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
