# Homelab DNS

HA Pi-hole (two nodes, keepalived VIP) with dnscrypt upstream. Compose stacks live at the **repo root**: `dnscrypt-proxy/`, `pihole-core/`, and `keepalived/`; root `compose.yml` **`include`**s them (Docker Compose **2.24+**). Config, env files, and data dirs stay in **`dns-node/`**; run **`dns-node/deploy.sh`** from there (it calls `docker compose` from the repo root).

| | IP |
|--|-----|
| VM1 | 192.168.100.5 |
| VM2 | 192.168.100.10 |
| VIP (client DNS) | 192.168.100.100 |

## Secrets (set before deploy)

**`dns-node/.env.vm1` and `dns-node/.env.vm2`**

| Variable | Notes |
|----------|--------|
| `WEBPASSWORD` | Pi-hole web UI + API password (use the **same** value on both nodes if you want one login; nebula-sync needs it too). |
| `VRRP_AUTH_PASS` | keepalived VRRP shared secret — **must match on both nodes**. |

**`nebula-sync/.env`** (if you use sync)

| Variable | Notes |
|----------|--------|
| `PRIMARY` / `REPLICAS` | URLs use `http://host|password` — replace the password segment with each Pi-hole’s web/API password (same idea as `WEBPASSWORD`). |

Do not commit real values: root `.gitignore` excludes `dns-node/.env`, `nebula-sync/.env`, and `dns-node/keepalived.conf` once generated.

## Deploy

```bash
cd dns-node
chmod +x deploy.sh create_macvlan.sh check_pihole.sh notify.sh validate.sh validate_all.sh
./deploy.sh .env.vm1   # first node
./deploy.sh .env.vm2   # second node
```

Also adjust non-secret settings in `.env.vm*` as needed (e.g. `PARENT_INTERFACE`, IPs). Copy `dns-node/.env.example` if you build a custom `.env`.

From the **repo root** (Compose 2.24+): `docker compose --env-file dns-node/.env.vm1 up -d`. Otherwise same three `-f` paths as in `dns-node/deploy.sh`.

## Optional

- **`nebula-sync/`** — sync Pi-hole v6 config between nodes ([nebula-sync](https://github.com/lovelaze/nebula-sync)). `./deploy.sh` there; set `.env` from `.env.example`.
- **Web login** — `WEBPASSWORD` in `.env` is applied via `FTLCONF_webserver_api_password`; recreate the `pihole` container after changes, or run `docker exec -it pihole pihole setpassword`.

## Check

```bash
./dns-node/validate_all.sh
```
