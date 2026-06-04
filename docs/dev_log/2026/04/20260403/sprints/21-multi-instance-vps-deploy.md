# Sprint 21 — Multi-Instance VPS Deployment

**Status:** Planned
**Date:** 2026-04-18
**Principles:** DevOps-first · Infrastructure as Code · Repeatable deploys

---

## Goal

Deploy 5 VBWD demo instances on a single Hostinger KVM1 VPS, each with its own domain, database, and plugin configuration. Automated deploys from GitHub Actions with instance selection.

---

## Architecture Decisions

| Decision | Choice |
|----------|--------|
| PostgreSQL | 1 container, 5 databases |
| Redis | 1 container, 5 DB indexes (0-4) |
| Frontend | 1 nginx per instance (path-based: `/` → fe-user, `/admin` → fe-admin) |
| Total containers | 12 (1 PG + 1 Redis + 5 API + 5 nginx) |
| Deploy trigger | GitHub Actions → SSH to VPS, with checkboxes per instance |
| SSL | Wildcard `*.vbwd.cc` via Let's Encrypt + Cloudflare DNS-01 |
| DNS | Move `vbwd.cc` to Cloudflare (free) |
| Subdomain management | Hestia control panel |
| Docker images | Built once on GHCR, pulled 5 times with different `.env` |

---

## Instances

| Domain | DB Name | Redis DB | Plugins | Purpose |
|--------|---------|----------|---------|---------|
| `vbwd.cc` | `vbwd_main` | 0 | subscription, cms, email, taro | Generic SaaS demo |
| `shop.vbwd.cc` | `vbwd_shop` | 1 | subscription, cms, email, shop, checkout, discount, shipping | E-commerce demo |
| `hotel.vbwd.cc` | `vbwd_hotel` | 2 | subscription, cms, email, booking | HoReCa demo |
| `doctor.vbwd.cc` | `vbwd_doctor` | 3 | subscription, cms, email, booking | Medical booking demo |
| `ghrm.vbwd.cc` | `vbwd_ghrm` | 4 | subscription, cms, email, ghrm | Software marketplace demo |

---

## Resource Budget (4GB RAM / 50GB Disk)

```
OS + Hestia + WordPress (ziba.guru):  ~800MB RAM, ~10GB disk
PostgreSQL (1 container, 5 DBs):      ~200MB RAM, ~2GB disk
Redis (1 container):                    ~50MB RAM
5 × API (Gunicorn, 2 workers each):   ~750MB RAM
5 × nginx (static files):             ~150MB RAM
Docker overhead:                       ~200MB RAM
──────────────────────────────────────────────────
Total:                                ~2.1GB RAM, ~15GB disk
Remaining:                            ~1.9GB RAM, ~35GB disk
```

---

## Implementation

### 21a — DNS + SSL Setup

1. Create Cloudflare account (free)
2. Add `vbwd.cc` zone to Cloudflare
3. Update nameservers at Hostinger registrar → Cloudflare NS
4. Add DNS records in Cloudflare:
   - `A vbwd.cc → VPS_IP` (proxy off for now)
   - `A *.vbwd.cc → VPS_IP` (wildcard)
5. Install Cloudflare API token on VPS
6. Configure Hestia to use Cloudflare DNS-01 for Let's Encrypt wildcard
7. Issue wildcard cert: `*.vbwd.cc` + `vbwd.cc`
8. Create subdomains in Hestia: `shop.vbwd.cc`, `hotel.vbwd.cc`, `doctor.vbwd.cc`, `ghrm.vbwd.cc`

### 21b — VPS Docker Infrastructure

Create on VPS:

```
/opt/vbwd/
├── docker-compose.shared.yml     # PostgreSQL + Redis (shared services)
├── docker-compose.instance.yml   # Template for one VBWD instance
├── instances/
│   ├── main/
│   │   ├── .env                  # DB_NAME=vbwd_main, REDIS_DB=0, DOMAIN=vbwd.cc
│   │   └── plugins.json          # subscription, cms, email, taro
│   ├── shop/
│   │   ├── .env
│   │   └── plugins.json          # + shop, checkout, discount, shipping
│   ├── hotel/
│   │   ├── .env
│   │   └── plugins.json          # + booking
│   ├── doctor/
│   │   ├── .env
│   │   └── plugins.json          # + booking
│   └── ghrm/
│       ├── .env
│       └── plugins.json          # + ghrm
├── nginx/
│   ├── vbwd.cc.conf              # proxy_pass to main API + frontend
│   ├── shop.vbwd.cc.conf
│   ├── hotel.vbwd.cc.conf
│   ├── doctor.vbwd.cc.conf
│   └── ghrm.vbwd.cc.conf
├── deploy.sh                     # Deploy script (pull + up per instance)
└── Makefile                      # Convenience commands
```

### 21c — Docker Compose Files

**`docker-compose.shared.yml`** — shared services:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./init-databases.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      POSTGRES_USER: vbwd
      POSTGRES_PASSWORD: ${PG_PASSWORD}
    ports:
      - "127.0.0.1:5432:5432"

  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:6379:6379"
```

**`init-databases.sql`** — creates 5 databases:
```sql
CREATE DATABASE vbwd_main;
CREATE DATABASE vbwd_shop;
CREATE DATABASE vbwd_hotel;
CREATE DATABASE vbwd_doctor;
CREATE DATABASE vbwd_ghrm;
```

**`docker-compose.instance.yml`** — per-instance template:
```yaml
services:
  api:
    image: ghcr.io/vbwd-platform/vbwd_backend:latest
    env_file: .env
    volumes:
      - ./plugins.json:/app/plugins/plugins.json:ro
      - uploads:/app/uploads
    depends_on:
      - postgres
      - redis
    networks:
      - vbwd-net

  frontend:
    image: ghcr.io/vbwd-platform/vbwd_frontend:latest
    env_file: .env
    depends_on:
      - api
    networks:
      - vbwd-net
```

### 21d — Hestia Nginx Proxy Config

Each subdomain in Hestia gets a custom nginx template that proxies to the Docker instance:

```nginx
# /home/admin/conf/web/shop.vbwd.cc/nginx.conf_custom
location / {
    proxy_pass http://127.0.0.1:8002;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Port mapping:
| Instance | API port | Frontend port |
|----------|----------|---------------|
| main | 5001 | 8001 |
| shop | 5002 | 8002 |
| hotel | 5003 | 8003 |
| doctor | 5004 | 8004 |
| ghrm | 5005 | 8005 |

### 21e — GitHub Actions Deploy Workflow

**`.github/workflows/deploy-instances.yml`:**

```yaml
name: Deploy VBWD Instances

on:
  workflow_dispatch:
    inputs:
      instances:
        description: 'Select instances to deploy'
        type: choice
        options:
          - all
          - main
          - shop
          - hotel
          - doctor
          - ghrm
      run_migrations:
        description: 'Run database migrations'
        type: boolean
        default: true
      seed_data:
        description: 'Seed demo data'
        type: boolean
        default: false

jobs:
  build:
    name: Build Docker Images
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - name: Build & push backend image
        uses: docker/build-push-action@v5
        with:
          tags: ghcr.io/vbwd-platform/vbwd_backend:latest
          push: true
      - name: Build & push frontend image
        uses: docker/build-push-action@v5
        with:
          tags: ghcr.io/vbwd-platform/vbwd_frontend:latest
          push: true

  deploy:
    name: Deploy to VPS
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: SSH and deploy
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd /opt/vbwd
            INSTANCES="${{ github.event.inputs.instances }}"
            if [ "$INSTANCES" = "all" ]; then
              INSTANCES="main shop hotel doctor ghrm"
            fi
            for instance in $INSTANCES; do
              echo "=== Deploying $instance ==="
              cd /opt/vbwd/instances/$instance
              docker compose pull
              docker compose up -d
              if [ "${{ github.event.inputs.run_migrations }}" = "true" ]; then
                docker compose exec -T api alembic upgrade head
              fi
              if [ "${{ github.event.inputs.seed_data }}" = "true" ]; then
                docker compose exec -T api python bin/install_demo_data.py
              fi
            done
```

### 21f — Per-Instance `.env` Files

**`instances/main/.env`:**
```env
INSTANCE_NAME=main
DOMAIN=vbwd.cc
DATABASE_URL=postgresql://vbwd:${PG_PASSWORD}@postgres:5432/vbwd_main
REDIS_URL=redis://redis:6379/0
JWT_SECRET_KEY=${JWT_SECRET}
FLASK_ENV=production
API_PORT=5001
FRONTEND_PORT=8001
```

**`instances/shop/.env`:**
```env
INSTANCE_NAME=shop
DOMAIN=shop.vbwd.cc
DATABASE_URL=postgresql://vbwd:${PG_PASSWORD}@postgres:5432/vbwd_shop
REDIS_URL=redis://redis:6379/1
JWT_SECRET_KEY=${JWT_SECRET}
FLASK_ENV=production
API_PORT=5002
FRONTEND_PORT=8002
```

(Same pattern for hotel/3, doctor/4, ghrm/5)

### 21g — Deploy Script on VPS

**`/opt/vbwd/deploy.sh`:**
```bash
#!/bin/bash
# Usage: ./deploy.sh [instance|all] [--migrate] [--seed]

INSTANCE=${1:-all}
MIGRATE=false
SEED=false

for arg in "$@"; do
  case $arg in
    --migrate) MIGRATE=true ;;
    --seed) SEED=true ;;
  esac
done

if [ "$INSTANCE" = "all" ]; then
  INSTANCES="main shop hotel doctor ghrm"
else
  INSTANCES="$INSTANCE"
fi

# Pull latest images
docker pull ghcr.io/vbwd-platform/vbwd_backend:latest
docker pull ghcr.io/vbwd-platform/vbwd_frontend:latest

for inst in $INSTANCES; do
  echo "=== Deploying $inst ==="
  cd /opt/vbwd/instances/$inst
  docker compose up -d --force-recreate
  
  if $MIGRATE; then
    docker compose exec -T api alembic upgrade head
  fi
  
  if $SEED; then
    docker compose exec -T api python bin/install_demo_data.py
  fi
  
  echo "=== $inst deployed ==="
done
```

### 21h — Initial Setup Script

**`/opt/vbwd/setup.sh`** — run once on fresh VPS:
```bash
#!/bin/bash
# 1. Install Docker
# 2. Start shared services (PG + Redis)
# 3. Create databases
# 4. Pull images
# 5. Start all instances
# 6. Run migrations
# 7. Seed demo data
```

---

## Deployment Flow

```
Developer pushes to main
  ↓
GitHub Actions: "Deploy VBWD Instances"
  ☑ all / ☐ main / ☐ shop / ☐ hotel / ☐ doctor / ☐ ghrm
  ☑ Run migrations
  ☐ Seed demo data
  ↓
CI builds Docker images → pushes to GHCR
  ↓
CI SSHs into VPS → runs deploy.sh
  ↓
Each selected instance:
  1. docker compose pull (get latest image)
  2. docker compose up -d (restart with new image)
  3. alembic upgrade head (if checked)
  4. install_demo_data.py (if checked)
  ↓
Live at vbwd.cc / shop.vbwd.cc / hotel.vbwd.cc / doctor.vbwd.cc / ghrm.vbwd.cc
```

---

## Sub-Sprint Order

| # | Task | Effort |
|---|------|--------|
| 21a | DNS: Move vbwd.cc to Cloudflare, wildcard cert | 30 min |
| 21b | VPS: Create /opt/vbwd directory structure | 15 min |
| 21c | Docker: Shared services + instance compose files | 1 hour |
| 21d | Hestia: Create subdomains + nginx proxy configs | 30 min |
| 21e | GitHub Actions: Deploy workflow with checkboxes | 30 min |
| 21f | Config: .env + plugins.json per instance | 30 min |
| 21g | Scripts: deploy.sh + setup.sh on VPS | 30 min |
| 21h | Initial deploy: all 5 instances live | 1 hour |
| **Total** | | **~5 hours** |

---

## Not in Scope

- Auto-scaling (single VPS, fixed resources)
- Database backups (add later via pg_dump cron)
- Monitoring (add later via Uptime Kuma or similar)
- CDN (Cloudflare proxy can be enabled later)
- CI/CD for plugin-specific deploys (all instances use same image)
