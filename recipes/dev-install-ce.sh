#!/bin/bash
set -e

# VBWD Community Edition - Development Installation Script
# Works for both local development and GitHub Actions
# Usage: ./recipes/dev-install-ce.sh [--domain <hostname>] [--ssl]
# Or set VBWD_DOMAIN / VBWD_SSL env vars before running.
#
# Examples:
#   ./recipes/dev-install-ce.sh                              # http://localhost
#   ./recipes/dev-install-ce.sh --domain myapp.com          # http://myapp.com
#   ./recipes/dev-install-ce.sh --domain myapp.com --ssl    # https://myapp.com
#   VBWD_DOMAIN=myapp.com VBWD_SSL=1 ./recipes/dev-install-ce.sh

# Parse arguments
DOMAIN="${VBWD_DOMAIN:-localhost}"
SSL="${VBWD_SSL:-0}"
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

for plugin in analytics chat cms email ghrm mailchimp paypal stripe taro yookassa; do
    PLUGIN_DIR="$BACKEND_DIR/plugins/$plugin"
    PLUGIN_REPO="https://github.com/VBWD-platform/vbwd-plugin-${plugin}.git"
    if [ -d "$PLUGIN_DIR/.git" ]; then
        echo "Plugin $plugin already installed, pulling..."
        cd "$PLUGIN_DIR" && git pull origin main || true
    else
        echo "Cloning plugin $plugin..."
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
        echo "  WARN  $src not found; $(basename "$dst") not seeded"
    fi
}

seed_manifest "$BACKEND_DIR/plugins/plugins.json"           backend-plugins.json
seed_manifest "$BACKEND_DIR/plugins/config.json"            backend-plugins-config.json
seed_manifest "$FE_ADMIN_DIR/plugins/plugins.json"          fe-admin-plugins.json
seed_manifest "$FE_ADMIN_DIR/plugins/config.json"           fe-admin-plugins-config.json
seed_manifest "$FE_USER_DIR/plugins/plugins.json"           fe-user-plugins.json
seed_manifest "$FE_USER_DIR/plugins/config.json"            fe-user-plugins-config.json

echo "✓ Plugin manifests seeded into $VAR_DIR/plugins/"
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
for plugin in chat checkout cms ghrm landing1 paypal-payment stripe-payment taro theme-switcher yookassa-payment; do
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
for plugin in analytics-widget cms-admin email-admin ghrm-admin taro-admin; do
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

# Note about frontend startup
echo ""
echo "=========================================="
echo "Step 5: Frontend applications (ready to start)"
echo "=========================================="
echo ""
echo "Frontend apps have been installed and are ready to run."
echo "Start them separately from their directories:"
echo ""
echo "User app (port $FE_USER_PORT):"
echo "  cd $FE_USER_DIR && npm run dev"
echo "  or with Docker: docker compose up"

echo ""
echo "Admin app (port $FE_ADMIN_PORT):"
echo "  cd $FE_ADMIN_DIR && npm run dev"
echo "  or with Docker: docker compose up"
echo ""
echo "Core library:"
echo "  Already built at: $FE_CORE_DIR/dist/"
echo ""


cd $FE_USER_DIR
make up

cd ..
cd $FE_ADMIN_DIR
make up
cd ..


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
echo "Repository Structure:"
echo "  - Backend:    $BACKEND_DIR"
echo "  - Core Lib:   $FE_CORE_DIR"
echo "  - User App:   $FE_USER_DIR (depends on core via git submodule)"
echo "  - Admin App:  $FE_ADMIN_DIR (depends on core via git submodule)"
echo ""
echo "Quick Start - Frontend Apps (run in separate terminals):"
echo "  - User app:   cd $FE_USER_DIR && npm run dev"
echo "  - Admin app:  cd $FE_ADMIN_DIR && npm run dev"
echo ""
echo "Useful commands:"
echo "  - Backend logs:    cd $BACKEND_DIR && docker compose logs -f api"
echo "  - User app logs:   cd $FE_USER_DIR && docker compose logs -f"
echo "  - Admin app logs:  cd $FE_ADMIN_DIR && docker compose logs -f"
echo "  - Run tests:       cd $BACKEND_DIR && make test"
echo "  - Stop backend:    cd $BACKEND_DIR && docker compose down"
echo ""
echo "Documentation: $WORKSPACE_DIR/docs/"
echo ""
