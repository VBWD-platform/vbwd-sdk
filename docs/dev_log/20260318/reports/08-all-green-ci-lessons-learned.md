# All Green CI — Lessons Learned & Requirements

**Date:** 2026-03-18
**Status:** All 30 repos GREEN on main

---

## Final CI Status

```
30/30 repos: completed/success on main
```

All repositories in the VBWD-platform GitHub organization pass CI:
- 1 platform metapackage
- 1 backend core + 10 backend plugins
- 3 frontend apps (core, user, admin) + 15 frontend plugins

---

## What Was Done Today

### 1. Backend Package Rename (`src/` → `vbwd/`)

Renamed the core backend directory for pip packaging. This was the highest-risk change — touching every file in the codebase.

**Scope:** 278 files changed, 1,615 insertions, 1,539 deletions

**What broke and why:**

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| 72 unit tests failed | `mocker.patch("src.middleware...")` string references not updated | `sed` replace `"src.` → `"vbwd.` in all test files (227 occurrences) |
| 1 unit test failed | `importlib.reload(src.config)` — variable name, not import | Manual fix: `src.config` → `vbwd.config` |
| Black formatting failed | Rename changed line lengths | Run `black vbwd/ tests/` |
| Integration test failed | `from src import models` in `test_model_table_consistency.py` | Manual fix — was missed by the bulk `sed` because it used `from src` not `from src.` |

**Requirement:** When renaming a Python package, you must update THREE types of references:
1. `from X.` / `import X.` statements (bulk `sed`)
2. `"X.something"` strings in `mocker.patch()` calls (bulk `sed` with `"src.` → `"vbwd.`)
3. Bare `import X` / `from X import Y` without a dot (manual grep + fix)

### 2. Plugin Repos — Import Update

All 10 backend plugin repos still had `from src.` imports after the core rename.

**What broke:** Platform CI cloned plugins from GitHub → `No module named 'src'`

**Fix:** Updated all 10 plugin repos with the same `sed` command, pushed to GitHub.

**Requirement:** After renaming the core package, ALL plugin repos must be updated in the same session. Don't assume "I'll do it later" — CI will fail immediately.

### 3. Plugin CI Workflows — Branch Reference

Each plugin's `.github/workflows/tests.yml` clones `vbwd-backend` to run tests. After the rename, the `main` branch on GitHub still had the old `src/` code (the rename was on `feature/platform`).

**What broke:** Plugin CI cloned `main` → got old `src/` → `No module named 'vbwd'`

**Fix:** Updated all 10 plugin CI workflows: `ref: feature/platform` → later `ref: main` after merge.

**Requirement:** When core changes affect plugin CI, update ALL plugin CI workflows in the same commit batch. Use a loop:
```bash
for plugin in analytics chat cms email ghrm mailchimp paypal stripe taro yookassa; do
  cd "$plugin" && git add . && git commit -m "fix" && git push && cd ..
done
```

### 4. Frontend TypeScript Strict Mode

The `main.ts` refactoring (extracting factory functions) introduced `let plugins = []` without a type annotation.

**What broke:** `vue-tsc --noEmit` failed: `Variable 'plugins' implicitly has type 'any[]'`

**Fix:** Added explicit type: `let plugins: IPlugin[] = []`

**Requirement:** Always use explicit types in TypeScript. Never `let x = []` — always `let x: SomeType[] = []`.

### 5. Black + Flake8 in New Test Files

The new `test_all_events_mailpit.py` file had formatting issues.

**What broke:**
- Black: trailing parenthesis placement
- Flake8: line > 120 chars, f-string without placeholders

**Fix:** Run `black` on the file, fix flake8 manually.

**Requirement:** Before committing any new Python file, run:
```bash
docker compose run --rm test black <file>
docker compose run --rm test flake8 <file> --max-line-length=120 --extend-ignore=E203,W503
```

### 6. Alembic — `head` vs `heads`

Multiple plugins have independent migration chains, creating multiple Alembic heads.

**What broke:** `alembic upgrade head` (singular) → `Multiple head revisions are present`

**Fix:** `alembic upgrade heads` (plural)

**Requirement:** Always use `alembic upgrade heads` (plural) — never `head` (singular). This applies to:
- Dockerfile CMD
- CI workflows
- Makefile targets
- Install scripts

### 7. Docker — Platform Service Names

The platform's `docker-compose.yaml` uses service names like `fe-user-dev`, `fe-admin-dev`, `api`. But the SDK's nginx configs reference `dev` and `host.docker.internal`.

**What broke:** nginx 502 Bad Gateway — couldn't resolve `dev:5173`

**Fix:** Created platform-specific `nginx.conf` files with correct service names (`fe-user-dev:5173`, `api:5000`).

**Requirement:** When services are in the same Docker Compose network, use service names (not `host.docker.internal`). Each deployment (SDK vs platform) needs its own nginx config if service names differ.

### 8. Docker — npm Platform Mismatch

`npm install` on macOS creates `package-lock.json` with darwin binaries. Alpine Linux containers can't find `@rollup/rollup-linux-arm64-musl`.

**What broke:** `fe-admin-dev` container crashed on startup

**Fix:** `rm -f package-lock.json && npm install` in Docker command.

**Requirement:** When mounting host `node_modules` or running `npm install` inside Docker, always delete `package-lock.json` first if it was created on a different platform.

### 9. CI — Shell Glob in Docker

`docker compose run test pytest plugins/*/tests/unit/` passes `plugins/*/tests/unit/` as a literal string to pytest (no shell expansion inside Docker run).

**What broke:** `ERROR: file or directory not found: plugins/*/tests/unit/`

**Fix:** Use `bash -c` to expand the glob:
```yaml
docker compose run --rm test bash -c 'pytest plugins/*/tests/unit/ -q --tb=short'
```

**Requirement:** When passing glob patterns to commands inside Docker, wrap in `bash -c '...'` to ensure shell expansion.

### 10. GitHub Org — Wrong Remote URLs

Platform config files referenced `dantweb/vbwd-backend` instead of `VBWD-platform/vbwd-backend`.

**What broke:** `pip install` failed — repo not found at `dantweb/vbwd-backend@feature/platform`

**Fix:** Updated all `requirements.txt` and `package.json` to use `VBWD-platform/` org.

**Requirement:** After transferring repos to a GitHub organization, grep ALL config files for the old owner name:
```bash
grep -rn "dantweb" . --include="*.txt" --include="*.json" --include="*.yml" --include="*.sh"
```

---

## Checklist for Future Changes

Before pushing any change that touches core infrastructure:

- [ ] Run `docker compose run --rm test ./bin/pre-commit-check.sh --quick` locally
- [ ] Run `black` and `flake8` on any new/modified Python files
- [ ] Use `alembic upgrade heads` (plural) everywhere
- [ ] Use explicit TypeScript types (no `let x = []`)
- [ ] When renaming imports, check: `.py` imports, `mocker.patch()` strings, config files, shell scripts, Dockerfiles, CI workflows
- [ ] When modifying core, update ALL plugin repos in the same session
- [ ] When using globs in Docker, wrap in `bash -c`
- [ ] Use correct GitHub org name (`VBWD-platform/`) in all URLs
- [ ] Delete `package-lock.json` before `npm install` inside Docker on ARM
- [ ] Use service names (not `host.docker.internal`) in Docker Compose network nginx configs

---

## Commits That Fixed CI (chronological)

| Repo | Commit | Fix |
|------|--------|-----|
| vbwd-backend | `340de9e` | src/ → vbwd/ rename + pyproject.toml |
| vbwd-backend | `1f25bff` | Last `from src import models` in integration test |
| vbwd-backend | `10cb891` | alembic upgrade head → heads |
| vbwd-fe-user | `0d6168f` | createVbwdUserApp() factory |
| vbwd-fe-admin | `6020a9d` | createVbwdAdminApp() factory + IPlugin[] type |
| 10 plugins | various | `from src.` → `from vbwd.` imports |
| 10 plugins | various | CI workflow: clone main branch |
| vbwd-plugin-email | `729fe6b` | flake8 line length + f-string fix |
| vbwd-platform | `3fb0382` | installedAt in plugins.json + build fe-core submodule |
| vbwd-platform | `837573d` | sed patch plugin imports in CI |
| vbwd-platform | `e290553` | platform-specific nginx configs |
| vbwd-platform | `13d1624` | rm package-lock.json before npm install in Docker |
| vbwd-platform | `3ce00af` | split core/plugin pytest into separate steps |
| vbwd-platform | `f0dcf9d` | VBWD-platform org + main branch everywhere |
