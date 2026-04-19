#!/usr/bin/env bash
# ============================================================================
# VBWD Multi-Instance VPS Setup Script
# Sprint 21 — Deploy 5 VBWD demo instances on a single KVM1 VPS
#
# Prerequisites (already done in Sprint 21a):
#   - DNS: vbwd.cc + *.vbwd.cc pointed to VPS via Cloudflare
#   - SSL: Wildcard cert at /etc/letsencrypt/live/vbwd.cc/
#   - Hestia: 5 domains created (vbwd.cc, shop/hotel/doctor/ghrm.vbwd.cc)
#   - Docker: installed and running
#
# Usage:
#   scp recipes/vps-setup.sh root@147.93.121.176:/opt/vps-setup.sh
#   ssh root@147.93.121.176 bash /opt/vps-setup.sh
# ============================================================================
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

VBWD_ROOT="/opt/vbwd"
HESTIA_USER="admin"
GHCR_REGISTRY="ghcr.io/vbwd-platform"

# Generate passwords if not already set
PG_PASSWORD="${PG_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 32 | tr -d '/+=' | head -c 48)}"
FLASK_SECRET="${FLASK_SECRET:-$(openssl rand -base64 32 | tr -d '/+=' | head -c 48)}"

# Instance definitions: name:domain:redis_db:api_port:fe_user_port:fe_admin_port:plugins
INSTANCES=(
  "main:vbwd.cc:0:5001:8001:8101:subscription,cms,email,taro"
  "shop:shop.vbwd.cc:1:5002:8002:8102:subscription,cms,email,shop,checkout,discount,shipping"
  "hotel:hotel.vbwd.cc:2:5003:8003:8103:subscription,cms,email,booking"
  "doctor:doctor.vbwd.cc:3:5004:8004:8104:subscription,cms,email,booking"
  "ghrm:ghrm.vbwd.cc:4:5005:8005:8105:subscription,cms,email,ghrm"
)

# ── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[VBWD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }
step() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}\n"; }

# ── Helper: parse instance definition ────────────────────────────────────────

parse_instance() {
  local definition="$1"
  INSTANCE_NAME=$(echo "$definition" | cut -d: -f1)
  INSTANCE_DOMAIN=$(echo "$definition" | cut -d: -f2)
  INSTANCE_REDIS_DB=$(echo "$definition" | cut -d: -f3)
  INSTANCE_API_PORT=$(echo "$definition" | cut -d: -f4)
  INSTANCE_FE_USER_PORT=$(echo "$definition" | cut -d: -f5)
  INSTANCE_FE_ADMIN_PORT=$(echo "$definition" | cut -d: -f6)
  INSTANCE_PLUGINS=$(echo "$definition" | cut -d: -f7)
}

# ============================================================================
# Step 1: Create directory structure
# ============================================================================

step "Step 1: Creating directory structure"

mkdir -p "${VBWD_ROOT}"/{instances,nginx}
for definition in "${INSTANCES[@]}"; do
  parse_instance "$definition"
  mkdir -p "${VBWD_ROOT}/instances/${INSTANCE_NAME}"
done

log "Directory structure created at ${VBWD_ROOT}/"

# ============================================================================
# Step 2: Create Docker network
# ============================================================================

step "Step 2: Creating shared Docker network"

if docker network inspect vbwd-shared >/dev/null 2>&1; then
  log "Network 'vbwd-shared' already exists"
else
  docker network create vbwd-shared
  log "Network 'vbwd-shared' created"
fi

# ============================================================================
# Step 3: Write shared .env (passwords)
# ============================================================================

step "Step 3: Writing shared secrets"

cat > "${VBWD_ROOT}/.env" <<ENVEOF
PG_PASSWORD=${PG_PASSWORD}
JWT_SECRET=${JWT_SECRET}
FLASK_SECRET=${FLASK_SECRET}
ENVEOF

chmod 600 "${VBWD_ROOT}/.env"
log "Secrets written to ${VBWD_ROOT}/.env"

# ============================================================================
# Step 4: Write docker-compose.shared.yml (PostgreSQL + Redis)
# ============================================================================

step "Step 4: Writing shared services compose file"

cat > "${VBWD_ROOT}/docker-compose.shared.yml" <<'COMPOSEEOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: vbwd-postgres
    restart: unless-stopped
    command: postgres -c max_connections=200 -c shared_buffers=256MB
    environment:
      POSTGRES_USER: vbwd
      POSTGRES_PASSWORD: ${PG_PASSWORD}
      POSTGRES_DB: vbwd_main
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./init-databases.sql:/docker-entrypoint-initdb.d/init.sql:ro
    ports:
      - "127.0.0.1:5432:5432"
    networks:
      - vbwd-shared
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U vbwd"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: vbwd-redis
    restart: unless-stopped
    command: redis-server --maxmemory 64mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:6379:6379"
    networks:
      - vbwd-shared
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pg_data:
  redis_data:

networks:
  vbwd-shared:
    external: true
COMPOSEEOF

log "Shared services compose written"

# ============================================================================
# Step 5: Write init-databases.sql
# ============================================================================

step "Step 5: Writing database init script"

cat > "${VBWD_ROOT}/init-databases.sql" <<'SQLEOF'
-- Create databases for each VBWD instance
-- (vbwd_main is created by POSTGRES_DB env var)
SELECT 'CREATE DATABASE vbwd_shop' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'vbwd_shop')\gexec
SELECT 'CREATE DATABASE vbwd_hotel' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'vbwd_hotel')\gexec
SELECT 'CREATE DATABASE vbwd_doctor' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'vbwd_doctor')\gexec
SELECT 'CREATE DATABASE vbwd_ghrm' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'vbwd_ghrm')\gexec
SQLEOF

log "Database init script written"

# ============================================================================
# Step 6: Write per-instance docker-compose.yml + .env + plugins.json
# ============================================================================

step "Step 6: Writing per-instance configurations"

for definition in "${INSTANCES[@]}"; do
  parse_instance "$definition"
  instance_dir="${VBWD_ROOT}/instances/${INSTANCE_NAME}"

  log "Configuring instance: ${INSTANCE_NAME} (${INSTANCE_DOMAIN})"

  # ── docker-compose.yml ──
  cat > "${instance_dir}/docker-compose.yml" <<COMPOSEEOF
services:
  api:
    image: ${GHCR_REGISTRY}/vbwd_backend:latest
    container_name: vbwd-${INSTANCE_NAME}-api
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./plugins.json:/app/plugins/plugins.json:ro
      - uploads:/app/uploads
      - logs:/app/logs
    networks:
      - default
      - vbwd-shared
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:5000/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  fe-user:
    image: ${GHCR_REGISTRY}/vbwd_fe_user:latest
    container_name: vbwd-${INSTANCE_NAME}-fe-user
    restart: unless-stopped
    environment:
      - API_UPSTREAM=api:5000
    ports:
      - "127.0.0.1:${INSTANCE_FE_USER_PORT}:80"
    depends_on:
      api:
        condition: service_healthy
    networks:
      - default

  fe-admin:
    image: ${GHCR_REGISTRY}/vbwd_fe_admin:latest
    container_name: vbwd-${INSTANCE_NAME}-fe-admin
    restart: unless-stopped
    environment:
      - API_UPSTREAM=api:5000
    ports:
      - "127.0.0.1:${INSTANCE_FE_ADMIN_PORT}:80"
    depends_on:
      api:
        condition: service_healthy
    networks:
      - default

volumes:
  uploads:
  logs:

networks:
  vbwd-shared:
    external: true
COMPOSEEOF

  # ── .env ──
  cat > "${instance_dir}/.env" <<ENVINSTEOF
INSTANCE_NAME=${INSTANCE_NAME}
DOMAIN=${INSTANCE_DOMAIN}
FLASK_ENV=production
FLASK_SECRET_KEY=${FLASK_SECRET}
JWT_SECRET_KEY=${JWT_SECRET}
DATABASE_URL=postgresql://vbwd:${PG_PASSWORD}@postgres:5432/vbwd_${INSTANCE_NAME}
REDIS_URL=redis://redis:6379/${INSTANCE_REDIS_DB}
GUNICORN_WORKERS=2
LOG_LEVEL=warning
ENVINSTEOF

  chmod 600 "${instance_dir}/.env"

  # ── plugins.json ──
  # Convert comma-separated plugin list to JSON
  plugins_json='{"plugins":{'
  first=true
  IFS=',' read -ra plugin_list <<< "${INSTANCE_PLUGINS}"
  for plugin in "${plugin_list[@]}"; do
    if [ "$first" = true ]; then
      first=false
    else
      plugins_json+=','
    fi
    plugins_json+="\"${plugin}\":{\"enabled\":true,\"version\":\"1.0.0\",\"source\":\"local\"}"
  done
  plugins_json+='}}'
  echo "$plugins_json" | python3 -m json.tool > "${instance_dir}/plugins.json"

  log "  docker-compose.yml + .env + plugins.json written"
done

# ============================================================================
# Step 7: Write Hestia nginx proxy configs
# ============================================================================

step "Step 7: Writing Hestia nginx proxy configs"

for definition in "${INSTANCES[@]}"; do
  parse_instance "$definition"

  # Hestia custom nginx config path
  hestia_conf_dir="/home/${HESTIA_USER}/conf/web/${INSTANCE_DOMAIN}"
  mkdir -p "${hestia_conf_dir}"

  cat > "${hestia_conf_dir}/nginx.conf_custom" <<NGINXEOF
# VBWD instance: ${INSTANCE_NAME} (${INSTANCE_DOMAIN})
# Auto-generated by vps-setup.sh — do not edit manually

# Admin panel (fe-admin serves on /admin/)
location /admin/ {
    proxy_pass http://127.0.0.1:${INSTANCE_FE_ADMIN_PORT}/admin/;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 60s;
}

# User frontend (fe-user handles /, /api/, /uploads/)
location / {
    proxy_pass http://127.0.0.1:${INSTANCE_FE_USER_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 60s;
}
NGINXEOF

  log "  ${INSTANCE_DOMAIN} → fe-user :${INSTANCE_FE_USER_PORT}, fe-admin :${INSTANCE_FE_ADMIN_PORT}"
done

# Reload nginx to apply configs
if command -v nginx &>/dev/null; then
  nginx -t && systemctl reload nginx
  log "Nginx reloaded"
else
  warn "Nginx not found — reload manually after installing"
fi

# ============================================================================
# Step 8: Write deploy.sh
# ============================================================================

step "Step 8: Writing deploy script"

cat > "${VBWD_ROOT}/deploy.sh" <<'DEPLOYEOF'
#!/usr/bin/env bash
# ============================================================================
# VBWD Deploy Script
# Usage: ./deploy.sh [instance|all] [--migrate] [--seed] [--pull]
#
# Examples:
#   ./deploy.sh all --migrate              # Deploy all, run migrations
#   ./deploy.sh shop --migrate --seed      # Deploy shop with migrations + seed
#   ./deploy.sh main --pull                # Just pull + restart main
# ============================================================================
set -euo pipefail

VBWD_ROOT="/opt/vbwd"
INSTANCE="${1:-all}"
MIGRATE=false
SEED=false
PULL_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --migrate) MIGRATE=true ;;
    --seed)    SEED=true ;;
    --pull)    PULL_ONLY=true ;;
  esac
done

ALL_INSTANCES="main shop hotel doctor ghrm"

if [ "$INSTANCE" = "all" ]; then
  DEPLOY_LIST="$ALL_INSTANCES"
else
  DEPLOY_LIST="$INSTANCE"
fi

# Source shared secrets
source "${VBWD_ROOT}/.env"

# Pull latest images once (shared across all instances)
echo "=== Pulling latest images ==="
docker pull ghcr.io/vbwd-platform/vbwd_backend:latest &
docker pull ghcr.io/vbwd-platform/vbwd_fe_user:latest &
docker pull ghcr.io/vbwd-platform/vbwd_fe_admin:latest &
wait
echo "=== Images pulled ==="

for instance_name in $DEPLOY_LIST; do
  instance_dir="${VBWD_ROOT}/instances/${instance_name}"

  if [ ! -d "$instance_dir" ]; then
    echo "ERROR: Instance directory not found: ${instance_dir}"
    continue
  fi

  echo ""
  echo "=== Deploying ${instance_name} ==="

  cd "$instance_dir"

  # Recreate containers with new images
  docker compose up -d --force-recreate --remove-orphans

  if [ "$PULL_ONLY" = true ]; then
    echo "=== ${instance_name}: containers restarted ==="
    continue
  fi

  # Wait for API health
  echo "  Waiting for API health..."
  for attempt in $(seq 1 30); do
    if docker compose exec -T api curl -sf http://localhost:5000/api/v1/health >/dev/null 2>&1; then
      echo "  API healthy after ${attempt} attempts"
      break
    fi
    if [ "$attempt" -eq 30 ]; then
      echo "  WARNING: API health check timed out for ${instance_name}"
    fi
    sleep 2
  done

  if [ "$MIGRATE" = true ]; then
    echo "  Running migrations..."
    docker compose exec -T api alembic upgrade heads || {
      echo "  WARNING: Migration failed for ${instance_name}"
    }
  fi

  if [ "$SEED" = true ]; then
    echo "  Seeding demo data..."
    docker compose exec -T api python bin/install_demo_data.py 2>/dev/null || \
    docker compose exec -T api flask seed-test-data 2>/dev/null || {
      echo "  WARNING: Seed failed for ${instance_name} (may not have seed scripts)"
    }
  fi

  echo "=== ${instance_name} deployed ==="
done

echo ""
echo "=== Deploy complete ==="
docker ps --filter "name=vbwd-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
DEPLOYEOF

chmod +x "${VBWD_ROOT}/deploy.sh"
log "Deploy script written to ${VBWD_ROOT}/deploy.sh"

# ============================================================================
# Step 9: Write Makefile for convenience
# ============================================================================

step "Step 9: Writing Makefile"

cat > "${VBWD_ROOT}/Makefile" <<'MAKEEOF'
.PHONY: up down status deploy logs ps shared-up shared-down

# Start shared services (PostgreSQL + Redis)
shared-up:
	cd /opt/vbwd && docker compose -f docker-compose.shared.yml --env-file .env up -d

# Stop shared services
shared-down:
	cd /opt/vbwd && docker compose -f docker-compose.shared.yml down

# Start all instances
up: shared-up
	@for inst in main shop hotel doctor ghrm; do \
		echo "Starting $$inst..."; \
		cd /opt/vbwd/instances/$$inst && docker compose up -d; \
	done

# Stop all instances
down:
	@for inst in main shop hotel doctor ghrm; do \
		echo "Stopping $$inst..."; \
		cd /opt/vbwd/instances/$$inst && docker compose down 2>/dev/null || true; \
	done

# Deploy all with migrations
deploy:
	/opt/vbwd/deploy.sh all --migrate

# Deploy specific instance (usage: make deploy-shop)
deploy-%:
	/opt/vbwd/deploy.sh $* --migrate

# Show all VBWD containers
ps:
	docker ps --filter "name=vbwd-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Show status
status: ps
	@echo ""
	@echo "=== Disk usage ==="
	@du -sh /opt/vbwd/ 2>/dev/null || true
	@echo ""
	@echo "=== Memory ==="
	@free -h | head -2

# Tail logs for instance (usage: make logs-shop)
logs-%:
	cd /opt/vbwd/instances/$* && docker compose logs -f --tail=50

# Tail all API logs
logs:
	docker logs -f --tail=50 $$(docker ps -q --filter "name=vbwd-.*-api" | head -1)

# Restart specific instance (usage: make restart-shop)
restart-%:
	cd /opt/vbwd/instances/$* && docker compose restart

# Database backup
backup:
	@mkdir -p /opt/vbwd/backups
	@for db in vbwd_main vbwd_shop vbwd_hotel vbwd_doctor vbwd_ghrm; do \
		echo "Backing up $$db..."; \
		docker exec vbwd-postgres pg_dump -U vbwd $$db | gzip > /opt/vbwd/backups/$$db-$$(date +%Y%m%d-%H%M%S).sql.gz; \
	done
	@echo "Backups saved to /opt/vbwd/backups/"
MAKEEOF

log "Makefile written"

# ============================================================================
# Step 10: Write cert renewal cron
# ============================================================================

step "Step 10: Setting up cert auto-renewal"

CRON_CMD="0 3 1,15 * * certbot renew --quiet --post-hook 'systemctl reload nginx' 2>/dev/null"

if crontab -l 2>/dev/null | grep -q "certbot renew"; then
  log "Certbot renewal cron already exists"
else
  (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
  log "Certbot renewal cron added (1st and 15th of each month, 03:00)"
fi

# ============================================================================
# Step 11: Start shared services
# ============================================================================

step "Step 11: Starting shared services (PostgreSQL + Redis)"

cd "${VBWD_ROOT}"
docker compose -f docker-compose.shared.yml --env-file .env up -d

# Wait for PostgreSQL
log "Waiting for PostgreSQL..."
for attempt in $(seq 1 30); do
  if docker exec vbwd-postgres pg_isready -U vbwd >/dev/null 2>&1; then
    log "PostgreSQL ready after ${attempt} attempts"
    break
  fi
  sleep 2
done

# Verify databases were created
log "Verifying databases..."
docker exec vbwd-postgres psql -U vbwd -d postgres -tc "SELECT datname FROM pg_database WHERE datname LIKE 'vbwd_%' ORDER BY datname;" | tr -d ' '

# ============================================================================
# Summary
# ============================================================================

step "Setup Complete"

echo -e "${GREEN}Directory structure:${NC}"
find "${VBWD_ROOT}" -maxdepth 3 -type f | sort | head -40

echo ""
echo -e "${GREEN}Shared services:${NC}"
docker ps --filter "name=vbwd-postgres" --filter "name=vbwd-redis" --format "table {{.Names}}\t{{.Status}}"

echo ""
echo -e "${GREEN}Secrets stored in:${NC} ${VBWD_ROOT}/.env"
echo -e "${YELLOW}IMPORTANT: Save these credentials securely:${NC}"
echo "  PG_PASSWORD=${PG_PASSWORD}"
echo "  JWT_SECRET=${JWT_SECRET}"
echo "  FLASK_SECRET=${FLASK_SECRET}"

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Log in to GHCR:  echo 'YOUR_PAT' | docker login ghcr.io -u dantweb --password-stdin"
echo "  2. Deploy all:      cd /opt/vbwd && ./deploy.sh all --migrate --seed"
echo "  3. Check status:    make -C /opt/vbwd ps"
echo ""
echo -e "${GREEN}Instance URLs:${NC}"
for definition in "${INSTANCES[@]}"; do
  parse_instance "$definition"
  echo "  https://${INSTANCE_DOMAIN}/"
  echo "  https://${INSTANCE_DOMAIN}/admin/"
done
