#!/bin/bash
set -e

# VBWD Community Edition - Development Installation Script
# Works for both local development and GitHub Actions
# Usage: ./recipes/dev-install-ce.sh [--domain <hostname>] [--ssl]
#                                    [--admin-email <addr>] [--admin-password <pw>]
# Or set VBWD_DOMAIN / VBWD_SSL / VBWD_ADMIN_EMAIL / VBWD_ADMIN_PASSWORD env
# vars before running.
#
# Examples:
#   ./recipes/dev-install-ce.sh                              # http://localhost, admin@vbwd.local / admin123
#   ./recipes/dev-install-ce.sh --domain myapp.com          # http://myapp.com
#   ./recipes/dev-install-ce.sh --domain myapp.com --ssl    # https://myapp.com
#   VBWD_DOMAIN=myapp.com VBWD_SSL=1 ./recipes/dev-install-ce.sh
#   ./recipes/dev-install-ce.sh --admin-email me@x.io --admin-password 'S3cret!'
#
# The default admin (admin@vbwd.local / admin123) is for LOCAL DEVELOPMENT
# ONLY. The Step 3.6 routine rotates an existing admin's password to whatever
# the caller passed, so you can re-run this script with new credentials.

# Parse arguments
DOMAIN="${VBWD_DOMAIN:-localhost}"
SSL="${VBWD_SSL:-0}"
ADMIN_EMAIL="${VBWD_ADMIN_EMAIL:-admin@vbwd.local}"
ADMIN_PASSWORD="${VBWD_ADMIN_PASSWORD:-admin123}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --ssl)
            SSL=1
            shift
            ;;
        --admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --admin-password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Derive protocol prefixes from SSL flag
if [ "$SSL" = "1" ]; then
    HTTP="https"
    WS="wss"
else
    HTTP="http"
    WS="ws"
fi

echo "=========================================="
echo "VBWD CE Development Environment Setup"
echo "=========================================="

# Detect environment
if [ -n "$GITHUB_ACTIONS" ]; then
    IS_CI=true
    WORKSPACE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
    echo "Running in GitHub Actions"
else
    IS_CI=false
    WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    echo "Running in local development environment"
fi

echo "Workspace: $WORKSPACE_DIR"

# Configuration
BACKEND_REPO="https://github.com/VBWD-platform/vbwd-backend.git"
# Frontend repositories (split into 3 independent repos with git submodules)
FE_CORE_REPO="https://github.com/VBWD-platform/vbwd-fe-core.git"
FE_USER_REPO="https://github.com/VBWD-platform/vbwd-fe-user.git"
FE_ADMIN_REPO="https://github.com/VBWD-platform/vbwd-fe-admin.git"

BACKEND_DIR="$WORKSPACE_DIR/vbwd-backend"
FE_CORE_DIR="$WORKSPACE_DIR/vbwd-fe-core"
FE_USER_DIR="$WORKSPACE_DIR/vbwd-fe-user"
FE_ADMIN_DIR="$WORKSPACE_DIR/vbwd-fe-admin"

# Port configuration
FE_USER_PORT=8080
FE_ADMIN_PORT=8081

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is available
check_port_available() {
    local port=$1
    if command_exists lsof; then
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            return 1  # Port in use
        fi
    elif command_exists netstat; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            return 1  # Port in use
        fi
    fi
    return 0  # Port available
}

# Function to wait for service
wait_for_service() {
    local service_name=$1
    local url=$2
    local max_attempts=${3:-30}
    local attempt=1

    echo "Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            echo "$service_name is ready!"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: $service_name not ready yet..."
        sleep 2
        attempt=$((attempt + 1))
    done

    echo "ERROR: $service_name failed to start within expected time"
    return 1
}

# Check prerequisites
echo ""
echo "Checking prerequisites..."
if ! command_exists git; then
    echo "ERROR: git is not installed"
    exit 1
fi

if ! command_exists docker; then
    echo "ERROR: docker is not installed"
    exit 1
fi

if ! command_exists docker compose; then
    echo "ERROR: docker compose is not installed"
    exit 1
fi

echo "All prerequisites met"

# Clone backend repository
echo ""
echo "=========================================="
echo "Step 1: Setting up vbwd-backend"
echo "=========================================="

if [ -d "$BACKEND_DIR/.git" ]; then
    echo "Backend directory already exists, pulling latest changes..."
    cd "$BACKEND_DIR"
    git pull origin main || true
else
    echo "Cloning vbwd-backend..."
    rm -rf "$BACKEND_DIR"
    git clone --branch main "$BACKEND_REPO" "$BACKEND_DIR"
    cd "$BACKEND_DIR"
fi

# Setup backend environment
if [ ! -f "$BACKEND_DIR/.env" ]; then
    echo "Creating backend .env file..."
    if [ -f "$BACKEND_DIR/.env.example" ]; then
        cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env"
    else
        # Create minimal .env if example doesn't exist
        cat > "$BACKEND_DIR/.env" << 'EOF'
# Database Configuration
POSTGRES_PASSWORD=vbwd
POSTGRES_DB=vbwd
POSTGRES_USER=vbwd
DATABASE_URL=postgresql://vbwd:vbwd@postgres:5432/vbwd

# Flask Configuration
FLASK_ENV=development
FLASK_SECRET_KEY=dev-secret-key-change-in-production
FLASK_APP=src/app.py

# Redis Configuration
REDIS_URL=redis://redis:6379/0

# LoopAI Integration (Optional)
LOOPAI_API_URL=http://loopai-web:5000
LOOPAI_API_KEY=dev-api-key
LOOPAI_AGENT_ID=1

# Email Configuration (Optional)
SMTP_HOST=localhost
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
EOF
    fi
    echo "Backend .env file created"
else
    echo "Backend .env file already exists"
fi

# Install backend plugins (each hosted in its own repo)
echo ""
echo "=========================================="
echo "Step 1.5: Installing backend plugins"
echo "=========================================="

for plugin in \
    analytics booking chat checkout cms discount email ghrm mailchimp \
    meinchat paypal shop stripe subscription taro token_payment; do
    PLUGIN_DIR="$BACKEND_DIR/plugins/$plugin"
    # GitHub repo names are kebab-case; on-disk plugin dirs are the python
    # snake_case import names. Map underscores → hyphens for the URL only.
    plugin_repo_name="${plugin//_/-}"
    PLUGIN_REPO="https://github.com/VBWD-platform/vbwd-plugin-${plugin_repo_name}.git"
    if [ -d "$PLUGIN_DIR/.git" ]; then
        echo "Plugin $plugin already installed, pulling..."
        cd "$PLUGIN_DIR" && git pull origin main || true
    else
        echo "Cloning plugin $plugin (from vbwd-plugin-${plugin_repo_name})..."
        rm -rf "$PLUGIN_DIR"
        git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
    fi
done
echo "✓ Backend plugins installed"

# Initialize plugins.json from dist if not present
if [ ! -f "$BACKEND_DIR/plugins/plugins.json" ]; then
    cp "$BACKEND_DIR/plugins/plugins.json.dist" "$BACKEND_DIR/plugins/plugins.json"
    echo "✓ plugins.json created from plugins.json.dist"
fi

# Seed ${VAR_DIR}/plugins/ — the canonical, server-side plugin manifest
# directory shared across api / fe-admin / fe-user (see
# docs/architecture/plugin-management.md). All six files MUST exist
# before the backend container starts; the backend refuses to manage a
# frontend app whose env-var-configured manifest is missing.
VAR_DIR="${VBWD_VAR_DIR:-$WORKSPACE_DIR/var}"
mkdir -p "$VAR_DIR/plugins"
echo ""
echo "Seeding $VAR_DIR/plugins/ (idempotent — admin edits via UI are preserved)"

seed_manifest() {
    src="$1"
    dst="$VAR_DIR/plugins/$2"
    if [ -f "$dst" ]; then
        echo "  skip  $(basename "$dst") — already exists"
    elif [ -f "$src" ]; then
        cp "$src" "$dst"
        echo "  seed  $(basename "$dst") ← $src"
    else
        # Source missing: still create an empty JSON manifest so `make up`
        # bind-mounts a real file. Leaving it absent makes Docker auto-create
        # the host path as a directory, breaking the file mount.
        echo '{}' > "$dst"
        echo "  WARN  $src not found; wrote empty $(basename "$dst")"
    fi
}

# Backend manifests can be seeded now (backend repo + plugins already cloned).
# Frontend manifests are seeded later in Step 2 — AFTER the fe-user / fe-admin
# repos are cloned — because their source files (plugins/config.json) do not
# exist until then. Seeding them here would leave var/plugins/fe-*-config.json
# absent, and `make up` would then bind-mount a non-existent host path that
# Docker auto-creates as a directory, failing the file mount.
seed_manifest "$BACKEND_DIR/plugins/plugins.json"           backend-plugins.json
seed_manifest "$BACKEND_DIR/plugins/config.json"            backend-plugins-config.json

echo "✓ Backend plugin manifests seeded into $VAR_DIR/plugins/"
echo "  Export VBWD_VAR_DIR before 'docker compose up' if you want to"
echo "  keep this directory somewhere other than $WORKSPACE_DIR/var"

# Clone and setup frontend repositories (3 independent repos with submodules)
echo ""
echo "=========================================="
echo "Step 2: Setting up Frontend (3 repos: core, user, admin)"
echo "=========================================="

# Step 2a: Clone and build vbwd-fe-core (base library - must build first)
echo ""
echo "Step 2a: Setting up vbwd-fe-core (shared component library)"
echo "==========================================================="

if [ -d "$FE_CORE_DIR/.git" ]; then
    echo "Core library directory already exists, pulling latest changes..."
    cd "$FE_CORE_DIR"
    git pull origin main || true
else
    echo "Cloning vbwd-fe-core..."
    rm -rf "$FE_CORE_DIR"
    git clone "$FE_CORE_REPO" "$FE_CORE_DIR"
    cd "$FE_CORE_DIR"
fi

echo "Building vbwd-fe-core..."
if command_exists docker compose || command_exists docker; then
    cd "$FE_CORE_DIR"
    if [ -f "docker-compose.yaml" ] || [ -f "docker-compose.yml" ]; then
        # Use Docker Compose if available
        docker compose run --rm build npm install && npm run build || true
    else
        npm install
        npm run build
    fi
else
    npm install
    npm run build
fi
echo "✓ vbwd-fe-core built successfully"

# Step 2b: Clone vbwd-fe-user with submodule
echo ""
echo "Step 2b: Setting up vbwd-fe-user (user-facing app)"
echo "=================================================="

if [ -d "$FE_USER_DIR/.git" ]; then
    echo "User app directory already exists, updating submodules..."
    cd "$FE_USER_DIR"
    git pull origin main || true
    git submodule update --init --recursive || true
else
    echo "Cloning vbwd-fe-user with submodules..."
    rm -rf "$FE_USER_DIR"
    git clone --recurse-submodules "$FE_USER_REPO" "$FE_USER_DIR"
    cd "$FE_USER_DIR"
fi

# Verify submodule
if [ -d "$FE_USER_DIR/vbwd-fe-core" ] && [ -f "$FE_USER_DIR/vbwd-fe-core/package.json" ]; then
    echo "✓ Submodule vbwd-fe-core initialized"
else
    echo "WARNING: Submodule vbwd-fe-core may not be properly initialized"
fi

echo "Building vbwd-fe-core submodule for vbwd-fe-user..."
cd "$FE_USER_DIR/vbwd-fe-core"
npm install && npm run build && rm -rf node_modules

echo "Installing dependencies for vbwd-fe-user..."
cd "$FE_USER_DIR"
npm install
echo "✓ vbwd-fe-user dependencies installed"

echo "Installing vbwd-fe-user plugins..."
for plugin in \
    booking chat checkout cms ghrm landing1 meinchat \
    paypal-payment shop stripe-payment subscription taro \
    theme-switcher token-payment; do
    PLUGIN_DIR="$FE_USER_DIR/plugins/$plugin"
    PLUGIN_REPO="https://github.com/VBWD-platform/vbwd-fe-user-plugin-${plugin}.git"
    if [ -d "$PLUGIN_DIR/.git" ]; then
        echo "Plugin $plugin already installed, pulling..."
        cd "$PLUGIN_DIR" && git pull origin main || true
    else
        echo "Cloning fe-user plugin $plugin..."
        rm -rf "$PLUGIN_DIR"
        git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
    fi
done
echo "✓ vbwd-fe-user plugins installed"

# Step 2c: Clone vbwd-fe-admin with submodule
echo ""
echo "Step 2c: Setting up vbwd-fe-admin (admin backoffice)"
echo "===================================================="

if [ -d "$FE_ADMIN_DIR/.git" ]; then
    echo "Admin app directory already exists, updating submodules..."
    cd "$FE_ADMIN_DIR"
    git pull origin main || true
    git submodule update --init --recursive || true
else
    echo "Cloning vbwd-fe-admin with submodules..."
    rm -rf "$FE_ADMIN_DIR"
    git clone --recurse-submodules "$FE_ADMIN_REPO" "$FE_ADMIN_DIR"
    cd "$FE_ADMIN_DIR"
fi

# Verify submodule
if [ -d "$FE_ADMIN_DIR/vbwd-fe-core" ] && [ -f "$FE_ADMIN_DIR/vbwd-fe-core/package.json" ]; then
    echo "✓ Submodule vbwd-fe-core initialized"
else
    echo "WARNING: Submodule vbwd-fe-core may not be properly initialized"
fi

echo "Building vbwd-fe-core submodule for vbwd-fe-admin..."
cd "$FE_ADMIN_DIR/vbwd-fe-core"
npm install && npm run build && rm -rf node_modules

echo "Installing dependencies for vbwd-fe-admin..."
cd "$FE_ADMIN_DIR"
npm install
echo "✓ vbwd-fe-admin dependencies installed"

echo "Installing vbwd-fe-admin plugins..."
for plugin in \
    analytics-widget booking cms-admin discount-admin email-admin \
    ghrm-admin meinchat-admin shop-admin subscription-admin \
    taro-admin token-payment-admin; do
    PLUGIN_DIR="$FE_ADMIN_DIR/plugins/$plugin"
    PLUGIN_REPO="https://github.com/VBWD-platform/vbwd-fe-admin-plugin-${plugin}.git"
    if [ -d "$PLUGIN_DIR/.git" ]; then
        echo "Plugin $plugin already installed, pulling..."
        cd "$PLUGIN_DIR" && git pull origin main || true
    else
        echo "Cloning fe-admin plugin $plugin..."
        rm -rf "$PLUGIN_DIR"
        git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
    fi
done
echo "✓ vbwd-fe-admin plugins installed"

# Seed the frontend plugin manifests now that the fe-user / fe-admin repos
# (and their plugins/config.json source files) exist. These MUST be present
# as files before `make up`, otherwise Docker auto-creates the missing
# var/plugins/fe-*-config.json host path as a directory and the read-only
# bind mount onto /app/vue/public/config.json fails.
echo ""
echo "Seeding frontend plugin manifests into $VAR_DIR/plugins/"
seed_manifest "$FE_ADMIN_DIR/plugins/plugins.json"          fe-admin-plugins.json
seed_manifest "$FE_ADMIN_DIR/plugins/config.json"           fe-admin-plugins-config.json
seed_manifest "$FE_USER_DIR/plugins/plugins.json"           fe-user-plugins.json
seed_manifest "$FE_USER_DIR/plugins/config.json"            fe-user-plugins-config.json
echo "✓ Frontend plugin manifests seeded into $VAR_DIR/plugins/"

# Setup frontend environment files
echo ""
echo "Setting up environment files for frontend apps..."

for FE_DIR in "$FE_USER_DIR" "$FE_ADMIN_DIR"; do
    FE_NAME=$(basename "$FE_DIR")
    if [ ! -f "$FE_DIR/.env" ]; then
        # VITE_API_URL is a relative path so it works via the nginx proxy on any domain.
        # VITE_BACKEND_URL is the Vite dev-server proxy target (only used by `npm run dev`).
        cat > "$FE_DIR/.env" << EOF
VITE_API_URL=/api/v1
VITE_BACKEND_URL=${HTTP}://${DOMAIN}:5000
VITE_WS_URL=${WS}://${DOMAIN}:5000
EOF
        echo "✓ Environment file created for $FE_NAME (domain: $DOMAIN)"
    fi
done

# Start Docker containers
echo ""
echo "=========================================="
echo "Step 3: Starting Docker containers"
echo "=========================================="

cd "$BACKEND_DIR"

# Stop any existing containers
echo "Stopping any existing containers..."
docker compose down -v || true

# Build and start containers
echo "Building and starting containers..."
if [ "$IS_CI" = true ]; then
    # In CI, use detached mode and wait for services
    docker compose up -d --build
else
    # In local dev, also use detached mode
    docker compose up -d --build
fi

# Wait for services to be ready
echo ""
echo "Waiting for services to start..."
sleep 5

# Check backend health
if wait_for_service "Backend API" "${HTTP}://${DOMAIN}:5000/api/v1/health" 60; then
    echo "Backend API is running on ${HTTP}://${DOMAIN}:5000"
else
    echo "ERROR: Backend API failed to start"
    echo "Checking backend logs..."
    docker compose logs api
    exit 1
fi

# Check database
echo "Checking database connection..."
if docker compose exec -T api python -c "from sqlalchemy import create_engine; import os; e=create_engine(os.getenv('DATABASE_URL', 'postgresql://vbwd:vbwd@postgres:5432/vbwd')); c=e.connect(); print('Database: OK'); c.close()" 2>/dev/null; then
    echo "Database is connected and ready"
else
    echo "WARNING: Database connection check failed"
    docker compose logs postgres
fi

# Run database migrations
echo ""
echo "=========================================="
echo "Step 3.5: Running database migrations"
echo "=========================================="

if [ -f "$WORKSPACE_DIR/recipes/run_migrations.sh" ]; then
    echo "Running database migrations..."
    bash "$WORKSPACE_DIR/recipes/run_migrations.sh" upgrade
    if [ $? -eq 0 ]; then
        echo "Database migrations completed!"
    else
        echo "WARNING: Database migrations may have failed - check logs"
    fi
else
    echo "WARNING: run_migrations.sh not found, skipping migrations"
fi

# Create the default admin user.
#
# Idempotent: bin/create_admin.sh inside the backend container does an
# upsert — if the email exists it ensures the user is ACTIVE + has the
# ADMIN role; if absent it creates one with the supplied password. Re-runs
# of this recipe with different --admin-password values rotate the password
# of the existing admin to the new value, so the script stays a single
# source of truth for "what does it take to log into this stack."
#
# Defaults (admin@vbwd.local / admin123) are LOCAL DEV ONLY. Override per
# run with --admin-email / --admin-password or VBWD_ADMIN_EMAIL /
# VBWD_ADMIN_PASSWORD.
echo ""
echo "=========================================="
echo "Step 3.6: Creating default admin user"
echo "=========================================="

cd "$BACKEND_DIR"
if [ -f "$BACKEND_DIR/bin/create_admin.sh" ]; then
    echo "Creating / upserting admin: $ADMIN_EMAIL"
    if bash "$BACKEND_DIR/bin/create_admin.sh" "$ADMIN_EMAIL" "$ADMIN_PASSWORD"; then
        echo "✓ Admin user ready: $ADMIN_EMAIL"
    else
        echo "WARNING: admin-user creation failed — check backend logs"
        echo "  (you can retry with: cd $BACKEND_DIR && ./bin/create_admin.sh '$ADMIN_EMAIL' '$ADMIN_PASSWORD')"
    fi
else
    echo "WARNING: $BACKEND_DIR/bin/create_admin.sh not found — admin not created"
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 3.7 — Populate plugin demo data (CMS, booking, shop, ghrm, discount,
# token_payment). Each plugin's populate-db.sh is idempotent (upserts), so
# re-running this recipe is safe.
#
# Order matters: CMS first (creates layouts/widgets/styles/pages — required
# by booking + shop + ghrm which themselves emit CMS layouts + pages).
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "Step 3.7: Populating plugin demo data"
echo "=========================================="

cd "$BACKEND_DIR"
POPULATE_PLUGINS=(cms booking shop ghrm discount token_payment)

for plugin in "${POPULATE_PLUGINS[@]}"; do
    populate_sh="$BACKEND_DIR/plugins/$plugin/bin/populate-db.sh"
    if [ -f "$populate_sh" ]; then
        echo ""
        echo "── Populating $plugin ──"
        if bash "$populate_sh"; then
            echo "✓ $plugin demo data populated"
        else
            echo "WARNING: $plugin populate failed — check logs"
        fi
    else
        echo "WARNING: $populate_sh not found — skipping $plugin populate"
    fi
done

# ──────────────────────────────────────────────────────────────────────────
# Step 3.8 — CMS images + default-home routing rules
#
# (a) Register every file in $BACKEND_DIR/uploads/images/ as a CmsImage row.
#     Image files are already on disk inside the container via the bind
#     mount (vbwd-backend bind-mounts the whole repo at /app); this step
#     just makes them visible in the admin media gallery + reusable in
#     widgets/pages. Idempotent: each file's slug-derived row is upserted.
#
# (b) Routing rules: ensure `/` (default) and `/index.html` both resolve
#     to the CMS page slug `home`. If a page `home` doesn't exist yet,
#     clone `home1` → `home` so the rule has a real landing target.
#     Goes through the CMS service layer — no raw SQL.
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "Step 3.8: Importing CMS images + default-home routing"
echo "=========================================="

cd "$BACKEND_DIR"
docker compose exec -T api python - <<'PYEOF'
"""dev-install-ce: register seed CMS images + ensure / and /index.html → /home.

All writes go through the CMS service / repository layer per
feedback_no_direct_db_for_test_data. Idempotent: re-running is a no-op
once seeded.
"""
import mimetypes
import os
import sys
from pathlib import Path

from vbwd.app_factory import create_app
from vbwd.extensions import db

app = create_app()

with app.app_context():
    # ── (a) CMS image gallery seeding ──────────────────────────────────────
    try:
        from plugins.cms.src.repositories.cms_image_repository import (
            CmsImageRepository,
        )
        from plugins.cms.src.services.cms_image_service import CmsImageService
        from plugins.cms.src.services.file_storage import LocalFileStorage
    except Exception as exc:
        print(f"  CMS plugin not loadable — skipping image import ({exc})")
    else:
        seed_dir = Path("/app/uploads/images")
        if not seed_dir.is_dir():
            print(f"  No seed-image dir at {seed_dir} — skipping")
        else:
            image_repo = CmsImageRepository(db.session)
            storage = LocalFileStorage(base_path="/app/uploads")
            image_service = CmsImageService(image_repo, storage)

            files = sorted(p for p in seed_dir.iterdir() if p.is_file())
            print(f"  Found {len(files)} seed image(s) at {seed_dir}")

            from plugins.cms.src.services.cms_image_service import _slugify

            registered = skipped = failed = 0
            for path in files:
                slug = _slugify(path.stem)
                if image_repo.find_by_slug(slug):
                    skipped += 1
                    continue
                try:
                    data = path.read_bytes()
                    mime, _ = mimetypes.guess_type(str(path))
                    image_service.upload_image(
                        file_data=data,
                        filename=path.name,
                        mime_type=mime or "application/octet-stream",
                        caption=path.stem,
                    )
                    registered += 1
                except Exception as exc:
                    failed += 1
                    print(f"    ✗ {path.name}: {exc}")
            print(
                f"  Images: {registered} registered, "
                f"{skipped} already present, {failed} failed"
            )

    # ── (b) Default-home routing rules ─────────────────────────────────────
    try:
        from plugins.cms.src.models.cms_page import CmsPage
        from plugins.cms.src.models.cms_routing_rule import CmsRoutingRule
    except Exception as exc:
        print(f"  CMS routing models not loadable — skipping routing ({exc})")
        sys.exit(0)

    # Ensure a `home` page exists. If absent but `home1` exists, clone it
    # so the routing target resolves to a real published page.
    home_page = db.session.query(CmsPage).filter_by(slug="home").first()
    if home_page is None:
        home1 = db.session.query(CmsPage).filter_by(slug="home1").first()
        if home1 is not None:
            home_page = CmsPage()
            for column in CmsPage.__table__.columns:
                if column.name in ("id", "created_at", "updated_at", "version"):
                    continue
                setattr(home_page, column.name, getattr(home1, column.name))
            home_page.slug = "home"
            home_page.title = (home1.title or "Home") + ""
            db.session.add(home_page)
            db.session.commit()
            print("  + page 'home' created (cloned from 'home1')")
        else:
            print(
                "  ! neither 'home' nor 'home1' page found — "
                "routing rules will still upsert but pages must be created later"
            )
    else:
        print("  ~ page 'home' already exists")

    def _upsert_rule(*, name, match_type, match_value, target_slug,
                     redirect_code, is_rewrite, priority):
        existing = (
            db.session.query(CmsRoutingRule)
            .filter_by(match_type=match_type, match_value=match_value,
                       layer="middleware")
            .first()
        )
        if existing is None:
            rule = CmsRoutingRule(
                name=name,
                match_type=match_type,
                match_value=match_value,
                target_slug=target_slug,
                is_active=True,
                priority=priority,
                layer="middleware",
                redirect_code=redirect_code,
                is_rewrite=is_rewrite,
            )
            db.session.add(rule)
            print(
                f"  + routing rule: {match_type}"
                + (f"={match_value}" if match_value else "")
                + f" → {target_slug}"
            )
        else:
            existing.target_slug = target_slug
            existing.is_active = True
            existing.priority = priority
            existing.redirect_code = redirect_code
            existing.is_rewrite = is_rewrite
            print(
                f"  ~ routing rule: {match_type}"
                + (f"={match_value}" if match_value else "")
                + f" → {target_slug} (updated)"
            )

    _upsert_rule(
        name="home", match_type="default", match_value=None,
        target_slug="home", redirect_code=302, is_rewrite=True, priority=0,
    )
    _upsert_rule(
        name="index.html → home", match_type="path_prefix",
        match_value="/index.html", target_slug="home",
        redirect_code=302, is_rewrite=True, priority=-10,
    )
    db.session.commit()
    print("✓ Default-home routing rules upserted")
PYEOF

if [ $? -eq 0 ]; then
    echo "✓ CMS image import + routing-rule step complete"
else
    echo "WARNING: CMS image / routing step exited non-zero — check logs"
fi

# Run backend tests
#echo ""
#echo "=========================================="
#echo "Step 4: Running backend tests"
#echo "=========================================="
#
#cd "$BACKEND_DIR"
#echo "Running all backend tests..."
#if docker compose run --rm test pytest tests/ -v --tb=short; then
#    echo "Backend tests passed!"
#else
#    echo "ERROR: Backend tests failed"
#    exit 1
#fi

# Start frontend containers
echo ""
echo "=========================================="
echo "Step 5: Starting frontend containers (dev + nginx)"
echo "=========================================="
echo ""
echo "Both frontends run two containers each:"
echo "  - dev:   Vite dev server on the container's port 5173."
echo "  - nginx: reverse proxy on the host port ($FE_USER_PORT / $FE_ADMIN_PORT)"
echo "           — this is what users hit in their browser."
echo "'make up' only starts 'dev', so we also start 'nginx' to expose"
echo "the apps on the documented URLs."
echo ""

# Helper — bring up both dev + nginx for an fe-* repo. Uses --build so
# image changes between recipe runs are picked up.
start_frontend() {
    local dir="$1"
    local label="$2"
    (
        cd "$dir" || exit 1
        echo "── $label (cwd: $dir) ──"
        docker compose up dev nginx -d --build
    )
}

start_frontend "$FE_USER_DIR"  "vbwd-fe-user"
start_frontend "$FE_ADMIN_DIR" "vbwd-fe-admin"

# Verify each app responds on its public port — the recipe's summary
# below claims they're up; this proves it before the user sees it.
if wait_for_service "vbwd-fe-user"  "${HTTP}://${DOMAIN}:${FE_USER_PORT}/"  60; then
    echo "✓ User app reachable on ${HTTP}://${DOMAIN}:${FE_USER_PORT}"
else
    echo "WARNING: User app didn't answer on ${HTTP}://${DOMAIN}:${FE_USER_PORT} yet."
    echo "  Check logs with: cd $FE_USER_DIR && docker compose logs -f dev nginx"
fi
if wait_for_service "vbwd-fe-admin" "${HTTP}://${DOMAIN}:${FE_ADMIN_PORT}/" 60; then
    echo "✓ Admin app reachable on ${HTTP}://${DOMAIN}:${FE_ADMIN_PORT}"
else
    echo "WARNING: Admin app didn't answer on ${HTTP}://${DOMAIN}:${FE_ADMIN_PORT} yet."
    echo "  Check logs with: cd $FE_ADMIN_DIR && docker compose logs -f dev nginx"
fi


# Summary
echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Services:"
echo "  - Backend API:          ${HTTP}://${DOMAIN}:5000"
echo "  - Frontend (User app):  ${HTTP}://${DOMAIN}:$FE_USER_PORT"
echo "  - Frontend (Admin app): ${HTTP}://${DOMAIN}:$FE_ADMIN_PORT"
echo "  - Database:             postgresql://vbwd:vbwd@${DOMAIN}:5432/vbwd"
echo ""
echo "Default admin login (LOCAL DEV ONLY — rotate before exposing the stack):"
echo "  - Email:    $ADMIN_EMAIL"
echo "  - Password: $ADMIN_PASSWORD"
echo "  - Admin UI: ${HTTP}://${DOMAIN}:$FE_ADMIN_PORT/admin/login"
echo ""
echo "Seeded demo data (idempotent — re-run this recipe any time):"
echo "  - CMS:           styles, widgets, layouts, pages + image gallery"
echo "  - Booking:       resources, schemas, bookings, CMS pages, email templates"
echo "  - Shop:          products, categories, warehouses, stock, CMS pages"
echo "  - GHRM:          catalogue + detail layouts/widgets/pages"
echo "  - Discount:      demo discounts + coupons"
echo "  - Token payment: demo token bundles + invoice pricing"
echo ""
echo "CMS routing: /  and  /index.html  →  /home  (rewrite)"
echo "  Edit at: ${HTTP}://${DOMAIN}:$FE_ADMIN_PORT/admin/cms/routing"
echo ""
echo "Repository Structure:"
echo "  - Backend:    $BACKEND_DIR"
echo "  - Core Lib:   $FE_CORE_DIR"
echo "  - User App:   $FE_USER_DIR (depends on core via git submodule)"
echo "  - Admin App:  $FE_ADMIN_DIR (depends on core via git submodule)"
echo ""
echo "Frontends are already running (dev + nginx containers started above)."
echo "If you prefer a native dev server with HMR instead of the dockerised dev,"
echo "stop the 'dev' container and run 'npm run dev' from the repo root."
echo ""
echo "Useful commands:"
echo "  - Backend logs:    cd $BACKEND_DIR && docker compose logs -f api"
echo "  - User app logs:   cd $FE_USER_DIR && docker compose logs -f dev nginx"
echo "  - Admin app logs:  cd $FE_ADMIN_DIR && docker compose logs -f dev nginx"
echo "  - Stop user app:   cd $FE_USER_DIR && docker compose down"
echo "  - Stop admin app:  cd $FE_ADMIN_DIR && docker compose down"
echo "  - Stop backend:    cd $BACKEND_DIR && docker compose down"
echo "  - Run tests:       cd $BACKEND_DIR && make test"
echo ""
echo "Documentation: $WORKSPACE_DIR/docs/"
echo ""
