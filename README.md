# Homelab DNS

HA Pi-hole on two nodes: **keepalived** holds a shared **VIP**; clients keep one DNS address on failover. **dnscrypt-proxy** sits on a private Docker bridge as Pi-hole’s upstream. **[nebula-sync](https://github.com/lovelaze/nebula-sync)** keeps Pi-hole v6 settings aligned between both instances.

## Which Compose file to run

Run **only the root project** from this repository’s **top level**:

```bash
docker compose --project-directory . up -d
```

That command loads **`compose.yml`**, which **`include`s** these fragments (each with its own **`env_file`** where noted):

| Included file | Role |
|---------------|------|
| `macvlan/compose.yml` | Macvlan network `pihole_macvlan` |
| `dnscrypt-proxy/compose.yml` | Internal bridge + dnscrypt-proxy |
| `pihole/compose.yml` | Pi-hole |
| `keepalived/compose.yml` | keepalived (`network_mode: service:pihole`) |
| `nebula-sync/compose.yml` | Pi-hole v6 config sync (`PRIMARY` / `REPLICAS` in `nebula-sync/.env`) |

**Do not** run `docker compose` from inside `pihole/`, `macvlan/`, etc. alone—you would get an incomplete project (missing networks, peers, or mounts).

**Bind mounts in `include`d fragments** are resolved relative to **that fragment’s `compose.yml`**, not the repo root (for example `keepalived/compose.yml` uses **`./keepalived.conf`** next to that file). **`--project-directory .`** should still be the repo root when you invoke Compose from there.

Equivalent without `include` (older tooling) would be the same **five** `-f` paths plus `--project-directory "$(pwd)"`; the root **`compose.yml`** is the supported entrypoint.

## Deploying on dns1 and dns2

Use the **same git tree** on both servers (clone, rsync, or pull). On **each** host you maintain **local** `.env` files (not committed). The **compose files are identical** on dns1 and dns2; only **env values** (and rendered **`keepalived/keepalived.conf`**) differ.

| File | dns1 | dns2 |
|------|------|------|
| `macvlan/.env` | Usually **same** on both (parent NIC, subnet, gateway for the shared LAN). |
| `dnscrypt-proxy/.env` | Usually **same** (e.g. `TZ`). |
| `pihole/.env` | **`PIHOLE_IPV4`** = this host’s Pi-hole IP on macvlan. **`SERVERIP`** = VIP (same both). Match **`WEBPASSWORD`** with **`nebula-sync/.env`** (password segment in `PRIMARY` / `REPLICAS` URLs). |
| `keepalived/.env` | **`ROUTER_ID`** unique per node. **`VRRP_STATE`** `MASTER` on preferred primary, **`BACKUP`** on the other. **`VRRP_PRIORITY`** higher on primary (e.g. 110 vs 100). **`UNICAST_SRC_IP`** = this node’s LAN IP; **`UNICAST_PEER_IP`** = the other node’s LAN IP. **`VIP_CIDR`** and **`VRRP_AUTH_PASS`** **must match** on both. |
| `nebula-sync/.env` | Usually **same** on both nodes: **`PRIMARY`** and **`REPLICAS`** list both Pi-hole base URLs and passwords (`http://ip\|password`). Each host runs its own `nebula-sync` container; identical config keeps both pointed at the same pair of instances. |

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
chmod +x init-env.sh   # once
./init-env.sh
```

**`init-env.sh`** walks through prompts: this node is **primary** (MASTER) or **peer** (BACKUP), primary and peer **Pi-hole IPs**, **VIP**, **macvlan subnet** and **gateway**, optional NIC (**`eth0`** default) and **timezone**, then **Pi-hole web password** and **VRRP shared secret** (typed twice each). It writes **`macvlan/.env`**, **`dnscrypt-proxy/.env`**, **`pihole/.env`**, **`keepalived/.env`**, **`nebula-sync/.env`**, and renders **`keepalived/keepalived.conf`**. Run it on **each** host with the **same** IPs, VIP, subnet, gateway, passwords, and secret; only **primary vs peer** changes. Use **`--force`** to skip the overwrite confirmation if files already exist.

Alternatively, copy from each **`*.env.example`** and edit by hand (see the dns1/dns2 table), then render **`keepalived.conf`** with **`envsubst`**.

Then **`docker compose --project-directory . up -d`** from the repo root.

**Old external network:** if `pihole_macvlan` already exists from a manual `docker network create`, remove it once: `docker network rm pihole_macvlan`, then bring the stack up again.

## Repository layout

| Path | Purpose |
|------|---------|
| `compose.yml` | Root Compose project (`include` + per-fragment `env_file`, Compose **v2.24+**) |
| `init-env.sh` | Interactive setup: writes `*/.env` and `keepalived/keepalived.conf` from prompts |
| `macvlan/` | Macvlan network |
| `dnscrypt-proxy/` | Internal bridge + dnscrypt; `etc-dnscrypt-proxy/` |
| `pihole/` | Pi-hole; persistent data under `etc-pihole/` and `etc-dnsmasq.d/` |
| `keepalived/` | VRRP sidecar; `keepalived.conf.template` → `keepalived.conf` |
| `nebula-sync/` | Pi-hole v6 sync (required; wired into root `compose.yml`) |

Git ignores `*/.env`, `keepalived/keepalived.conf`, and `nebula-sync/.env`.

## Requirements

- Docker and Compose **v2.24+**
- `gettext` / `envsubst` for `keepalived.conf`
- Pi-hole instances reachable from each host running the stack (for nebula-sync `PRIMARY` / `REPLICAS` URLs)

## Optional

- **Pi-hole password** — after changing `WEBPASSWORD`, update **`nebula-sync/.env`** URL passwords, recreate `pihole`, and run `docker exec -it pihole pihole setpassword` if needed.
- **Replicas / app passwords** — see [nebula-sync](https://github.com/lovelaze/nebula-sync) for `webserver.api.app_sudo` and related Pi-hole v6 settings.
