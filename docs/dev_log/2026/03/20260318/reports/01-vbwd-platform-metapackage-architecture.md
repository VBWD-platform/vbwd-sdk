# vbwd-platform Metapackage Architecture

**Date:** 2026-03-18
**Type:** Architecture Design & Implementation Plan
**Status:** Draft

---

## Summary

This report defines the architecture for **vbwd-platform** — a metapackage that provides plugin developers and merchants with a clean workspace following the **Composer `vendor/` pattern**. Core platform code (backend, frontend apps, component library) is installed as **packages** into gitignored dependency directories (`node_modules/`, `.venv/`). The developer's workspace contains only custom plugins, configuration, and orchestration — exactly like a Laravel project where you never edit `vendor/laravel/framework`.

---

## 1. The Composer/Vendor Analogy

### How Laravel/Composer works
```
my-laravel-project/
├── composer.json          # "laravel/framework": "^11.0"
├── composer.lock           # Locked versions
├── vendor/                 # READ-ONLY, gitignored — all packages here
│   └── laravel/framework/  # Core framework (you never edit this)
├── app/                    # YOUR code
├── routes/                 # YOUR routes
├── config/                 # YOUR config
├── database/migrations/    # YOUR migrations
└── .env                    # YOUR secrets
```

### How vbwd-platform should work
```
vbwd-platform/
├── .env                          # YOUR secrets (DB, Redis, JWT, Stripe keys)
├── docker-compose.yaml           # Infrastructure (postgres, redis)
├── Makefile                      # Developer commands
│
├── be/
│   ├── requirements.txt          # "vbwd-backend==1.2.0" + plugin deps
│   ├── .venv/                    # READ-ONLY, gitignored — pip packages here
│   │   └── lib/python3.11/
│   │       └── site-packages/
│   │           └── vbwd/ # Core backend (you never edit this)
│   ├── plugins/                  # YOUR plugins only
│   │   ├── plugins.json          # Plugin registry
│   │   ├── config.json           # Plugin configuration
│   │   └── loyalty-points/       # Your custom plugin
│   │       ├── __init__.py
│   │       ├── src/
│   │       └── tests/
│   ├── migrations/               # YOUR Alembic migrations (plugin tables)
│   ├── app.py                    # Thin entry point: from vbwd import create_app
│   └── gunicorn.conf.py          # YOUR server config
│
├── fe-user/
│   ├── package.json              # "vbwd-fe-user": "^1.2.0" + plugin deps
│   ├── node_modules/             # READ-ONLY, gitignored — npm packages here
│   │   ├── vbwd-fe-user/         # Core user app (you never edit this)
│   │   └── vbwd-view-component/  # Core component library
│   ├── plugins/                  # YOUR plugins only
│   │   ├── plugins.json
│   │   └── my-widget/
│   │       ├── index.ts
│   │       └── src/
│   ├── vite.config.ts            # Extends core config, adds plugin resolution
│   └── index.html                # Optional: override core template
│
├── fe-admin/
│   ├── package.json              # "vbwd-fe-admin": "^1.2.0" + plugin deps
│   ├── node_modules/             # READ-ONLY, gitignored
│   │   ├── vbwd-fe-admin/        # Core admin app (you never edit this)
│   │   └── vbwd-view-component/
│   ├── plugins/                  # YOUR plugins only
│   │   ├── plugins.json
│   │   └── my-admin-panel/
│   └── vite.config.ts
│
└── uploads/                      # Persistent file storage
```

**Key principle:** Core code lives in dependency directories (`.venv/`, `node_modules/`) — gitignored, read-only, installed via package manager. The developer only commits their plugins, config, and `.env`.

---

## 2. Current State vs Target State

### Current State (SDK development mode)

| Component | How it's consumed | Location |
|-----------|------------------|----------|
| Backend core | Direct source in `vbwd-backend/src/` | Local git repo — full access |
| Backend plugins | Source in `vbwd-backend/plugins/` | Git repos inside `plugins/` |
| fe-core | `file:./vbwd-fe-core` in package.json | Git submodule — full access |
| fe-user core | Direct source in `vbwd-fe-user/vue/src/` | Local git repo — full access |
| fe-user plugins | Source in `vbwd-fe-user/plugins/` | Git repos inside `plugins/` |
| fe-admin core | Direct source in `vbwd-fe-admin/vue/src/` | Local git repo — full access |
| fe-admin plugins | Source in `vbwd-fe-admin/plugins/` | Git repos inside `plugins/` |

**Problems:**
- Plugin developers have direct access to ALL core source code
- No separation between "platform code" and "your code"
- Developers can accidentally (or intentionally) modify core
- Must clone 4+ repos just to write one plugin
- No versioned releases — always tracking `main` branch

### Target State (Composer/vendor pattern)

| Component | How it's consumed | Where it lives |
|-----------|------------------|----------------|
| Backend core | `pip install vbwd-backend` | `.venv/` (gitignored) |
| fe-core | `npm install vbwd-view-component` | `node_modules/` (gitignored) |
| fe-user core | `npm install vbwd-fe-user` | `node_modules/` (gitignored) |
| fe-admin core | `npm install vbwd-fe-admin` | `node_modules/` (gitignored) |
| Custom plugins | Developer's source code | `plugins/` (committed to git) |

The developer **can read** core source (browse `node_modules/` or `.venv/`) for reference, but **cannot commit changes** to it — exactly like Composer.

---

## 3. Package Design

### 3.1 Backend Package (`vbwd-backend`)

**What becomes the pip package:**
- `src/` — All core code (models, services, repositories, routes, middleware, events, plugin framework)
- `alembic/versions/` — Core database migrations
- `templates/` — Email and system templates
- `create_app()` factory function as entry point

**What stays in the platform workspace:**
- `plugins/` — Custom plugins only
- `plugins.json` / `config.json` — Plugin registry
- `.env` — Environment config
- `app.py` — Thin entry point
- `migrations/` — Custom plugin migrations

**pyproject.toml for vbwd-backend:**
```toml
[project]
name = "vbwd-backend"
version = "1.2.0"
description = "VBWD SaaS Platform - Backend Core"
requires-python = ">=3.11"
dependencies = [
    "flask>=3.0",
    "sqlalchemy>=2.0",
    "alembic>=1.13",
    "flask-jwt-extended>=4.6",
    "dependency-injector>=4.41",
    "gunicorn>=21.0",
    "redis>=5.0",
    "psycopg2-binary>=2.9",
    "celery>=5.3",
]

[project.optional-dependencies]
dev = ["pytest", "black", "flake8", "mypy"]

[build-system]
requires = ["setuptools>=68.0"]
build-backend = "setuptools.build_meta"
```

**Platform entry point (`be/app.py`):**
```python
from vbwd import create_app
app = create_app()
```

**Platform requirements.txt:**
```
vbwd-backend==1.2.0

# Custom plugin dependencies:
anthropic>=0.20.0    # for my AI plugin
stripe>=5.0.0        # if using stripe
```

### 3.2 Frontend Core Package (`vbwd-view-component`)

**Already exists as a package** — `vbwd-fe-core` already builds to `dist/` and exports as `vbwd-view-component`. Currently consumed via `file:./vbwd-fe-core`, needs to be published to npm registry instead.

No structural changes needed. Just publish it:
```bash
cd vbwd-fe-core
npm publish  # → vbwd-view-component@1.2.0 on npm
```

### 3.3 Frontend App Packages (`vbwd-fe-user`, `vbwd-fe-admin`)

This is the hardest part. Vue apps are not naturally libraries — they have `index.html`, `main.ts`, router config, etc. Two approaches:

**Approach A — App-as-library (recommended):**

Restructure `vbwd-fe-user` to export a `createApp()` factory that accepts plugin config:

```typescript
// Published as npm package: vbwd-fe-user
export function createVbwdUserApp(options: {
  plugins: IPlugin[];
  config: AppConfig;
}): App {
  const app = createApp(AppRoot);
  // Setup router, stores, i18n from core
  // Register provided plugins
  return app;
}
```

**Platform entry point (`fe-user/main.ts`):**
```typescript
import { createVbwdUserApp } from 'vbwd-fe-user';
import { loadPlugins } from './plugins/loader';

const plugins = await loadPlugins();
const app = createVbwdUserApp({ plugins, config: { apiUrl: import.meta.env.VITE_API_URL } });
app.mount('#app');
```

**Platform `fe-user/vite.config.ts`:**
```typescript
import { defineConfig } from 'vite';
import { vbwdUserConfig } from 'vbwd-fe-user/vite-config';

export default defineConfig({
  ...vbwdUserConfig,
  // Override or extend as needed
  server: { port: 8080 }
});
```

**Platform `fe-user/package.json`:**
```json
{
  "name": "@my-platform/fe-user",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "vbwd-fe-user": "^1.2.0",
    "vbwd-view-component": "^1.2.0",
    "vue": "^3.4.0",
    "vue-router": "^4.0.0",
    "pinia": "^2.0.0"
  }
}
```

**Approach B — Docker image with build-on-start:**

Pre-built Docker image with core baked in, plugins mounted at runtime, rebuild triggered on start.

```yaml
services:
  fe-user:
    image: ghcr.io/vbwd/vbwd-fe-user:1.2.0
    volumes:
      - ./fe-user/plugins:/app/plugins
    command: ["sh", "-c", "npm run build && nginx -g 'daemon off;'"]
```

**Comparison:**

| Criteria | Approach A (app-as-library) | Approach B (Docker image) |
|----------|---------------------------|--------------------------|
| IDE support | Full autocomplete, type checking | None (code inside Docker) |
| Hot reload | Native Vite HMR | Requires container restart |
| Familiar to | npm/frontend devs | DevOps/Docker users |
| Plugin DX | `npm run dev` → instant | `docker compose up` → rebuild |
| Core visibility | Can browse `node_modules/` | Can browse via `docker exec` |
| Deployment | `npm run build` → static files | Docker image push |

**Recommendation:** Use **Approach A** for development, **Approach B** for production deployment. They are complementary:
- Developers use `npm install` + `npm run dev` locally (Approach A)
- CI/CD builds a Docker image with plugins baked in (Approach B) for production

---

## 4. Recommended Architecture

### The Two-Mode Pattern

**Development mode** (Composer/vendor pattern):
```bash
cd vbwd-platform/be
pip install -r requirements.txt   # Core lands in .venv/
cd ../fe-user
npm install                        # Core lands in node_modules/
npm run dev                        # Vite HMR with custom plugins
```

**Production mode** (Docker images):
```bash
cd vbwd-platform
make build    # Builds Docker images with plugins baked in
make deploy   # Pushes to registry, deploys to server
```

### Full Platform Structure

```
vbwd-platform/
├── .env.example                  # Template for environment config
├── .env                          # Actual config (gitignored)
├── .gitignore                    # node_modules/, .venv/, uploads/, .env
├── docker-compose.yaml           # Infrastructure: postgres, redis, mailpit
├── docker-compose.prod.yaml      # Production: api + fe-user + fe-admin
├── Makefile                      # Developer commands
├── README.md                     # Getting started guide
│
├── be/
│   ├── requirements.txt          # vbwd-backend==1.2.0
│   ├── .venv/                    # gitignored — core backend package
│   ├── app.py                    # Entry: from vbwd import create_app
│   ├── gunicorn.conf.py          # Server configuration
│   ├── Dockerfile                # Production image (bakes in plugins)
│   ├── plugins/
│   │   ├── plugins.json          # Plugin registry
│   │   ├── config.json           # Plugin settings
│   │   ├── requirements.txt      # Plugin-specific pip deps
│   │   └── loyalty-points/       # YOUR plugin
│   │       ├── __init__.py       # LoyaltyPlugin(BasePlugin)
│   │       ├── src/
│   │       │   ├── models/
│   │       │   ├── repositories/
│   │       │   ├── services/
│   │       │   └── routes.py
│   │       └── tests/
│   └── migrations/               # Custom Alembic migrations
│
├── fe-user/
│   ├── package.json              # vbwd-fe-user + vbwd-view-component
│   ├── node_modules/             # gitignored — core app + components
│   ├── main.ts                   # Entry: import { createVbwdUserApp }
│   ├── index.html                # HTML template
│   ├── vite.config.ts            # Extends core Vite config
│   ├── Dockerfile                # Production image
│   ├── plugins/
│   │   ├── plugins.json
│   │   └── my-widget/
│   │       ├── index.ts          # export const myPlugin: IPlugin
│   │       └── src/
│   └── public/                   # Static assets
│
├── fe-admin/
│   ├── package.json              # vbwd-fe-admin + vbwd-view-component
│   ├── node_modules/             # gitignored
│   ├── main.ts
│   ├── index.html
│   ├── vite.config.ts
│   ├── Dockerfile
│   ├── plugins/
│   │   ├── plugins.json
│   │   └── my-admin-panel/
│   └── public/
│
└── uploads/                      # File storage (gitignored, bind-mounted)
```

### docker-compose.yaml (Infrastructure only — dev mode)
```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${DB_USER:-vbwd}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-vbwd}
      POSTGRES_DB: ${DB_NAME:-vbwd}
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "${DB_PORT:-5432}:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "${REDIS_PORT:-6379}:6379"

  mailpit:
    image: axllent/mailpit
    ports:
      - "8025:8025"
      - "1025:1025"

volumes:
  pgdata:
```

### Makefile (full command parity with SDK root Makefile)

The platform Makefile mirrors all commands from the SDK root Makefile (`vbwd-sdk-2/Makefile`), so plugin developers have the exact same workflow as SDK developers.

```makefile
.PHONY: install npm-install up down ps dev-be dev-fe-user dev-fe-admin \
        rebuild-backend rebuild-admin rebuild-user rebuild-core code-rebuild total-rebuild \
        migrations reset-db install-demo-data be-logs \
        unit integration styles test test-quick test-be test-fe-user test-fe-admin \
        pre-commit pre-commit-quick create-plugin install-plugin upgrade build deploy

# === Installation ===
install:
	cd be && python -m venv .venv && .venv/bin/pip install -r requirements.txt
	cd be && .venv/bin/pip install -r plugins/requirements.txt 2>/dev/null || true
	cd fe-user && npm install
	cd fe-admin && npm install

npm-install:
	cd fe-user && npm install
	cd fe-admin && npm install

# === Service Management ===
up:
	docker compose up -d   # postgres, redis, mailpit

down:
	docker compose down

ps:
	@echo "=== Infrastructure ===" && docker compose ps
	@echo "=== Backend ===" && cd be && .venv/bin/flask --app app:create_app routes 2>/dev/null && echo "Running" || echo "Stopped"

# === Development (run in separate terminals) ===
dev-be:
	cd be && .venv/bin/flask --app app:create_app run --port 5000 --reload

dev-fe-user:
	cd fe-user && npm run dev   # port 8080

dev-fe-admin:
	cd fe-admin && npm run dev  # port 8081

# === Rebuild ===
rebuild-backend:
	cd be && .venv/bin/pip install --upgrade -r requirements.txt
	cd be && .venv/bin/pip install -r plugins/requirements.txt 2>/dev/null || true
	@echo "Backend rebuilt — restart dev-be"

rebuild-admin:
	cd fe-admin && npm install && npm run build
	@echo "Admin frontend rebuilt at http://localhost:8081"

rebuild-user:
	cd fe-user && npm install && npm run build
	@echo "User frontend rebuilt at http://localhost:8080"

rebuild-core:
	cd be && .venv/bin/pip install --upgrade vbwd-backend
	cd fe-user && npm update vbwd-fe-user vbwd-view-component
	cd fe-admin && npm update vbwd-fe-admin vbwd-view-component
	@echo "Core packages upgraded"

code-rebuild:
	$(MAKE) down
	$(MAKE) rebuild-core
	$(MAKE) rebuild-admin
	$(MAKE) rebuild-user
	$(MAKE) rebuild-backend
	@echo "Code rebuild complete"

total-rebuild:
	$(MAKE) down
	$(MAKE) install
	$(MAKE) up
	@echo "Waiting for postgres..."
	@sleep 3
	$(MAKE) migrations
	$(MAKE) reset-db
	$(MAKE) install-demo-data FORCE=1
	@echo "Total rebuild complete"

# === Database ===
migrations:
	cd be && .venv/bin/alembic upgrade heads

reset-db:
	cd be && .venv/bin/flask --app app:create_app reset-database --force

# Install demo data: core + all plugin populate_db.py
# Usage: make install-demo-data                  → skip if data exists
#        make install-demo-data FORCE=1           → overwrite all
#        make install-demo-data PLUGIN=cms        → specific plugin only
#        make install-demo-data PLUGIN=cms FORCE=1
install-demo-data:
	@cd be && .venv/bin/flask --app app:create_app seed-core-data $(if $(FORCE),--force,) 2>/dev/null || true
ifdef PLUGIN
	@echo "Installing demo data for plugin: $(PLUGIN)"
	cd be && .venv/bin/python plugins/$(PLUGIN)/populate_db.py $(if $(FORCE),--force,)
else
	@for populator in be/plugins/*/populate_db.py; do \
		plugin_name=$$(basename $$(dirname $$populator)); \
		echo "  Populating $$plugin_name..."; \
		cd be && .venv/bin/python $$populator $(if $(FORCE),--force,) || true; \
		cd ..; \
	done
endif

# === Logs ===
be-logs:
	@echo "Backend logs (run dev-be in a terminal to see live output)"

# === Testing (uses same scripts as CI) ===
unit:
	@echo "=== Backend unit tests ==="
	cd be && ./bin/pre-commit-check.sh --unit
	@echo "=== fe-user unit tests ==="
	cd fe-user && ./bin/pre-commit-check.sh --unit
	@echo "=== fe-admin unit tests ==="
	cd fe-admin && ./bin/pre-commit-check.sh --unit
	@echo "All unit tests passed"

integration:
	@echo "=== Backend integration tests ==="
	cd be && ./bin/pre-commit-check.sh --integration
	@echo "All integration tests passed"

styles:
	@echo "=== Backend lint ==="
	cd be && ./bin/pre-commit-check.sh --lint
	@echo "=== fe-user style ==="
	cd fe-user && ./bin/pre-commit-check.sh --style
	@echo "=== fe-admin style ==="
	cd fe-admin && ./bin/pre-commit-check.sh --style
	@echo "All style checks passed"

test:
	cd be && ./bin/pre-commit-check.sh --full
	cd fe-user && ./bin/pre-commit-check.sh --full
	cd fe-admin && ./bin/pre-commit-check.sh --full

test-quick:
	cd be && ./bin/pre-commit-check.sh --quick
	cd fe-user && ./bin/pre-commit-check.sh --quick
	cd fe-admin && ./bin/pre-commit-check.sh --quick

test-be:
	cd be && ./bin/pre-commit-check.sh --full

test-fe-user:
	cd fe-user && ./bin/pre-commit-check.sh --full

test-fe-admin:
	cd fe-admin && ./bin/pre-commit-check.sh --full

pre-commit: test
pre-commit-quick: test-quick

# === Plugin Management ===
create-plugin:
	@echo "Usage: make create-plugin NAME=my-plugin TYPE=be|fe-user|fe-admin"

install-plugin:
	@echo "Usage: make install-plugin NAME=cms"

# === Upgrade Core ===
upgrade: rebuild-core

# === Production ===
build:
	docker compose -f docker-compose.prod.yaml build

deploy:
	docker compose -f docker-compose.prod.yaml push
```

---

## 5. Critical Technical Challenges

### 5.1 Backend: Publishing as pip package

**Challenge:** `vbwd-backend` currently has no `pyproject.toml` or `setup.py`. It runs directly from source inside Docker.

**Solution:**
1. Add `pyproject.toml` to `vbwd-backend/`
2. Ensure all imports work when installed as a package (`from vbwd.models import User`)
3. Include core Alembic migrations in the package data
4. Publish to private PyPI (GitHub Packages or self-hosted)

**Current import style:** `from src.models import User`
**Package import style:** `from vbwd.models import User`

This requires renaming `src/` to `vbwd/` **or** configuring package discovery to map `src` → `vbwd`. The rename is cleaner.

**Migration path:**
```
vbwd-backend/
├── src/           →  vbwd/     # Rename for pip packaging
│   ├── app.py                          # create_app() factory
│   ├── models/
│   ├── services/
│   ├── routes/
│   └── plugins/                        # Plugin framework (manager, base, etc.)
├── plugins/                            # Official plugins (separate repos, not in package)
├── pyproject.toml                      # NEW: package metadata
└── tests/
```

**Important:** Only the plugin **framework** (`src/plugins/manager.py`, `src/plugins/base.py`) ships with the package. Actual plugin implementations (cms, stripe, etc.) are separate — installed by the developer.

### 5.2 Frontend: App-as-Library Pattern

**Challenge:** Vue apps use Vite's `import.meta.glob()` to discover plugins at build time. If the app is in `node_modules/`, it can't glob the developer's `plugins/` directory.

**Solution:** The platform workspace has its own `main.ts` and `vite.config.ts` that:
1. Import the core app factory from `node_modules/vbwd-fe-user`
2. Glob plugins from the local `plugins/` directory
3. Pass discovered plugins to the factory

```typescript
// vbwd-platform/fe-user/main.ts
import { createVbwdUserApp } from 'vbwd-fe-user';

// Glob plugins from workspace (build-time resolution)
const pluginModules = import.meta.glob('./plugins/*/index.ts', { eager: false });

async function bootstrap() {
  const plugins = [];
  for (const [path, loader] of Object.entries(pluginModules)) {
    const mod = await loader();
    // Same fallback logic: default export or first named export with .install
    const plugin = mod.default ?? Object.values(mod).find(v => v?.install);
    if (plugin) plugins.push(plugin);
  }

  const app = createVbwdUserApp({
    plugins,
    apiUrl: import.meta.env.VITE_API_URL,
  });
  app.mount('#app');
}

bootstrap();
```

**What needs to change in `vbwd-fe-user`:**
1. Extract core app setup into a `createVbwdUserApp()` factory function
2. Export it as the package's main entry point
3. Export Vite config presets for the platform to extend
4. Export types (IPlugin, IPlatformSDK, etc.) — already done via `vbwd-view-component`

### 5.3 Alembic: Core + Custom Migrations

**Challenge:** Core migrations ship with the pip package. Custom migrations live in `be/migrations/`.

**Solution:** Alembic's `version_locations` supports multiple directories:
```ini
# alembic.ini
[alembic]
version_locations =
    %(here)s/.venv/lib/python3.11/site-packages/vbwd/alembic/versions
    %(here)s/migrations
    %(here)s/plugins/*/migrations
```

Or more elegantly, the `create_app()` factory configures this automatically:
```python
def create_app(plugins_dir="plugins", custom_migrations_dir="migrations"):
    # Auto-configure Alembic version_locations
    # to include core + custom + per-plugin migration directories
```

### 5.4 Plugin Registry Merging

**Challenge:** The core Docker image / package may ship with default official plugins (cms, email, etc.), but the developer's `plugins.json` should control what's enabled.

**Solution:** Layered configuration:
```json
// be/plugins/plugins.json
{
  "_comment": "Only custom and overridden plugins listed here",
  "plugins": {
    "cms": { "enabled": true },
    "stripe": { "enabled": true },
    "loyalty-points": { "enabled": true, "custom": true }
  }
}
```

The PluginManager merges: core defaults + platform overrides + custom plugins.

### 5.5 Official Plugins as Installable Packages

**Challenge:** Official plugins (cms, ghrm, stripe, taro) are currently source code in `plugins/` directories. In the platform model, they should be installable.

**Two distribution models:**

**A. pip/npm packages (like WordPress plugins via composer):**
```
# be/requirements.txt
vbwd-backend==1.2.0
vbwd-plugin-cms==1.0.0
vbwd-plugin-stripe==1.0.0
```

Plugin packages install into `.venv/` alongside core. PluginManager discovers them via entry points:
```toml
# vbwd-plugin-cms/pyproject.toml
[project.entry-points."vbwd.plugins"]
cms = "vbwd_plugin_cms:CmsPlugin"
```

**B. Git clone into plugins/ (like current approach, but explicit):**
```bash
make install-plugin NAME=cms
# → git clone https://github.com/vbwd/vbwd-plugin-cms.git be/plugins/cms
```

**Recommendation:** Start with **Option B** (git clone) — it's simpler and matches the current architecture. Migrate to **Option A** (pip packages with entry points) when the plugin ecosystem matures.

---

## 6. Implementation Plan

### Phase 1: Backend as pip package (2-3 days)

1. Add `pyproject.toml` to `vbwd-backend/`
2. Rename `src/` → `vbwd/` (or configure package mapping)
3. Update all internal imports: `from src.` → `from vbwd.`
4. Ensure `create_app()` accepts external `plugins_dir` parameter
5. Include core Alembic migrations as package data
6. Test: `pip install -e .` then run from external `app.py`
7. Publish to GitHub Packages (private PyPI)

**Key files:**
- `vbwd-backend/pyproject.toml` — NEW
- `vbwd-backend/vbwd/` — Renamed from `src/`
- `vbwd-backend/vbwd/app.py` — Accept `plugins_dir` kwarg
- `vbwd-backend/vbwd/plugins/manager.py` — Accept external plugins path

### Phase 2: Frontend app-as-library (3-4 days)

1. In `vbwd-fe-user`: extract `createVbwdUserApp()` factory from `main.ts`
2. Export factory + Vite config presets from package
3. Publish `vbwd-fe-user` to npm (alongside existing `vbwd-view-component`)
4. Repeat for `vbwd-fe-admin`
5. Test: create platform workspace, `npm install`, `npm run dev` with local plugins

**Key files:**
- `vbwd-fe-user/vue/src/factory.ts` — NEW: `createVbwdUserApp()` export
- `vbwd-fe-user/package.json` — Add exports, publishConfig
- `vbwd-fe-user/vite-config.ts` — NEW: exportable Vite config preset
- Same for `vbwd-fe-admin/`

### Phase 3: Platform template (1-2 days)

1. Create `vbwd-platform/` structure with all scaffolding files
2. Write `.env.example`, `docker-compose.yaml`, `Makefile`
3. Create minimal `be/app.py`, `fe-user/main.ts`, `fe-admin/main.ts`
4. Create `vite.config.ts` files that extend core presets
5. Add example custom plugin (one per tier)
6. Write `README.md` with getting-started guide

### Phase 4: Plugin CLI & templates (1 day)

1. `make create-plugin NAME=x TYPE=be|fe-user|fe-admin`
2. Scaffold boilerplate with correct structure, metadata, tests
3. `make install-plugin NAME=cms` — clone official plugin repos

### Phase 5: Publish & CI/CD (1-2 days)

1. GitHub Actions workflow in `vbwd-backend/` to publish pip package on tag
2. GitHub Actions workflow in `vbwd-fe-user/` and `vbwd-fe-admin/` to publish npm
3. GitHub Actions workflow in `vbwd-fe-core/` to publish `vbwd-view-component`
4. Version synchronization across all packages

---

## 7. Developer Workflow Comparison

### Current: SDK Developer
```bash
git clone --recurse-submodules vbwd-sdk-2
cd vbwd-sdk-2
./recipes/dev-install-ce.sh     # Clones 4+ repos, builds fe-core
make up                          # Starts everything
# Full access to ALL source code — core + plugins
```

### Target: Plugin Developer / Merchant
```bash
# 1. Scaffold
npx create-vbwd-platform my-saas  # or: git clone vbwd-platform-template
cd my-saas

# 2. Install
make install
# → pip install vbwd-backend (into .venv/)
# → npm install vbwd-fe-user (into node_modules/)
# → npm install vbwd-fe-admin (into node_modules/)

# 3. Configure
cp .env.example .env
vim .env

# 4. Start infrastructure
make up   # postgres, redis

# 5. Run (3 terminals)
make dev-be         # Backend on :5000
make dev-fe-user    # User app on :8080
make dev-fe-admin   # Admin app on :8081

# 6. Create a plugin
make create-plugin NAME=loyalty TYPE=be
# → Scaffolds be/plugins/loyalty/ with boilerplate

# 7. Install an official plugin
make install-plugin NAME=cms
# → git clone vbwd-plugin-cms into be/plugins/cms/

# 8. Test
make test  # Tests custom plugins only

# 9. Deploy
make build && make deploy
```

### Target: SDK Core Developer
```bash
# Same as today — full source access in vbwd-sdk-2/
# Plus:
make release VERSION=1.3.0
# → Publishes pip package (vbwd-backend)
# → Publishes npm packages (vbwd-fe-user, vbwd-fe-admin, vbwd-view-component)
# → Tags all repos
```

---

## 8. Alternative Approaches Considered

### A. Docker Images Only (no pip/npm packages)

Core is pre-built into Docker images. Plugins are volume-mounted.

**Pros:** No package publishing infrastructure needed.
**Cons:** No IDE autocomplete for core types, no Vite HMR, rebuild required on plugin changes, foreign pattern for web developers.

**Verdict:** Good for production deployment, poor for development. Use as **production complement**, not primary approach.

### B. Git Submodules (current approach extended)

Keep everything as git repos, submodule more aggressively.

**Pros:** Simple, no packaging step.
**Cons:** Submodule management is painful, no versioning, developers CAN modify core, complex clone process.

**Verdict:** Not scalable for external developers. Doesn't solve the "hide core" requirement.

### C. Monorepo with Workspaces

npm workspaces or turborepo for everything.

**Pros:** Single repo, coordinated builds.
**Cons:** External developers still get full source. Defeats the Composer pattern.

**Verdict:** Good for SDK developers internally, wrong for platform consumers.

### D. Composer/vendor pattern via pip + npm (recommended)

Core is packages in gitignored dependency dirs. Developer workspace is minimal.

**Pros:** Standard tooling (pip, npm), familiar to PHP/Laravel devs, IDE support, hot reload, clean separation, versioned releases.
**Cons:** Need to restructure core for library export (especially frontend apps), need package registry.

**Verdict:** Best match for the stated goal. Natural extension of how npm/pip already work.

---

## 9. Migration Path

The platform approach is **additive** — it doesn't break the current SDK workflow:

| Concern | SDK developer (core) | Platform user (plugins) |
|---------|---------------------|------------------------|
| Works in | `vbwd-sdk-2/` (full source) | `vbwd-platform/` (packages) |
| Core access | Direct source files | `node_modules/` / `.venv/` |
| Can modify core | Yes | No (gitignored) |
| Plugin development | Same `plugins/` pattern | Same `plugins/` pattern |
| Deployment | Docker + Makefile | Docker + Makefile |

**Step-by-step migration:**
1. Add `pyproject.toml` to backend (no existing code changes)
2. Add `createApp()` factory export to frontend apps (no existing code changes)
3. Publish packages to registries
4. Create `vbwd-platform/` template
5. Both workflows coexist indefinitely

---

## 10. Open Questions

1. **Package registry:** GitHub Packages (private PyPI + npm) or self-hosted (Verdaccio + devpi)?
2. **Backend rename:** `src/` → `vbwd/` is a large refactor touching every import. Worth it, or use setuptools `package_dir` mapping?
3. **Frontend factory API:** What should `createVbwdUserApp()` accept? Plugins only, or also theme, locale, custom routes?
4. **Official plugins:** Git clone into `plugins/` or pip/npm packages?
5. **Version locking:** Should all components share one version (`vbwd@1.2.0`) or version independently?
6. **Plugin marketplace:** How do developers discover and install community plugins?
7. **License:** CE core is public domain. What about official plugins? Community plugin licensing?

---

## 11. Testing Strategy: pre-commit-check.sh in the Platform

Each platform directory (`be/`, `fe-user/`, `fe-admin/`) ships with `bin/pre-commit-check.sh` — the same pattern used in the SDK repos today. These scripts run **both core tests and plugin tests**, ensuring the developer's custom code doesn't break anything.

### Platform pre-commit-check.sh structure

```
vbwd-platform/
├── be/bin/pre-commit-check.sh          # Backend: black + flake8 + mypy + pytest (core + plugins)
├── fe-user/bin/pre-commit-check.sh     # FE User: ESLint + vue-tsc + vitest (core + plugins)
├── fe-admin/bin/pre-commit-check.sh    # FE Admin: ESLint + vue-tsc + vitest (core + plugins)
└── Makefile                            # make test → runs all three
```

### How it works

**Backend (`be/bin/pre-commit-check.sh`):**
```bash
# --lint:        black + flake8 + mypy on plugins/ (custom code)
# --unit:        pytest core tests (from installed package) + pytest plugins/*/tests/unit/
# --integration: pytest core integration + plugins/*/tests/integration/
# --core:        core tests only (from installed vbwd-backend package)
# --quick:       lint + unit (skip integration)
# --full:        lint + unit + integration (everything)
```

Core tests run via `pytest --pyargs vbwd.tests` — directly from the installed pip package in `.venv/`. Plugin tests run from the local `plugins/` directory. Both are combined in a single report.

**Frontend (`fe-user/bin/pre-commit-check.sh`, `fe-admin/bin/pre-commit-check.sh`):**
```bash
# --style:       ESLint + vue-tsc on plugins/ (custom code)
# --unit:        vitest core tests (from node_modules/) + vitest plugins/
# --integration: vitest plugins/*/tests/integration/
# --core:        core tests only
# --quick:       style + unit (skip integration)
# --full:        style + unit + integration (everything)
```

### Makefile integration

```makefile
test:          be/bin/pre-commit-check.sh --full && fe-user/bin/pre-commit-check.sh --full && fe-admin/bin/pre-commit-check.sh --full
test-quick:    be/bin/pre-commit-check.sh --quick && fe-user/bin/pre-commit-check.sh --quick && fe-admin/bin/pre-commit-check.sh --quick
test-be:       be/bin/pre-commit-check.sh --full
test-fe-user:  fe-user/bin/pre-commit-check.sh --full
test-fe-admin: fe-admin/bin/pre-commit-check.sh --full
pre-commit:    make test
```

### GitHub Actions CI for vbwd-platform

```yaml
# .github/workflows/ci.yml
jobs:
  install:           # pip install + npm install
  be-lint:           # be/bin/pre-commit-check.sh --lint
  be-unit:           # be/bin/pre-commit-check.sh --unit (core + plugins)
  be-integration:    # be/bin/pre-commit-check.sh --integration
  fe-user-lint:      # fe-user/bin/pre-commit-check.sh --style
  fe-user-unit:      # fe-user/bin/pre-commit-check.sh --unit (core + plugins)
  fe-admin-lint:     # fe-admin/bin/pre-commit-check.sh --style
  fe-admin-unit:     # fe-admin/bin/pre-commit-check.sh --unit (core + plugins)
  test-summary:      # Aggregate — fails if any job failed
```

All jobs use the same `bin/pre-commit-check.sh` scripts that developers run locally. **What passes locally, passes in CI. No surprises.**

---

## 12. Acceptance Criteria

### CRITICAL: Both installation modes MUST work simultaneously

The `feature/platform` branches must keep both SDK and metapackage installations green at all times.

**SDK developer installation (existing — must NOT regress):**
```bash
cd vbwd-sdk-2 && ./recipes/dev-install-ce.sh && make up
vbwd-backend/bin/pre-commit-check.sh --full    # GREEN (292+ tests + all plugins)
vbwd-fe-user/bin/pre-commit-check.sh --full     # GREEN
vbwd-fe-admin/bin/pre-commit-check.sh --full    # GREEN
# GitHub Actions CI on vbwd-sdk-2               → GREEN
```

**Metapackage installation (new):**
```bash
cd vbwd-platform && make install && make up && make test
be/bin/pre-commit-check.sh --full               # GREEN (core + plugins)
fe-user/bin/pre-commit-check.sh --full          # GREEN
fe-admin/bin/pre-commit-check.sh --full         # GREEN
# GitHub Actions CI on vbwd-platform            → GREEN
```

During development, the metapackage installs from `feature/platform` branches:
```
# be/requirements.txt
vbwd-backend @ git+https://github.com/dantweb/vbwd-backend.git@feature/platform

# fe-user/package.json
"vbwd-fe-user": "github:dantweb/vbwd-fe-user#feature/platform"
```

### GitHub Actions — ALL green (both repos):

| Job | Script | Must pass |
|-----|--------|-----------|
| install | `make install` | YES |
| be-lint | `be/bin/pre-commit-check.sh --lint` | YES |
| be-unit | `be/bin/pre-commit-check.sh --unit` | YES |
| be-integration | `be/bin/pre-commit-check.sh --integration` | YES |
| fe-user-lint | `fe-user/bin/pre-commit-check.sh --style` | YES |
| fe-user-unit | `fe-user/bin/pre-commit-check.sh --unit` | YES |
| fe-admin-lint | `fe-admin/bin/pre-commit-check.sh --style` | YES |
| fe-admin-unit | `fe-admin/bin/pre-commit-check.sh --unit` | YES |
| test-summary | All above | YES |

### Local — ALL green:

```bash
cd be && ./bin/pre-commit-check.sh --full        # lint + core tests + plugin tests
cd fe-user && ./bin/pre-commit-check.sh --full   # style + core tests + plugin tests
cd fe-admin && ./bin/pre-commit-check.sh --full  # style + core tests + plugin tests
make test                                         # Runs all three
```

### Makefile — Full command parity with SDK:

All commands from the SDK root Makefile (`vbwd-sdk-2/Makefile`) must exist in the platform Makefile:

| Command | SDK | Platform | Must work |
|---------|-----|----------|-----------|
| `make up` | docker compose up (all repos) | docker compose up (infra) + dev servers | YES |
| `make down` | docker compose down (all repos) | docker compose down + stop dev servers | YES |
| `make rebuild-backend` | docker compose build --no-cache | pip install --upgrade + restart | YES |
| `make rebuild-admin` | npm install + build + docker compose | npm install + build | YES |
| `make rebuild-user` | npm install + build + docker compose | npm install + build | YES |
| `make rebuild-core` | cd vbwd-fe-core && npm install && build | pip upgrade + npm update core packages | YES |
| `make code-rebuild` | down + rebuild all | down + rebuild all | YES |
| `make total-rebuild` | down + rebuild + reset-db + populate | down + install + up + migrate + reset-db | YES |
| `make migrations` | docker compose exec api alembic upgrade | .venv/bin/alembic upgrade heads | YES |
| `make reset-db` | reset-database.sh + populate per plugin | reset-database only (no populate) | YES |
| `make install-demo-data` | (not in SDK root) | core demo data + all `populate_db.py` | YES |
| `make install-demo-data FORCE=1` | (not in SDK root) | force overwrite all demo data | YES |
| `make install-demo-data PLUGIN=x` | (not in SDK root) | run specific plugin populator | YES |
| `make unit` | pytest + npm test per repo | pre-commit-check.sh --unit per dir | YES |
| `make integration` | pytest integration | pre-commit-check.sh --integration | YES |
| `make styles` | lint per repo | pre-commit-check.sh --lint/--style per dir | YES |
| `make ps` | docker compose ps per repo | docker compose ps + server status | YES |
| `make be-logs` | docker compose logs -f | backend log output | YES |
| `make pre-commit` | (not in SDK root) | alias for `make test` | YES |
| `make pre-commit-quick` | (not in SDK root) | alias for `make test-quick` | YES |

### Functional:

1. Core code lives in `.venv/` and `node_modules/` — gitignored, read-only
2. Developer's git repo contains ONLY: `plugins/`, config, entry points, `bin/`, `Makefile`, `docker-compose`
3. `make install` → `make up` → `make dev-be` / `make dev-fe-user` / `make dev-fe-admin` works from clean state
4. `make migrations` runs core + custom Alembic migrations
5. `make create-plugin NAME=x TYPE=be` scaffolds a plugin that passes `./bin/pre-commit-check.sh --full`
6. `make upgrade` / `make rebuild-core` updates core packages (pip + npm) without breaking plugins
7. `make total-rebuild` performs full clean setup from scratch (like SDK's total-rebuild)
8. Existing core test suites (292+ backend tests, frontend tests) pass when run from platform
9. Plugin developer never needs to clone SDK source repos

---

## Sprint Planning

Full sprint details: [`sprints/01-vbwd-platform-metapackage.md`](../sprints/01-vbwd-platform-metapackage.md)

---

## Commits

_No code changes in this report — architecture design only._