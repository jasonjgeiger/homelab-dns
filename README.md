# Homelab DNS

HA Pi-hole on two nodes: **keepalived** holds a shared **VIP**; clients keep one DNS address on failover. **dnscrypt-proxy** sits on a private Docker bridge as Pi-hole’s upstream. **[nebula-sync](https://github.com/lovelaze/nebula-sync)** keeps Pi-hole v6 settings aligned between both instances.

There is **no root `compose.yml`**. **`stack.sh`** merges the fragment compose files under a fixed project name (**`pihole`**) and starts services in order: **dnscrypt-proxy → pihole → keepalived → nebula-sync**.

## Commands (repo root)

| Command | Purpose |
|---------|---------|
| `./stack.sh init` | Interactive prompts → writes `*/.env` and `keepalived/keepalived.conf` |
| `./stack.sh init --force` | Same, skip overwrite confirmation |
| `./stack.sh up` | Bring the stack up (ordered starts) |
| `./stack.sh down` | Stop/remove project **`pihole`** |
| `./stack.sh trash [--yes]` | **`docker compose down --remove-orphans -v --rmi all`** for project **`pihole` only** (containers, project networks, compose/volume data, images used by these services) |
| `./stack.sh wipe [--yes]` | Same as **`trash`**, then deletes **`macvlan/.env`**, **`dnscrypt-proxy/.env`**, **`pihole/.env`**, **`keepalived/.env`**, **`nebula-sync/.env`**, and **`keepalived/keepalived.conf`** |
| `./stack.sh pull` | Pull images |
| `./stack.sh ps` / `logs` / `config` / `exec` … | Passed through to `docker compose` with the same files and env |

**`trash`** and **`wipe`** ask for confirmation unless you pass **`--yes`** or **`-y`**. Both need all four Compose **`.env`** files present so **`docker compose`** can resolve the project. **`down`** is lighter (no **`-v`** / **`--rmi`**). Bind-mounted host dirs (e.g. Pi-hole data) are never removed by Compose.

```bash
chmod +x stack.sh   # once
./stack.sh init
./stack.sh up
```

Compose flags used internally: **`--project-directory`** = repo root, **`-p pihole`**, five **`-f`** fragment paths, four **`--env-file`** entries (`macvlan`, `dnscrypt-proxy`, `pihole`, `nebula-sync`). **`keepalived/.env`** is not passed to Compose (only used to render **`keepalived.conf`**).

**Bind mounts** in each fragment are still resolved relative to **that fragment’s `compose.yml`** (e.g. **`keepalived/keepalived.conf`** beside **`keepalived/compose.yml`**).

## Deploying on dns1 and dns2

Use the **same git tree** on both servers. On **each** host, local **`.env`** files (and **`keepalived.conf`**) differ only by node role and IPs as below.

| File | dns1 | dns2 |
|------|------|------|
| `macvlan/.env` | Usually **same** on both (parent NIC, subnet, gateway for the shared LAN). |
| `dnscrypt-proxy/.env` | Usually **same** (e.g. `TZ`). |
| `pihole/.env` | **`PIHOLE_IPV4`** = this host’s Pi-hole IP on macvlan. **`SERVERIP`** = VIP (same both). Match **`WEBPASSWORD`** with **`nebula-sync/.env`** (password segment in `PRIMARY` / `REPLICAS` URLs). |
| `keepalived/.env` | **`ROUTER_ID`** unique per node. **`VRRP_STATE`** `MASTER` on preferred primary, **`BACKUP`** on the other. **`VRRP_PRIORITY`** higher on primary (e.g. 110 vs 100). **`UNICAST_SRC_IP`** / **`UNICAST_PEER_IP`** swapped per node. **`VIP_CIDR`** and **`VRRP_AUTH_PASS`** **must match** on both. |
| `nebula-sync/.env` | Usually **same** on both nodes: **`PRIMARY`** and **`REPLICAS`** (`http://ip\|password`). |

After editing **`keepalived/.env`**, re-render **`keepalived.conf`**:

```bash
(cd keepalived && set -a && source .env && set +a && envsubst < keepalived.conf.template > keepalived.conf)
```

Then **`./stack.sh up`** again as needed.

**Example (illustrative IPs)**  

| | dns1 | dns2 |
|--|------|------|
| Pi-hole on macvlan | `192.168.100.5` | `192.168.100.10` |
| VIP (DHCP DNS for clients) | `192.168.100.100` | `192.168.100.100` |
| VRRP | `MASTER`, priority `110` | `BACKUP`, priority `100` |
| Unicast src / peer | src `.5`, peer `.10` | src `.10`, peer `.5` |

## Fragment compose files (merged by stack.sh)

| File | Role |
|------|------|
| `macvlan/compose.yml` | Macvlan network `pihole_macvlan` |
| `dnscrypt-proxy/compose.yml` | Internal bridge + dnscrypt-proxy |
| `pihole/compose.yml` | Pi-hole |
| `keepalived/compose.yml` | keepalived (`network_mode: service:pihole`) |
| `nebula-sync/compose.yml` | nebula-sync |

Do not run **`docker compose -f …`** on a **single** fragment alone; you will miss networks, env merge, or mounts.

## Repository layout

| Path | Purpose |
|------|---------|
| `stack.sh` | **`init`** (prompts → env + keepalived.conf), **`up`** / **`down`**, compose passthrough |
| `macvlan/` | Macvlan network compose + `.env` |
| `dnscrypt-proxy/` | dnscrypt + `etc-dnscrypt-proxy/` |
| `pihole/` | Pi-hole; data under `etc-pihole/` and `etc-dnsmasq.d/` |
| `keepalived/` | VRRP; template → **`keepalived.conf`** (mounted by Compose) |
| `nebula-sync/` | nebula-sync compose + `.env` |

Git ignores `*/.env`, `keepalived/keepalived.conf`, and `nebula-sync/.env`.

## Requirements

- Docker and Compose **v2.24+**
- `gettext` / `envsubst` for **`keepalived.conf`** (and **`stack.sh init`**)
- Pi-hole IPs reachable from each host for nebula-sync

## Optional

- **Pi-hole password** — after changing `WEBPASSWORD`, update **`nebula-sync/.env`**, recreate **`pihole`**, and/or `docker exec -it pihole pihole setpassword`.
- **Replicas / app passwords** — [nebula-sync](https://github.com/lovelaze/nebula-sync) docs.

**Old external network:** if **`pihole_macvlan`** already exists from a manual **`docker network create`**, remove it once: **`docker network rm pihole_macvlan`**, then **`./stack.sh up`**.
