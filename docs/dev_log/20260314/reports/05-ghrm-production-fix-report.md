# Report 05 — GHRM Production Fix
**Date:** 2026-03-14

---

## Summary

Two production issues discovered and resolved in the GHRM (GitHub Repo Manager) plugin:
1. **Wrong content served** — sync was always returning mock data, never real GitHub content
2. **500 on package listing** — removing the mock broke unauthenticated catalogue routes

Additionally, a root-level `Makefile` was extended with three new cross-repo test targets.

---

## Issue 1 — GHRM Sync Always Returned Mock Content

### Root Cause

All production service factories (`_pkg_svc()`, `_access_svc()`, `on_enable()`, `scheduler.py`) were hardcoded to instantiate `MockGithubAppClient`. The real `GithubAppClient` existed but was never wired in production.

A secondary bug: `GithubAppClient.get_installation_token()` used `_repo_headers()` to authenticate the token-fetch request — a circular dependency, since `_repo_headers()` requires the installation token it was trying to fetch.

### Fixes

**`github_app_client_real.py`** — full rewrite of `GithubAppClient`:
- Constructor now takes `app_id`, `private_key` (PEM content), `installation_id`
- Added `_make_jwt()` — RS256 JWT signed with the app private key (required by GitHub App API)
- Added `_ensure_installation_token()` — lazy initialiser
- Fixed `get_installation_token()` to authenticate with JWT bearer headers, not installation token

**`routes.py`** — added `_make_github_client(cfg)` factory:
- Reads `github_app_id`, `github_installation_id`, `github_app_private_key_path` from plugin config
- Raises `GithubNotConfiguredError` if any credential is absent or PEM file missing
- Returns a real `GithubAppClient` otherwise

**`__init__.py`** — `on_enable()`:
- Now calls `_make_github_client(cfg)` from routes module
- Catches `GithubNotConfiguredError` with a `WARNING` log instead of silently skipping

**`scheduler.py`** — `revoke_expired_grace_access()`:
- Now calls `_make_github_client(_cfg())` and catches `GithubNotConfiguredError` to skip gracefully with a `WARNING` log
- Removed `MockGithubAppClient` import entirely

---

## Issue 2 — 500 on `GET /api/v1/ghrm/packages`

### Root Cause

After removing the mock fallback, `_pkg_svc()` called `_make_github_client(cfg)` eagerly at request time. If `_cfg()` returned `{}` (plugin manager not ready, or credentials not yet loaded), `GithubNotConfiguredError` propagated as an unhandled exception → HTTP 500.

`list_packages`, `get_package`, `get_related`, `get_versions` never use `self._github` — only `sync_package` does. There was no reason to require a GitHub client for catalogue reads.

### Fix

**`software_package_service.py`**:
- `github` parameter changed to `Optional[IGithubAppClient]`
- `sync_package()` guards `self._github is None` → raises `GhrmSyncAuthError("GitHub App not configured")`

**`routes.py`** — `_pkg_svc()`:
- Catches `GithubNotConfiguredError` and passes `github=None` to the service
- Catalogue and detail routes work without any GitHub credentials

**`routes.py`** — access/auth routes (`_access_svc()` callers):
- Each route now explicitly catches `GithubNotConfiguredError` → returns HTTP 503
- `get_access_status` returns `{"connected": False}` (200) when not configured — safe default for the UI

**`routes.py`** — `sync_package` route:
- Added `GithubNotConfiguredError` → 503 response

---

## `MockGithubAppClient` Audit

Before this fix, non-test files that imported `MockGithubAppClient`:

| File | Status |
|------|--------|
| `plugins/ghrm/src/routes.py` | ✅ Removed |
| `plugins/ghrm/src/scheduler.py` | ✅ Removed |
| `plugins/ghrm/__init__.py` | ✅ Removed |

`MockGithubAppClient` remains defined in `github_app_client.py` (correct — used by unit/integration tests only).

Verified with grep — no non-test file imports `MockGithubAppClient`.

---

## Makefile — Cross-Repo Test Targets

Three new targets added to the root `Makefile`:

| Target | What it runs |
|--------|-------------|
| `make unit` | `make test-unit` (backend) + `npm run test` (fe-core, fe-admin, fe-user) |
| `make integration` | `make test-integration` (backend) |
| `make styles` | `make lint` (backend) + `npm run lint` (fe-core, fe-admin, fe-user) |

---

## Pre-Commit Status

`./bin/pre-commit-check.sh --quick` — **PASS** (1086 unit tests, 5 skipped)

---

## Config Verification

`plugins/config.json` GHRM section confirmed correct:
- `github_app_id`, `github_installation_id`, OAuth credentials present
- `github_app_private_key_path: /app/plugins/ghrm/auth/github-app.pem` — file confirmed present in container
- `auth/` directory excluded from git tracking (contains private key)
