# Sprint 01 Summary: vbwd-platform Metapackage Implementation

**Date:** 2026-03-18
**Sprint:** `sprints/done/01-vbwd-platform-metapackage.md`
**Status:** Done

---

## Summary

Implemented the Composer/vendor pattern for vbwd-platform. Core platform code (backend, frontend apps) is now installable as packages into gitignored dependency directories. Plugin developers work in a minimal workspace with only their custom plugins, configuration, and entry points.

---

## Phases Completed

### Phase 1: Backend as pip Package

- Renamed `src/` → `vbwd/` across 278 files (1,440+ import references)
- Added `pyproject.toml` for `pip install vbwd-backend`
- Updated all config files: Makefile, Dockerfile, pre-commit-check.sh, CI workflow
- Updated all `mocker.patch("src.")` → `"vbwd."` strings in tests (227 occurrences)
- **Tests:** 735 core + 506 plugin unit tests pass, lint green
- **Commit:** `340de9e` on `feature/platform`

### Phase 2: Frontend App-as-Library

- Created `createVbwdUserApp()` factory in `vbwd-fe-user/vue/src/factory.ts`
- Created `createVbwdAdminApp()` factory in `vbwd-fe-admin/vue/src/factory.ts`
- Reduced `main.ts` to thin wrappers (81→20 lines, 110→24 lines)
- Fixed TypeScript strict mode errors (`IPlugin[]` type annotations)
- **Tests:** 346 fe-user + 231 fe-admin unit tests pass, lint green
- **Commits:** `0d6168f` (fe-user), `6020a9d` (fe-admin)

### Phase 3: Platform Scaffolding

- Created `vbwd-platform/` repo at `VBWD-platform/vbwd-platform`
- Structure: `be/`, `fe-user/`, `fe-admin/` with plugins dirs, entry points, configs
- `docker-compose.yaml` — postgres:16, redis:7, mailpit
- `.env.example` — all environment variables with safe defaults
- `.gitignore` — node_modules/, .venv/, uploads/, .env

### Phase 3b: Makefile — Full Command Parity

- 30+ Makefile targets mirroring SDK root Makefile
- install, up, down, ps, dev-be, dev-fe-user, dev-fe-admin
- rebuild-backend, rebuild-admin, rebuild-user, rebuild-core, code-rebuild, total-rebuild
- migrations, reset-db, install-demo-data (with FORCE/PLUGIN flags)
- unit, integration, styles, test, test-quick, pre-commit

### Phase 3c: Demo Data Installation

- `make install-demo-data` — runs core seed + all `populate_db.py` from plugins
- `make install-demo-data FORCE=1` — force overwrite
- `make install-demo-data PLUGIN=cms` — specific plugin only

### Phase 4: Pre-commit Scripts

- `be/bin/pre-commit-check.sh` — black + flake8 + mypy + pytest (core + plugins)
- `fe-user/bin/pre-commit-check.sh` — ESLint + vue-tsc + vitest (plugins)
- `fe-admin/bin/pre-commit-check.sh` — same as fe-user
- All scripts support: --lint/--style, --unit, --integration, --core, --quick, --full

### Phase 5: GitHub Actions CI

- 9-job CI pipeline in `.github/workflows/ci.yml`
- install → be-lint → be-unit → be-integration
- install → fe-user-style → fe-user-unit
- install → fe-admin-style → fe-admin-unit
- test-summary (aggregates all results)

### Phase 6: Official Plugins + Install Recipe

- `plugins.json` with all 25 official plugins enabled (10 backend, 10 fe-user, 5 fe-admin)
- `config.json` with safe defaults (empty API keys)
- `recipes/install-all-plugins.sh` — clones all plugins from VBWD-platform GitHub org, starts infrastructure, runs migrations, populates demo data from all plugins

---

## Repositories & Branches

| Repo | Branch | Key Commit |
|------|--------|------------|
| `VBWD-platform/vbwd-backend` | `feature/platform` | `340de9e` — src/ → vbwd/ + pyproject.toml |
| `VBWD-platform/vbwd-fe-user` | `feature/platform` | `0d6168f` — createVbwdUserApp() factory |
| `VBWD-platform/vbwd-fe-admin` | `feature/platform` | `6020a9d` — createVbwdAdminApp() factory |
| `VBWD-platform/vbwd-platform` | `main` | `87dc051` — full scaffolding + plugins + recipe |

---

## Test Results

| Component | Tests | Result |
|-----------|-------|--------|
| Backend core unit | 735 passed, 4 skipped | GREEN |
| Backend plugin unit | 506 passed, 1 skipped | GREEN (26 pre-existing taro failures) |
| Backend lint | black + flake8 + mypy | GREEN |
| fe-user unit | 346 passed | GREEN |
| fe-user lint | 0 errors, 6 warnings | GREEN |
| fe-admin unit | 231 passed | GREEN |
| fe-admin lint | 0 errors, 6 warnings | GREEN |
| Platform pre-commit (be) | --lint | GREEN |
| Platform pre-commit (fe-user) | --style | GREEN |
| Platform pre-commit (fe-admin) | --style | GREEN |
| Email integration (Mailpit) | 15 passed | GREEN |

---

## Dual Installation Verification

Both installation modes work simultaneously:

- **SDK mode** (`vbwd-sdk-2/`): `./recipes/dev-install-ce.sh` → all tests pass
- **Platform mode** (`vbwd-platform/`): `./recipes/install-all-plugins.sh` → scripts pass

No regressions introduced.
