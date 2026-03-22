# Homelab DNS

**High availability (HA)** Pi-hole: two nodes share a **virtual IP (VIP)** via keepalived so clients keep using one DNS address if a node fails. Upstream queries go through **dnscrypt-proxy** on a private Docker bridge, then Pi-hole.

## Layout

| Path | Purpose |
|------|---------|
| **`dns-setup/`** | Pi-hole data dirs (`pihole/`, `dnsmasq.d/`), health/notify scripts, optional macvlan helper |
| **`macvlan/`** | `compose.yml`, **`.env`** (from `.env.example`) — Docker macvlan network `pihole_macvlan` |
| **`dnscrypt-proxy/`** | `compose.yml`, **`.env`** (from `.env.example`), internal bridge + dnscrypt; **`etc-dnscrypt-proxy/`** |
| **`pihole/`** | `compose.yml`, **`.env`** (from `.env.example`), Pi-hole on macvlan + internal bridge |
| **`keepalived/`** | `compose.yml`, **`.env`** (from `.env.example`), **`keepalived.conf.template`**, rendered **`keepalived.conf`** |
| **`compose.yml`** (repo root) | Merges fragments with Compose **`include`** + per-fragment **`env_file`** (Docker Compose **2.24+**) |
| **`nebula-sync/`** | Optional Pi-hole v6 config sync between nodes |

## Example IPs

| Role | Address |
|------|---------|
| Pi-hole on VM1 | 192.168.100.5 |
| Pi-hole on VM2 | 192.168.100.10 |
| VIP (set in DHCP for clients) | 192.168.100.100 |

Adjust **`macvlan/.env`** (LAN / parent NIC), **`pihole/.env`**, and **`keepalived/.env`** on each node (IPs, VRRP role, priority).

## Prerequisites

- Docker + Docker Compose **v2.24+** (for `include` + per-include `env_file`)
- `gettext` / `envsubst` (to render `keepalived.conf` from the template)
- Same VIP, subnet, and `VRRP_AUTH_PASS` on both nodes; unique per-node Pi-hole IP and keepalived priority

## Secrets

| Location | Notes |
|----------|--------|
| **`macvlan/.env`** | Host NIC + subnet/gateway for the macvlan network (typically **same** on both nodes). |
| **`pihole/.env`** | `WEBPASSWORD` — same on both nodes if you want one login (needed for nebula-sync too). |
| **`keepalived/.env`** | `VRRP_AUTH_PASS` — **must match on both nodes**. |

**`nebula-sync/.env`** (if used): `PRIMARY` / `REPLICAS` use `http://host|password` — password part matches Pi-hole.

`.gitignore` excludes each service **`.env`**, **`keepalived/keepalived.conf`**, and **`nebula-sync/.env`**.

## Deploy

**1.** Copy env templates (once per machine, then edit):

```bash
cp macvlan/.env.example macvlan/.env
cp dnscrypt-proxy/.env.example dnscrypt-proxy/.env
cp pihole/.env.example pihole/.env
cp keepalived/.env.example keepalived/.env
```

**2.** Render keepalived config (after editing **`keepalived/.env`**):

```bash
cd keepalived && set -a && source .env && set +a && envsubst < keepalived.conf.template > keepalived.conf && cd ..
```

**3.** Bring the stack up from the **repo root**:

```bash
docker compose --project-directory . up -d
```

`--project-directory .` is required so volume paths in the fragments resolve from the repo root.

On the **second node**, use different **`pihole/.env`** (e.g. `PIHOLE_IPV4`) and **`keepalived/.env`** (e.g. `ROUTER_ID`, `VRRP_STATE`, `VRRP_PRIORITY`, unicast IPs), then repeat steps 2–3.

If you still have an **external** Docker network named `pihole_macvlan` from an older layout, remove it once (`docker network rm pihole_macvlan`) so Compose can create it from **`macvlan/compose.yml`** + **`macvlan/.env`**.

## Optional

- **`dns-setup/create_macvlan.sh`** — only for manual recovery; Compose creates the network from **`macvlan/compose.yml`** + **`macvlan/.env`**.
- **[nebula-sync](https://github.com/lovelaze/nebula-sync)** — `cd nebula-sync && ./deploy.sh` (creates `.env` from `.env.example` on first run). On replicas, enable `webserver.api.app_sudo` if you use app passwords (see upstream README).
- **Web login** — `WEBPASSWORD` is applied as `FTLCONF_webserver_api_password`. After changing it, recreate the `pihole` container or run `docker exec -it pihole pihole setpassword`.

## Validate

```bash
./dns-setup/validate_all.sh
```

Runs `dns-setup/validate.sh` (layout, keepalived template, `docker compose config` when `.env` files exist) and `nebula-sync/validate.sh`.
