# Homelab DNS

**High availability (HA)** Pi-hole: two nodes share a **virtual IP (VIP)** via keepalived so clients keep using one DNS address if a node fails. Upstream queries go through **dnscrypt-proxy** on a private Docker bridge, then Pi-hole.

## Layout

| Path | Purpose |
|------|---------|
| **`dns-setup/`** | Per-node env (`.env.vm1` / `.env.vm2`), `deploy.sh`, `validate.sh`, `validate_all.sh`, macvlan + keepalived helpers, `etc-dnscrypt-proxy/`, and data dirs `pihole/` + `dnsmasq.d/` (bind-mounted into the container) |
| **`dnscrypt-proxy/`** | Compose fragment: internal network + dnscrypt |
| **`pihole/`** | Compose fragment: Pi-hole service + macvlan |
| **`keepalived/`** | Compose fragment: VRRP sidecar (`network_mode: service:pihole`) |
| **`compose.yml`** (repo root) | Merges the three fragments with Compose **`include`** (Docker Compose **2.24+**) |
| **`nebula-sync/`** | Optional Pi-hole v6 config sync between nodes |

## Example IPs

| Role | Address |
|------|---------|
| Pi-hole on VM1 | 192.168.100.5 |
| Pi-hole on VM2 | 192.168.100.10 |
| VIP (set in DHCP for clients) | 192.168.100.100 |

Change these in `dns-setup/.env.vm*` to match your LAN.

## Prerequisites

- Docker + Docker Compose v2 on each DNS node  
- `gettext` / `envsubst` (for `deploy.sh`)  
- Same macvlan + keepalived VIP settings on both nodes; unique per-node Pi-hole IP and keepalived priority  

## Secrets (before deploy)

**`dns-setup/.env.vm1` and `dns-setup/.env.vm2`**

| Variable | Notes |
|----------|--------|
| `WEBPASSWORD` | Pi-hole web + API password; use the **same** on both nodes if you want one login (needed for nebula-sync too). |
| `VRRP_AUTH_PASS` | keepalived shared secret — **must match on both nodes**. |

**`nebula-sync/.env`** (if you use sync): `PRIMARY` / `REPLICAS` use `http://host|password` — set the password part to each node’s Pi-hole password.

`.gitignore` excludes `dns-setup/.env`, `dns-setup/keepalived.conf`, and `nebula-sync/.env` so secrets are not committed by default.

## Deploy

```bash
cd dns-setup
chmod +x deploy.sh create_macvlan.sh check_pihole.sh notify.sh validate.sh validate_all.sh
./deploy.sh .env.vm1   # first node
./deploy.sh .env.vm2   # second node
```

Tune `PARENT_INTERFACE`, subnets, and IPs in `.env.vm*`. Copy `dns-setup/.env.example` to build a custom `.env`.

**From the repo root** (Compose 2.24+):  
`docker compose --env-file dns-setup/.env.vm1 up -d`  

Older Compose: same three `-f` files as in `dns-setup/deploy.sh`.

## Optional

- **[nebula-sync](https://github.com/lovelaze/nebula-sync)** — `cd nebula-sync && ./deploy.sh` (creates `.env` from `.env.example` on first run). On replicas, enable `webserver.api.app_sudo` if you use app passwords (see upstream README).  
- **Web login** — `WEBPASSWORD` is applied as `FTLCONF_webserver_api_password`. After changing it, recreate the `pihole` container or run `docker exec -it pihole pihole setpassword`.

## Validate

```bash
./dns-setup/validate_all.sh
```

Runs `dns-setup/validate.sh` (stack files + `docker compose config`) and `nebula-sync/validate.sh`.
