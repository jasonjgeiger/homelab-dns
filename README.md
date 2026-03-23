# Homelab DNS

HA Pi-hole: **keepalived** VIP, **dnscrypt-proxy** on **`pihole_net`**, **[nebula-sync](https://github.com/lovelaze/nebula-sync)**.

**`compose.yml`** (project **`pihole`**) — **dnscrypt-proxy → pihole → keepalived → nebula-sync**.

**`.env`** at repo root holds Compose vars, nebula-sync, and VRRP keys. **`./stack.sh up`** / **`init`** render **`keepalived/assets/keepalived.conf`** from **`keepalived/keepalived.conf.template`** (do not `source` **`.env`** in bash — **`DNS1`** uses **`#`**).

## Commands

| Command | Purpose |
|---------|---------|
| `./stack.sh init` | Writes **`.env`**, renders **`keepalived/assets/keepalived.conf`** |
| `./stack.sh render-keepalived` | Rebuild **`keepalived/assets/keepalived.conf`** after VRRP edits in **`.env`** |
| `./stack.sh up` | Render keepalived, then ordered **`docker compose up`** |
| `./stack.sh down` / `trash` / `wipe` / `pull` / `ps` … | See **`./stack.sh --help`** |

```bash
chmod +x stack.sh
cp .env.example .env
# edit .env, then:
./stack.sh render-keepalived
./stack.sh up
```

**Compose:** **`--project-directory`** = repo root, **`-f compose.yml`**, **`--env-file .env`**.

## Layout

| Path | Role |
|------|------|
| `compose.yml` | All services |
| `.env` | Secrets + VRRP + nebula (**`.env.example`**) |
| `etc-pihole/`, `etc-dnsmasq.d/` | Pi-hole data |
| `etc-dnscrypt-proxy/` | dnscrypt config |
| `keepalived/assets/` | **`notify.sh`** (tracked stub for osixia startup) + generated **`keepalived.conf`** (gitignored), mounted at **`/container/service/keepalived/assets`**; **`KEEPALIVED_CONF`** points at that file ([osixia/container-keepalived](https://github.com/osixia/container-keepalived)) |

## Requirements

**Docker Engine 29.x** (e.g. 29.3.0) with Compose **v2** — file follows the [Compose specification](https://docs.docker.com/compose/compose-file/) (no obsolete top-level **`version`**). **`envsubst`** (**gettext**) for **`stack.sh`**.

**keepalived image:** load **`ip_vs`** on the host (`sudo modprobe ip_vs`) as required by [osixia/keepalived](https://github.com/osixia/container-keepalived). The compose service uses **`cap_add`**: **`NET_ADMIN`**, **`NET_RAW`**, **`NET_BROADCAST`** (same as the project’s quick start). If VIP failover misbehaves on your kernel, you can temporarily add **`privileged: true`** under **`keepalived`** in **`compose.yml`**.
