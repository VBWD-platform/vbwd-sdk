# Sprint 01: vbwd-platform Metapackage Implementation

**Date:** 2026-03-18
**Report:** `reports/01-vbwd-platform-metapackage-architecture.md`
**Status:** Planned

---

## Goal

Implement the Composer/vendor pattern for vbwd-platform: core (backend + frontends) becomes installable packages, plugin developers work in a minimal workspace with only their custom plugins, config, and `bin/pre-commit-check.sh` scripts.

---

## Engineering Principles

All code in this sprint MUST follow:

- **TDD-first** — write tests before implementation. Red → Green → Refactor. No code without a failing test first.
- **SOLID**:
  - **S** — Single Responsibility: each class/module does one thing
  - **O** — Open/Closed: extend via plugins, don't modify core
  - **L** — Liskov Substitution: subtypes must be substitutable for their base types (e.g. any `BasePlugin` subclass works wherever `BasePlugin` is expected)
  - **I** — Interface Segregation: small, focused interfaces (e.g. `IPlugin`, `IPlatformSDK`)
  - **D** — Dependency Inversion: depend on abstractions, not concretions
- **DRY** — Don't Repeat Yourself. Extract shared logic, no copy-paste.
- **Clean Code** — meaningful variable and function names. No single-letter vars, no cryptic abbreviations. Code reads like prose.
- **Open/Closed Principle** — the platform core is closed for modification, open for extension via plugins.
- **Liskov Substitution** — any plugin implementing `BasePlugin` (backend) or `IPlugin` (frontend) must be fully interchangeable with any other plugin of the same interface.

---

## Phases

### Phase 1: Backend as pip package

**Steps:**

1. Add `pyproject.toml` to `vbwd-backend/`
2. Rename `src/` → `vbwd/` for pip-compatible package name (short, clean namespace)
3. Update all internal imports: `from src.` → `from vbwd.`
4. Ensure `create_app()` accepts `plugins_dir` parameter for external plugin directories
5. Include core Alembic migrations as package data
6. Configure `alembic.ini` to support `version_locations` (core + custom + per-plugin)
7. Add `MANIFEST.in` to include templates, static files, and migrations
8. Test: `pip install -e .` from `vbwd-platform/be/`, run with external `app.py`
9. Publish to GitHub Packages (private PyPI)
10. Update `vbwd-backend/.github/workflows/ci.yml` to publish on tag

### Phase 2: Frontend app-as-library

**Steps:**

1. In `vbwd-fe-user/vue/src/`: extract `createVbwdUserApp()` factory from `main.ts`
   - Accepts `{ plugins, apiUrl, wsUrl }` config
   - Sets up router, stores, i18n, guards from core
   - Registers provided plugins via PluginRegistry
2. Export factory + Vite config presets from package entry point
3. Update `vbwd-fe-user/package.json` with `exports`, `main`, `module`, `types`, `publishConfig`
4. Create `vbwd-fe-user/vite-preset.ts` — exportable Vite config for platform consumers
5. Publish `vbwd-fe-user` to npm (alongside existing `vbwd-view-component`)
6. Repeat steps 1-5 for `vbwd-fe-admin`
7. Publish `vbwd-view-component` (`vbwd-fe-core`) to npm registry (currently `file:` only)
8. Test: create platform workspace, `npm install`, `npm run dev` with local plugins

### Phase 3: vbwd-platform scaffolding

**Steps:**

1. Create `vbwd-platform/` structure:
   ```
   vbwd-platform/
   ├── .env.example
   ├── .gitignore
   ├── docker-compose.yaml        # Infrastructure: postgres, redis, mailpit
   ├── docker-compose.prod.yaml   # Production: api, fe-user, fe-admin (Docker images)
   ├── Makefile
   ├── README.md
   ├── be/
   │   ├── app.py                 # from vbwd_backend import create_app
   │   ├── requirements.txt       # vbwd-backend==x.y.z
   │   ├── gunicorn.conf.py
   │   ├── bin/
   │   │   └── pre-commit-check.sh
   │   ├── plugins/
   │   │   ├── plugins.json
   │   │   ├── config.json
   │   │   └── requirements.txt   # Plugin-specific pip deps
   │   └── migrations/            # Custom Alembic migrations
   ├── fe-user/
   │   ├── main.ts
   │   ├── index.html
   │   ├── package.json           # vbwd-fe-user + vbwd-view-component
   │   ├── vite.config.ts
   │   ├── bin/
   │   │   └── pre-commit-check.sh
   │   └── plugins/
   │       ├── plugins.json
   │       └── .gitkeep
   ├── fe-admin/
   │   ├── main.ts
   │   ├── index.html
   │   ├── package.json           # vbwd-fe-admin + vbwd-view-component
   │   ├── vite.config.ts
   │   ├── bin/
   │   │   └── pre-commit-check.sh
   │   └── plugins/
   │       ├── plugins.json
   │       └── .gitkeep
   └── uploads/
   ```
2. Write `docker-compose.yaml` (infrastructure only for dev)
3. Write `docker-compose.prod.yaml` (full stack with Docker images)
4. Write `Makefile` with **full command parity** to the SDK root Makefile (see Phase 3b)
5. Write `.env.example` with all required vars
6. Write `.gitignore` (node_modules/, .venv/, uploads/, .env, dist/, *.pyc)
7. Write `README.md` with quick-start guide

### Phase 3b: Makefile — Full Command Parity with SDK

The platform Makefile MUST contain all the same commands as the SDK root Makefile (`vbwd-sdk-2/Makefile`). Plugin developers should have the exact same workflow as SDK developers.

**Required Makefile targets (mirroring SDK root Makefile):**

```makefile
.PHONY: install up down rebuild-backend rebuild-admin rebuild-user rebuild-core \
        code-rebuild total-rebuild be-logs ps migrations reset-db \
        unit integration styles test test-quick test-be test-fe-user test-fe-admin \
        pre-commit pre-commit-quick dev-be dev-fe-user dev-fe-admin \
        create-plugin install-plugin upgrade

# === Installation ===
install:                    # pip install (be) + npm install (fe-user, fe-admin)
npm-install:                # Install npm deps for fe-user + fe-admin

# === Service Management ===
up:                         # Start infrastructure (postgres, redis) + all dev servers
down:                       # Stop all services
ps:                         # Show status of all containers

# === Development (separate terminals) ===
dev-be:                     # Start Flask dev server on :5000 with plugins
dev-fe-user:                # Start Vite dev server on :8080 with plugins
dev-fe-admin:               # Start Vite dev server on :8081 with plugins

# === Rebuild ===
rebuild-backend:            # Full rebuild of backend (reinstall deps + restart)
rebuild-admin:              # Rebuild admin frontend (npm install + build + restart)
rebuild-user:               # Rebuild user frontend (npm install + build + restart)
rebuild-core:               # Reinstall core packages (pip upgrade + npm update)
code-rebuild:               # down + rebuild all code
total-rebuild:              # Full clean rebuild + database reset + plugin data population

# === Database ===
migrations:                 # Run Alembic migrations (core + custom)
reset-db:                   # Reset database schema (drop + recreate)
install-demo-data:          # Install core demo data + run all plugins populate_db.py
                            # If data exists: prompts to use --force or specify plugin name
                            # Usage: make install-demo-data
                            #        make install-demo-data FORCE=1
                            #        make install-demo-data PLUGIN=cms

# === Testing (same scripts as CI) ===
unit:                       # Unit tests across all packages (be + fe-user + fe-admin)
integration:                # Integration tests (backend only)
styles:                     # Lint/style checks across all packages
test:                       # Run all pre-commit-check.sh --full (be + fe-user + fe-admin)
test-quick:                 # Run all pre-commit-check.sh --quick (skip integration)
test-be:                    # be/bin/pre-commit-check.sh --full
test-fe-user:               # fe-user/bin/pre-commit-check.sh --full
test-fe-admin:              # fe-admin/bin/pre-commit-check.sh --full
pre-commit:                 # Alias for test
pre-commit-quick:           # Alias for test-quick

# === Logs ===
be-logs:                    # Tail backend logs

# === Plugin Management ===
create-plugin:              # Scaffold new plugin (NAME=x TYPE=be|fe-user|fe-admin)
install-plugin:             # Install official plugin from registry (NAME=cms)

# === Upgrade ===
upgrade:                    # Update core packages to latest (pip + npm)
```

**Implementation differences from SDK Makefile:**

| Command | SDK (vbwd-sdk-2) | Platform (vbwd-platform) |
|---------|------------------|--------------------------|
| `rebuild-backend` | `docker compose build --no-cache` | `pip install --upgrade -r requirements.txt` + restart |
| `rebuild-admin` | `npm install && npm run build && docker compose` | `npm install && npm run build` (Vite, no Docker) |
| `rebuild-user` | Same as above | Same as above |
| `rebuild-core` | `cd vbwd-fe-core && npm install && npm run build` | `pip install --upgrade vbwd-backend && npm update vbwd-view-component` |
| `migrations` | `docker compose exec api alembic upgrade heads` | `.venv/bin/alembic upgrade heads` (or Docker exec if prod mode) |
| `reset-db` | `./bin/reset-database.sh` + per-plugin populate | Same — plugins have own `bin/populate-db.sh` |
| `total-rebuild` | down + rebuild all + reset-db + populate | down + reinstall all packages + reset-db + populate |
| `unit` | `make test-unit` + `npm run test` per repo | `bin/pre-commit-check.sh --unit` per dir |
| `styles` | `make lint` + `npm run lint` per repo | `bin/pre-commit-check.sh --lint/--style` per dir |

### Phase 3c: Demo Data Installation (`make install-demo-data`)

Each backend plugin MUST have a unified `populate_db.py` file (not `populate-db.sh`, `seed.py`, or other names) for demo data population.

**Unified plugin convention:**
```
plugins/
├── cms/
│   └── populate_db.py        # Unified name for ALL plugins
├── ghrm/
│   └── populate_db.py
├── taro/
│   └── populate_db.py
├── email/
│   └── populate_db.py
└── loyalty-points/           # Custom plugin
    └── populate_db.py
```

**Each `populate_db.py` MUST:**
- Be executable as a standalone script: `python plugins/cms/populate_db.py`
- Accept `--force` flag to overwrite existing data
- Accept `--check` flag to report if data already exists (exit 0 = empty, exit 1 = data exists)
- Print clear output: what was inserted, how many records
- Be idempotent when run with `--force`
- Import from the core package: `from vbwd.app import create_app`

**`populate_db.py` template:**
```python
#!/usr/bin/env python3
"""Demo data populator for <plugin-name> plugin."""

import argparse
import sys

from vbwd.app import create_app


def check_data_exists(session):
    """Return True if demo data already exists."""
    # Plugin-specific check
    return False


def populate(session, force=False):
    """Insert demo data."""
    if check_data_exists(session) and not force:
        print("Data already exists. Use --force to overwrite.")
        sys.exit(1)
    # Insert demo records
    print("Demo data installed successfully.")


def main():
    parser = argparse.ArgumentParser(description="Populate demo data for <plugin-name>")
    parser.add_argument("--force", action="store_true", help="Overwrite existing data")
    parser.add_argument("--check", action="store_true", help="Check if data exists")
    arguments = parser.parse_args()

    app = create_app()
    with app.app_context():
        from vbwd.extensions import db
        if arguments.check:
            exists = check_data_exists(db.session)
            sys.exit(1 if exists else 0)
        populate(db.session, force=arguments.force)


if __name__ == "__main__":
    main()
```

**Makefile targets:**

```makefile
# Install core demo data + all plugin demo data
# If data exists, prompts user to use --force or run individual plugin
install-demo-data:
	@cd be && .venv/bin/flask --app app:create_app seed-core-data 2>/dev/null || true
ifdef PLUGIN
	@echo "Installing demo data for plugin: $(PLUGIN)"
	cd be && .venv/bin/python plugins/$(PLUGIN)/populate_db.py $(if $(FORCE),--force,)
else ifdef FORCE
	@echo "Installing ALL demo data (--force)..."
	@for populator in be/plugins/*/populate_db.py; do \
		plugin_name=$$(basename $$(dirname $$populator)); \
		echo "  Populating $$plugin_name..."; \
		cd be && .venv/bin/python $$populator --force; \
		cd ..; \
	done
else
	@has_data=0; \
	for populator in be/plugins/*/populate_db.py; do \
		plugin_name=$$(basename $$(dirname $$populator)); \
		if cd be && .venv/bin/python $$populator --check 2>/dev/null; then \
			cd ..; \
			echo "  Populating $$plugin_name..."; \
			cd be && .venv/bin/python $$populator; \
			cd ..; \
		else \
			cd ..; \
			echo "  $$plugin_name: data already exists (use FORCE=1 or PLUGIN=$$plugin_name)"; \
			has_data=1; \
		fi; \
	done; \
	if [ $$has_data -eq 1 ]; then \
		echo ""; \
		echo "Some plugins already have data. Options:"; \
		echo "  make install-demo-data FORCE=1           # Overwrite all"; \
		echo "  make install-demo-data PLUGIN=<name>     # Run specific plugin"; \
		echo "  make install-demo-data PLUGIN=cms FORCE=1 # Force specific plugin"; \
	fi
endif
```

**Usage examples:**
```bash
make install-demo-data                          # Install all, skip if data exists
make install-demo-data FORCE=1                  # Force overwrite all
make install-demo-data PLUGIN=cms               # Only CMS plugin
make install-demo-data PLUGIN=cms FORCE=1       # Force overwrite CMS only
```

**Migration task:** Rename existing populate scripts to unified `populate_db.py`:
- `plugins/taro/bin/populate-db.sh` → `plugins/taro/populate_db.py`
- `plugins/cms/bin/populate-db.sh` → `plugins/cms/populate_db.py`
- `plugins/ghrm/bin/populate-db.sh` → `plugins/ghrm/populate_db.py`
- `plugins/email/bin/populate-db.sh` → `plugins/email/populate_db.py`

### Phase 4: pre-commit-check.sh for platform

**Steps:**

1. Create `be/bin/pre-commit-check.sh`:
   - **Part A: Static Analysis** — black, flake8, mypy on `plugins/` directory (custom code only)
   - **Part B: Core Tests** — run core test suite from installed package (`python -m pytest --pyargs vbwd.tests`)
   - **Part C: Plugin Unit Tests** — `pytest plugins/*/tests/unit/ -v`
   - **Part D: Plugin Integration Tests** — `pytest plugins/*/tests/integration/ -v`
   - Flags: `--quick` (skip integration), `--lint`, `--unit`, `--integration`, `--core`, `--all`/`--full`
   - Docker-aware (same pattern as existing backend script)

2. Create `fe-user/bin/pre-commit-check.sh`:
   - **Part A: Style Checks** — ESLint + vue-tsc on `plugins/` directory
   - **Part B: Core Tests** — run core test suite from installed package
   - **Part C: Plugin Unit Tests** — `vitest run plugins/`
   - **Part D: Plugin Integration Tests** — `vitest run plugins/*/tests/integration/`
   - Flags: `--style`, `--unit`, `--integration`, `--core`, `--all`/`--full`

3. Create `fe-admin/bin/pre-commit-check.sh`:
   - Same structure as fe-user

4. Root-level Makefile targets:
   ```makefile
   test:           # Run all pre-commit-check.sh --full across be + fe-user + fe-admin
   test-quick:     # Run all pre-commit-check.sh --quick
   test-be:        # Run be/bin/pre-commit-check.sh --full
   test-fe-user:   # Run fe-user/bin/pre-commit-check.sh --full
   test-fe-admin:  # Run fe-admin/bin/pre-commit-check.sh --full
   pre-commit:     # Alias for test
   ```

### Phase 5: GitHub Actions CI for vbwd-platform

**Steps:**

1. Create `.github/workflows/ci.yml` in `vbwd-platform/`:
   ```yaml
   # Job structure:
   #   1. install           → pip install + npm install in all dirs
   #   2. be-lint           → needs 1 │ be/bin/pre-commit-check.sh --lint
   #   3. be-unit           → needs 1 │ be/bin/pre-commit-check.sh --unit (core + plugins)
   #   4. be-integration    → needs 3 │ be/bin/pre-commit-check.sh --integration
   #   5. fe-user-lint      → needs 1 │ fe-user/bin/pre-commit-check.sh --style
   #   6. fe-user-unit      → needs 1 │ fe-user/bin/pre-commit-check.sh --unit (core + plugins)
   #   7. fe-admin-lint     → needs 1 │ fe-admin/bin/pre-commit-check.sh --style
   #   8. fe-admin-unit     → needs 1 │ fe-admin/bin/pre-commit-check.sh --unit (core + plugins)
   #   9. test-summary      → needs all │ aggregate results
   ```

2. GitHub Actions services: postgres + redis (same as existing ci.yml)
3. Matrix strategy for frontend jobs (optional, if fe-user and fe-admin share config)
4. Upload test artifacts (test results, coverage reports)

### Phase 6: Plugin templates & CLI

**Steps:**

1. Create plugin scaffolding templates:
   - `templates/backend-plugin/` — `__init__.py`, `src/`, `tests/`, `requirements.txt`
   - `templates/fe-user-plugin/` — `index.ts`, `src/`, `tests/`, `locales/`
   - `templates/fe-admin-plugin/` — `index.ts`, `src/`, `tests/`, `locales/`
2. Add `make create-plugin NAME=x TYPE=be|fe-user|fe-admin`
3. Add `make install-plugin NAME=cms` — clone official plugin from GitHub

---

## Acceptance Criteria

### All tests on GitHub Actions in vbwd-platform MUST be green:

| Job | What it runs | Must pass |
|-----|-------------|-----------|
| install | `pip install` + `npm install` in all dirs | YES |
| be-lint | `be/bin/pre-commit-check.sh --lint` (black, flake8, mypy on plugins/) | YES |
| be-unit | `be/bin/pre-commit-check.sh --unit` (core tests + plugin tests) | YES |
| be-integration | `be/bin/pre-commit-check.sh --integration` (core + plugin integration) | YES |
| fe-user-lint | `fe-user/bin/pre-commit-check.sh --style` (ESLint, vue-tsc on plugins/) | YES |
| fe-user-unit | `fe-user/bin/pre-commit-check.sh --unit` (core + plugin unit tests) | YES |
| fe-admin-lint | `fe-admin/bin/pre-commit-check.sh --style` (ESLint, vue-tsc on plugins/) | YES |
| fe-admin-unit | `fe-admin/bin/pre-commit-check.sh --unit` (core + plugin unit tests) | YES |
| test-summary | Aggregates all results, fails if any job failed | YES |

### Local pre-commit-check.sh MUST be green:

```bash
# Each directory has its own bin/pre-commit-check.sh
cd be && ./bin/pre-commit-check.sh --full       # lint + core tests + plugin tests
cd fe-user && ./bin/pre-commit-check.sh --full  # style + core tests + plugin tests
cd fe-admin && ./bin/pre-commit-check.sh --full # style + core tests + plugin tests

# Root Makefile runs all three:
make test           # Runs all pre-commit-check.sh --full
make test-quick     # Runs all pre-commit-check.sh --quick (skip integration)
```

### Pre-commit-check.sh feature requirements:

| Feature | be/ | fe-user/ | fe-admin/ |
|---------|-----|----------|-----------|
| `--lint` / `--style` | black + flake8 + mypy on `plugins/` | ESLint + vue-tsc on `plugins/` | ESLint + vue-tsc on `plugins/` |
| `--unit` | core unit + plugin unit tests | core unit + plugin unit tests | core unit + plugin unit tests |
| `--integration` | core integration + plugin integration | plugin integration tests | plugin integration tests |
| `--core` | core tests only (from installed package) | core tests only | core tests only |
| `--quick` | lint + unit (skip integration) | style + unit (skip integration) | style + unit (skip integration) |
| `--full` / `--all` | lint + unit + integration (core + plugins) | style + unit + integration | style + unit + integration |
| Docker-aware | YES (detect `/.dockerenv`) | YES | YES |
| Exit codes | 0=pass, 1=lint, 2=unit, 3=integration | 0=pass, 1=style, 2=unit, 3=integration | same |
| Color output | YES | YES | YES |
| Duration tracking | YES | YES | YES |

### Functional acceptance criteria:

1. `make install` completes successfully from a clean state
2. `make up` starts postgres + redis infrastructure
3. `make dev-be` starts Flask dev server on port 5000 with plugins from `be/plugins/`
4. `make dev-fe-user` starts Vite dev server on port 8080 with plugins from `fe-user/plugins/`
5. `make dev-fe-admin` starts Vite dev server on port 8081 with plugins from `fe-admin/plugins/`
6. `make migrations` runs core + custom Alembic migrations
7. `make install-demo-data` installs core demo data + runs all `populate_db.py` in plugins
8. `make install-demo-data FORCE=1` overwrites existing data
9. `make install-demo-data PLUGIN=cms` runs only the CMS plugin populator
10. `make test` runs all pre-commit-check.sh scripts and all pass
11. `make create-plugin NAME=example TYPE=be` scaffolds a working plugin that passes tests
9. Core code is in `.venv/` and `node_modules/` (gitignored, read-only)
10. Developer's git repo contains ONLY: plugins/, config, entry points, bin/, Makefile, docker-compose
11. Existing core test suites (backend 292+ tests, fe-user, fe-admin) pass when run from platform
12. Plugin tests run alongside core tests via pre-commit-check.sh
13. GitHub Actions CI pipeline is green on a fresh push

### Non-functional acceptance criteria:

14. `make install` completes in under 5 minutes on a fresh machine
15. `make dev-be` starts in under 10 seconds (no rebuild)
16. `make dev-fe-user` starts in under 5 seconds (Vite HMR)
17. Plugin developer never needs to clone vbwd-backend, vbwd-fe-user, vbwd-fe-admin, or vbwd-fe-core source repos
18. Core updates via `make upgrade` (pip upgrade + npm update) — no manual steps

### Dual installation: both MUST work simultaneously

**CRITICAL:** The `feature/platform` branches in `vbwd-backend`, `vbwd-fe-user`, `vbwd-fe-admin` must keep BOTH installation modes working at all times:

**Mode 1 — SDK developer installation (current):**
```bash
cd vbwd-sdk-2
./recipes/dev-install-ce.sh
make up
# vbwd-backend/bin/pre-commit-check.sh --full   → GREEN
# vbwd-fe-user/bin/pre-commit-check.sh --full    → GREEN
# vbwd-fe-admin/bin/pre-commit-check.sh --full   → GREEN
# GitHub Actions CI on vbwd-sdk-2                 → GREEN
```

**Mode 2 — Metapackage installation (new):**
```bash
cd vbwd-platform
make install    # pip install from feature/platform branch + npm install
make up
make test       # all pre-commit-check.sh --full → GREEN
# GitHub Actions CI on vbwd-platform              → GREEN
```

**How both work with `feature/platform` branches:**

During development, the metapackage `requirements.txt` and `package.json` point to the `feature/platform` branches directly:

```
# be/requirements.txt (during development)
vbwd-backend @ git+https://github.com/dantweb/vbwd-backend.git@feature/platform

# fe-user/package.json (during development)
"vbwd-fe-user": "github:dantweb/vbwd-fe-user#feature/platform"
```

After merge to `main` and first release, these switch to versioned packages.

**Acceptance criteria for dual mode:**

| Check | SDK mode | Metapackage mode |
|-------|----------|------------------|
| `vbwd-backend/bin/pre-commit-check.sh --full` | GREEN (all 292+ tests + plugins) | N/A (runs from be/) |
| `vbwd-fe-user/bin/pre-commit-check.sh --full` | GREEN | N/A (runs from fe-user/) |
| `vbwd-fe-admin/bin/pre-commit-check.sh --full` | GREEN | N/A (runs from fe-admin/) |
| `be/bin/pre-commit-check.sh --full` | N/A | GREEN (core + plugins) |
| `fe-user/bin/pre-commit-check.sh --full` | N/A | GREEN (core + plugins) |
| `fe-admin/bin/pre-commit-check.sh --full` | N/A | GREEN (core + plugins) |
| GitHub CI (vbwd-sdk-2) | GREEN | N/A |
| GitHub CI (vbwd-platform) | N/A | GREEN |

**No regressions allowed.** Every commit on `feature/platform` must pass the existing SDK pre-commit checks. The `src/` → `vbwd/` rename is the biggest risk — must be done as an atomic commit with all imports updated and all tests passing.

---

## Dependencies

- `vbwd-backend` must have `pyproject.toml` and be publishable as pip package
- `vbwd-fe-core` (`vbwd-view-component`) must be published to npm (currently `file:` only)
- `vbwd-fe-user` must export `createVbwdUserApp()` factory
- `vbwd-fe-admin` must export `createVbwdAdminApp()` factory
- GitHub Packages (or alternative registry) must be configured for pip + npm publishing
- Existing CI in `vbwd-sdk-2/.github/workflows/ci.yml` must remain green (no regressions)

---

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Backend as pip package | 2-3 days |
| Phase 2: Frontend app-as-library | 3-4 days |
| Phase 3: Platform scaffolding | 1-2 days |
| Phase 4: pre-commit-check.sh | 1 day |
| Phase 5: GitHub Actions CI | 1 day |
| Phase 6: Plugin templates & CLI | 1 day |
| **Total** | **9-12 days** |

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Backend import rename (`src.` → `vbwd.`) breaks all code | High | Automated find-replace + run full test suite. Using `vbwd.` (short) instead of `vbwd_backend.` to minimize diff size |
| Frontend app-as-library pattern doesn't work with Vite glob | High | Fallback: platform workspace has its own `main.ts` with local glob |
| Core test suite can't run from installed package | Medium | Include tests as package data, verify with `pytest --pyargs` |
| GitHub Packages private PyPI has rate limits | Low | Cache packages in CI, use self-hosted Verdaccio/devpi if needed |
| Plugin developers confused by new workflow | Medium | Comprehensive README + `make create-plugin` scaffolding |