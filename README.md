# Homelab DNS

HA Pi-hole on two nodes: **keepalived** holds a shared **VIP**; clients keep one DNS address on failover. **dnscrypt-proxy** sits on a private Docker bridge as Pi-hole’s upstream.

## Which Compose file to run

Run **only the root project** from this repository’s **top level**:

```bash
docker compose --project-directory . up -d
```

That command loads **`compose.yml`**, which **`include`s** these fragments (each with its own **`env_file`**):

| Included file | Role |
|---------------|------|
| `macvlan/compose.yml` | Macvlan network `pihole_macvlan` |
| `dnscrypt-proxy/compose.yml` | Internal bridge + dnscrypt-proxy |
| `pihole/compose.yml` | Pi-hole |
| `keepalived/compose.yml` | keepalived (`network_mode: service:pihole`) |

**Do not** run `docker compose` from inside `pihole/`, `macvlan/`, etc. alone—you would get an incomplete project (missing networks, peers, or mounts). **`--project-directory .`** must be the repo root so bind mounts like `./dns-setup/...` and `./keepalived/...` resolve correctly.

Equivalent without `include` (older tooling) would be the same four `-f` paths plus `--project-directory "$(pwd)"`; the root **`compose.yml`** is the supported entrypoint.

## Deploying on dns1 and dns2

Use the **same git tree** on both servers (clone, rsync, or pull). On **each** host you maintain **local** `.env` files (not committed). The **compose files are identical** on dns1 and dns2; only **env values** (and rendered **`keepalived/keepalived.conf`**) differ.

| File | dns1 | dns2 |
|------|------|------|
| `macvlan/.env` | Usually **same** on both (parent NIC, subnet, gateway for the shared LAN). |
| `dnscrypt-proxy/.env` | Usually **same** (e.g. `TZ`). |
| `pihole/.env` | **`PIHOLE_IPV4`** = this host’s Pi-hole IP on macvlan. **`SERVERIP`** = VIP (same both). Match **`WEBPASSWORD`** if you want one admin login / nebula-sync. |
| `keepalived/.env` | **`ROUTER_ID`** unique per node. **`VRRP_STATE`** `MASTER` on preferred primary, **`BACKUP`** on the other. **`VRRP_PRIORITY`** higher on primary (e.g. 110 vs 100). **`UNICAST_SRC_IP`** = this node’s LAN IP; **`UNICAST_PEER_IP`** = the other node’s LAN IP. **`VIP_CIDR`** and **`VRRP_AUTH_PASS`** **must match** on both. |

After editing **`keepalived/.env`** on a host, re-render config on **that** host:

```bash
(cd keepalived && set -a && source .env && set +a && envsubst < keepalived.conf.template > keepalived.conf)
```

Then from the repo root:

```bash
docker compose --project-directory . up -d
```

**Example (illustrative IPs)**  

| | dns1 | dns2 |
|--|------|------|
| Pi-hole on macvlan | `192.168.100.5` | `192.168.100.10` |
| VIP (DHCP DNS for clients) | `192.168.100.100` | `192.168.100.100` |
| VRRP | `MASTER`, priority `110` | `BACKUP`, priority `100` |
| Unicast src / peer | src `.5`, peer `.10` | src `.10`, peer `.5` |

## First-time setup on each server

```bash
cp macvlan/.env.example macvlan/.env
cp dnscrypt-proxy/.env.example dnscrypt-proxy/.env
cp pihole/.env.example pihole/.env
cp keepalived/.env.example keepalived/.env
```

Edit the `.env` files per the dns1/dns2 table above, render **`keepalived.conf`** (command above), then **`docker compose --project-directory . up -d`**.

**Old external network:** if `pihole_macvlan` already exists from a manual `docker network create`, remove it once: `docker network rm pihole_macvlan`, then bring the stack up again.

## Repository layout

| Path | Purpose |
|------|---------|
| `compose.yml` | Root Compose project (`include` + per-fragment `env_file`, Compose **v2.24+**) |
| `macvlan/` | Macvlan network |
| `dnscrypt-proxy/` | Internal bridge + dnscrypt; `etc-dnscrypt-proxy/` |
| `pihole/` | Pi-hole |
| `keepalived/` | VRRP sidecar; `keepalived.conf.template` → `keepalived.conf` |
| `dns-setup/` | Pi-hole data dirs, notify/check scripts, optional `create_macvlan.sh` |
| `nebula-sync/` | Optional Pi-hole v6 config sync |

Git ignores `*/.env`, `keepalived/keepalived.conf`, and `nebula-sync/.env`.

## Requirements

- Docker and Compose **v2.24+**
- `gettext` / `envsubst` for `keepalived.conf`

## Optional

- **`dns-setup/create_macvlan.sh`** — emergency `docker network create` only; Compose normally owns the macvlan from `macvlan/`.
- **[nebula-sync](https://github.com/lovelaze/nebula-sync)** — `cd nebula-sync && ./deploy.sh`. See upstream for replicas / `webserver.api.app_sudo`.
- **Pi-hole password** — after changing `WEBPASSWORD`, recreate `pihole` or run `docker exec -it pihole pihole setpassword`.

## Validate

```bash
./dns-setup/validate_all.sh
```
