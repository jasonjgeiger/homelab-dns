# Homelab DNS

HA Pi-hole on two nodes: **keepalived** holds a shared **VIP**; clients keep one DNS address on failover. **dnscrypt-proxy** sits on a private Docker bridge as Pi-hole’s upstream. **[nebula-sync](https://github.com/lovelaze/nebula-sync)** keeps Pi-hole v6 settings aligned between both instances.

There is **no root `compose.yml`**. **`stack.sh`** merges the fragment compose files under a fixed project name (**`pihole`**) and starts services in order: **dnscrypt-proxy → pihole → keepalived → nebula-sync**. **dnscrypt-proxy**, **pihole**, and **keepalived** are defined in **`pihole/compose.yml`** so **`depends_on`** / **`network_mode: service:pihole`** stay valid if only that file is loaded (e.g. Portainer or a single **`-f`**).

## Commands (repo root)

| Command | Purpose |
|---------|---------|
| `./stack.sh init` | Interactive prompts → writes `*/.env` and `keepalived/keepalived.conf` |
| `./stack.sh init --force` | Same, skip overwrite confirmation |
| `./stack.sh up` | Bring the stack up (ordered starts) |
| `./stack.sh down` | Stop/remove project **`pihole`** |
| `./stack.sh trash [--yes]` | **`docker compose down --remove-orphans -v --rmi all`** for project **`pihole` only** (containers, project networks/volumes, service images) |
| `./stack.sh wipe [--yes]` | Same as **`trash`**, then deletes **`pihole/.env`**, **`keepalived/.env`**, **`nebula-sync/.env`**, and **`keepalived/keepalived.conf`** |
| `./stack.sh pull` | Pull images |
| `./stack.sh ps` / `logs` / `config` / `exec` … | Passed through to `docker compose` with the same files and env |

**`trash`** and **`wipe`** ask for confirmation unless you pass **`--yes`** or **`-y`**. Both need the two Compose **`.env`** files (**`pihole`**, **`nebula-sync`**) so **`docker compose`** can resolve the project. **`down`** is lighter (no **`-v`** / **`--rmi`**). Bind-mounted host dirs (e.g. Pi-hole data) are never removed by Compose.

```bash
chmod +x stack.sh   # once
./stack.sh init
./stack.sh up
```

Compose flags: **`--project-directory`** = repo root, **`-p pihole`**, **two** absolute **`-f`** paths (**`pihole/compose.yml`**, **`nebula-sync/compose.yml`**), **two** absolute **`--env-file`** paths (**`pihole/.env`** includes **`PARENT_INTERFACE`** / **`MACVLAN_*`**, **`TZ`** for Pi-hole and dnscrypt). Bind-mount paths are **repo-root-relative**. **`keepalived/.env`** is only for **`envsubst`**, not Compose.

## Deploying on dns1 and dns2

Use the **same git tree** on both servers. On **each** host, local **`.env`** files (and **`keepalived.conf`**) differ only by node role and IPs as below.

| File | dns1 | dns2 |
|------|------|------|
| `pihole/.env` | **`PARENT_INTERFACE`**, **`MACVLAN_SUBNET`**, **`MACVLAN_GATEWAY`** — usually **same** on both. **`PIHOLE_IPV4`** = this host’s Pi-hole IP on macvlan. **`SERVERIP`** = VIP (same both). **`TZ`** used by Pi-hole and dnscrypt. Match **`WEBPASSWORD`** with **`nebula-sync/.env`**. |
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
| `pihole/compose.yml` | **`pihole_macvlan`**, internal bridge, **dnscrypt-proxy**, **pihole**, **keepalived** (`network_mode: service:pihole`) |
| `nebula-sync/compose.yml` | nebula-sync |

Use **`./stack.sh`** (or the same **`-f`** list and **`--project-directory`**) so **nebula-sync** is in the project. **`dnscrypt-proxy/`** and **`keepalived/`** hold only host config (no separate compose files there).

## Repository layout

| Path | Purpose |
|------|---------|
| `stack.sh` | **`init`** (prompts → env + keepalived.conf), **`up`** / **`down`**, compose passthrough |
| `dnscrypt-proxy/` | **`etc-dnscrypt-proxy/`** config (mounted by **`pihole/compose.yml`**) |
| `pihole/` | Compose (**dnscrypt + Pi-hole + keepalived + networks**) + **`pihole/.env`**; data under `etc-pihole/` and `etc-dnsmasq.d/` |
| `keepalived/` | VRRP config only; template → **`keepalived.conf`** (mounted by **`pihole/compose.yml`**) |
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
